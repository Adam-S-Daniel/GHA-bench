#Requires -Version 7.0

<#
.SYNOPSIS
    Artifact retention / cleanup engine.

.DESCRIPTION
    Pure, side-effect-free functions that decide which CI artifacts to delete
    given a set of retention policies, and that render a human/machine readable
    deletion plan. Built incrementally with red/green TDD — see
    tests/ArtifactCleanup.Tests.ps1.

    An "artifact" is any object with the properties:
        Name          [string]   - artifact name
        SizeBytes     [long]      - size on disk in bytes
        CreatedAt     [datetime]  - creation timestamp
        WorkflowRunId [string]    - the workflow run that produced it

    The engine never performs deletion itself; Get-CleanupPlan computes a plan
    and Invoke-ArtifactCleanup optionally executes a caller-supplied delete
    action (skipped entirely in -DryRun). This keeps the policy logic trivially
    testable and makes "dry-run" the safe default.
#>

Set-StrictMode -Version Latest

# Canonical names for the reasons an artifact can be marked for deletion. Kept
# as constants so the engine, the report renderer and the tests all agree.
$script:ReasonMaxAge       = 'MaxAge'
$script:ReasonKeepLatestN  = 'KeepLatestN'
$script:ReasonMaxTotalSize = 'MaxTotalSize'

function Get-CleanupPlan {
    <#
    .SYNOPSIS
        Decide which artifacts to delete under the given retention policies.

    .DESCRIPTION
        Applies up to three independent, composable policies. An artifact is
        deleted if ANY policy marks it (union of reasons); it is retained only
        if no policy objects to it. Policies are applied in this order:

          1. MaxAgeDays        - delete anything older than N days.
          2. KeepLatestN       - within each WorkflowRunId group, keep the N
                                  newest and delete the rest.
          3. MaxTotalSizeBytes - of whatever still survives (1) and (2), delete
                                  oldest-first until the retained total fits the
                                  cap.

        A policy is only active when its parameter is supplied; omit it to skip
        that policy. The function mutates nothing and returns a plan object.

    .OUTPUTS
        [pscustomobject] with: Delete, Retain, Summary, AppliedPolicies, ReferenceDate.
    #>
    [CmdletBinding()]
    param(
        # The artifacts to evaluate. Empty is allowed (yields an empty plan).
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Artifact,

        # Delete artifacts strictly older than this many days. >= 0.
        [int] $MaxAgeDays,

        # Cap on total retained size in bytes; oldest survivors are deleted
        # until the retained total is <= this value. >= 0.
        [long] $MaxTotalSizeBytes,

        # Per workflow run, keep this many newest artifacts and delete the rest. >= 0.
        [int] $KeepLatestN,

        # Reference "now" for age calculations. Defaults to the current time;
        # tests pass a fixed value for determinism.
        [datetime] $Now = (Get-Date)
    )

    # ---- validate policy parameters up front with actionable messages -------
    if ($PSBoundParameters.ContainsKey('MaxAgeDays') -and $MaxAgeDays -lt 0) {
        throw "MaxAgeDays must be >= 0 (got $MaxAgeDays)."
    }
    if ($PSBoundParameters.ContainsKey('MaxTotalSizeBytes') -and $MaxTotalSizeBytes -lt 0) {
        throw "MaxTotalSizeBytes must be >= 0 (got $MaxTotalSizeBytes)."
    }
    if ($PSBoundParameters.ContainsKey('KeepLatestN') -and $KeepLatestN -lt 0) {
        throw "KeepLatestN must be >= 0 (got $KeepLatestN)."
    }

    # Normalise to a real array so .Count / indexing behave for 0 and 1 items.
    $artifacts = @($Artifact)

    # Build a mutable decision record per artifact. Reasons accumulates the
    # name of every policy that voted to delete this artifact.
    $decisions = foreach ($a in $artifacts) {
        Assert-ArtifactShape -Artifact $a
        [pscustomobject]@{
            Artifact = $a
            Reasons  = [System.Collections.Generic.List[string]]::new()
        }
    }
    $decisions = @($decisions)

    # ---- Policy 1: MaxAgeDays ----------------------------------------------
    # Delete anything created strictly before (Now - MaxAgeDays). An artifact
    # exactly at the cutoff is kept (the boundary is "keep"), so a 30-day limit
    # never deletes a 30-day-old artifact, only 31+ day-old ones.
    if ($PSBoundParameters.ContainsKey('MaxAgeDays')) {
        $cutoff = $Now.AddDays(-$MaxAgeDays)
        foreach ($d in $decisions) {
            if ($d.Artifact.CreatedAt -lt $cutoff) {
                $d.Reasons.Add($script:ReasonMaxAge)
            }
        }
    }

    # ---- Policy 2: KeepLatestN per workflow run -----------------------------
    # Within each WorkflowRunId group, order newest-first and keep the first N;
    # everything after that is marked for deletion. Ties on CreatedAt are broken
    # by Name (descending) purely so the keep/drop split is deterministic.
    if ($PSBoundParameters.ContainsKey('KeepLatestN')) {
        $groups = $decisions | Group-Object { $_.Artifact.WorkflowRunId }
        foreach ($group in $groups) {
            $ordered = $group.Group | Sort-Object `
                @{ Expression = { $_.Artifact.CreatedAt }; Descending = $true },
                @{ Expression = { $_.Artifact.Name };      Descending = $true }
            $ordered = @($ordered)
            for ($i = $KeepLatestN; $i -lt $ordered.Count; $i++) {
                $ordered[$i].Reasons.Add($script:ReasonKeepLatestN)
            }
        }
    }

    # ---- Policy 3: MaxTotalSizeBytes ----------------------------------------
    # Operates only on what still survives policies 1 and 2. If their combined
    # size exceeds the cap, evict oldest-first (ties broken by Name ascending)
    # until the retained total is <= the cap. Eviction order is independent of
    # the other policies — size pressure relieves from the oldest survivor.
    if ($PSBoundParameters.ContainsKey('MaxTotalSizeBytes')) {
        $survivors = @($decisions | Where-Object { $_.Reasons.Count -eq 0 })
        $retainedTotal = [long]0
        foreach ($d in $survivors) { $retainedTotal += [long]$d.Artifact.SizeBytes }

        if ($retainedTotal -gt $MaxTotalSizeBytes) {
            $ordered = @($survivors | Sort-Object `
                @{ Expression = { $_.Artifact.CreatedAt } },
                @{ Expression = { $_.Artifact.Name } })
            foreach ($d in $ordered) {
                if ($retainedTotal -le $MaxTotalSizeBytes) { break }
                $d.Reasons.Add($script:ReasonMaxTotalSize)
                $retainedTotal -= [long]$d.Artifact.SizeBytes
            }
        }
    }

    $appliedPolicies = [ordered]@{}
    if ($PSBoundParameters.ContainsKey('MaxAgeDays'))        { $appliedPolicies['MaxAgeDays'] = $MaxAgeDays }
    if ($PSBoundParameters.ContainsKey('KeepLatestN'))       { $appliedPolicies['KeepLatestN'] = $KeepLatestN }
    if ($PSBoundParameters.ContainsKey('MaxTotalSizeBytes')) { $appliedPolicies['MaxTotalSizeBytes'] = $MaxTotalSizeBytes }

    return (ConvertTo-CleanupPlan -Decision $decisions -AppliedPolicies $appliedPolicies -ReferenceDate $Now)
}

function Invoke-ArtifactCleanup {
    <#
    .SYNOPSIS
        Compute a cleanup plan and (optionally) execute the deletions.

    .DESCRIPTION
        Thin orchestration layer over Get-CleanupPlan. It computes the plan and,
        when NOT in -DryRun and a -DeleteAction script block is supplied, calls
        that action once per artifact slated for deletion (passing the full
        deletion record). The engine itself stays pure: the caller decides what
        "delete" actually means (call the GitHub API, remove a file, etc.), which
        keeps the dangerous side effect out of the testable core.

        -DryRun is the safety valve: it returns the identical plan but performs
        no deletions. The returned plan carries a DryRun flag for reporting.

    .OUTPUTS
        The Get-CleanupPlan plan object, plus a DryRun [bool] property.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Artifact,
        [int]       $MaxAgeDays,
        [long]      $MaxTotalSizeBytes,
        [int]       $KeepLatestN,
        [datetime]  $Now = (Get-Date),

        # When set, compute the plan but perform no deletions.
        [switch]    $DryRun,

        # Invoked once per to-be-deleted artifact when not in dry-run. Receives
        # the deletion record (Name, SizeBytes, CreatedAt, WorkflowRunId, Reasons).
        [scriptblock] $DeleteAction
    )

    # Forward only the policy parameters the caller actually supplied so that
    # unspecified policies stay inactive (Get-CleanupPlan keys off bound params).
    $forward = @{ Artifact = $Artifact; Now = $Now }
    foreach ($key in 'MaxAgeDays', 'MaxTotalSizeBytes', 'KeepLatestN') {
        if ($PSBoundParameters.ContainsKey($key)) { $forward[$key] = $PSBoundParameters[$key] }
    }

    $plan = Get-CleanupPlan @forward

    if (-not $DryRun -and $DeleteAction) {
        foreach ($record in $plan.Delete) {
            try {
                & $DeleteAction $record
            }
            catch {
                throw "Failed to delete artifact '$($record.Name)': $($_.Exception.Message)"
            }
        }
    }

    # Surface the mode on the plan so reports can label DRY-RUN vs LIVE.
    $plan | Add-Member -NotePropertyName DryRun -NotePropertyValue ([bool]$DryRun) -Force
    return $plan
}

function Assert-ArtifactShape {
    <#
    .SYNOPSIS
        Validate that an artifact has the required, correctly-typed properties.
        Throws a meaningful error naming the offending artifact and property.
    #>
    param([Parameter(Mandatory)] $Artifact)

    foreach ($prop in 'Name', 'SizeBytes', 'CreatedAt', 'WorkflowRunId') {
        if ($null -eq $Artifact.PSObject.Properties[$prop]) {
            throw "Artifact is missing required property '$prop': $($Artifact | ConvertTo-Json -Compress -Depth 3)"
        }
    }
    if ($Artifact.CreatedAt -isnot [datetime]) {
        throw "Artifact '$($Artifact.Name)' has a non-datetime CreatedAt ('$($Artifact.CreatedAt)')."
    }
    if ($Artifact.SizeBytes -lt 0) {
        throw "Artifact '$($Artifact.Name)' has a negative SizeBytes ($($Artifact.SizeBytes))."
    }
}

function ConvertTo-CleanupPlan {
    <#
    .SYNOPSIS
        Fold a list of decisions into the final plan + summary object.
    #>
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Decision,
        [Parameter(Mandatory)] [System.Collections.IDictionary] $AppliedPolicies,
        [Parameter(Mandatory)] [datetime] $ReferenceDate
    )

    $toDelete = @($Decision | Where-Object { $_.Reasons.Count -gt 0 })
    $toRetain = @($Decision | Where-Object { $_.Reasons.Count -eq 0 })

    # Project deletions into self-contained records (artifact fields + reasons)
    # so the plan is serialisable without dragging the source object along.
    $deleteRecords = foreach ($d in $toDelete) {
        [pscustomobject]@{
            Name          = $d.Artifact.Name
            SizeBytes     = [long]$d.Artifact.SizeBytes
            CreatedAt     = $d.Artifact.CreatedAt
            WorkflowRunId = $d.Artifact.WorkflowRunId
            Reasons       = @($d.Reasons)
        }
    }
    $retainRecords = foreach ($d in $toRetain) {
        [pscustomobject]@{
            Name          = $d.Artifact.Name
            SizeBytes     = [long]$d.Artifact.SizeBytes
            CreatedAt     = $d.Artifact.CreatedAt
            WorkflowRunId = $d.Artifact.WorkflowRunId
        }
    }
    $deleteRecords = @($deleteRecords)
    $retainRecords = @($retainRecords)

    # Sum explicitly rather than via Measure-Object: under Set-StrictMode an
    # empty pipeline makes Measure-Object yield nothing, and `.Sum` on $null
    # throws. A manual fold is correct for 0, 1 and N elements alike.
    $reclaimed = [long]0
    foreach ($r in $deleteRecords) { $reclaimed += [long]$r.SizeBytes }
    $retained = [long]0
    foreach ($r in $retainRecords) { $retained += [long]$r.SizeBytes }

    $summary = [pscustomobject]@{
        TotalArtifacts      = $Decision.Count
        DeletedCount        = $deleteRecords.Count
        RetainedCount       = $retainRecords.Count
        SpaceReclaimedBytes = [long]$reclaimed
        RetainedSizeBytes   = [long]$retained
        TotalSizeBytes      = [long]($reclaimed + $retained)
    }

    [pscustomobject]@{
        Delete          = $deleteRecords
        Retain          = $retainRecords
        Summary         = $summary
        AppliedPolicies = $AppliedPolicies
        ReferenceDate   = $ReferenceDate
    }
}

function ConvertTo-NormalizedArtifact {
    <#
    .SYNOPSIS
        Coerce a raw (e.g. JSON-deserialised) object into the canonical artifact
        shape with correctly typed fields.

    .DESCRIPTION
        Accepts a handful of common field spellings (name/Name, sizeBytes/size,
        createdAt/creationDate, workflowRunId/runId) so fixtures can use natural
        JSON casing. All timestamps are normalised to UTC so age comparisons are
        timezone-independent and deterministic. Throws if a required field is
        missing or a timestamp can't be parsed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)] $InputObject
    )
    process {
        $name = Get-FirstProperty -Object $InputObject -Names 'name', 'Name'
        $size = Get-FirstProperty -Object $InputObject -Names 'sizeBytes', 'SizeBytes', 'size'
        $date = Get-FirstProperty -Object $InputObject -Names 'createdAt', 'CreatedAt', 'creationDate'
        $run  = Get-FirstProperty -Object $InputObject -Names 'workflowRunId', 'WorkflowRunId', 'runId'

        if ($null -eq $name) { throw "Artifact is missing required field 'name'." }
        if ($null -eq $size) { throw "Artifact '$name' is missing required field 'sizeBytes'." }
        if ($null -eq $date) { throw "Artifact '$name' is missing required field 'createdAt'." }
        if ($null -eq $run)  { throw "Artifact '$name' is missing required field 'workflowRunId'." }

        [pscustomobject]@{
            Name          = [string]$name
            SizeBytes     = [long]$size
            CreatedAt     = (ConvertTo-UtcDateTime -Value $date -Context "artifact '$name' createdAt")
            WorkflowRunId = [string]$run
        }
    }
}

function Get-FirstProperty {
    # Return the value of the first property name that exists (and is non-null)
    # on the object, or $null if none are present. Lets us accept field aliases.
    param(
        [Parameter(Mandatory)] $Object,
        [Parameter(Mandatory)] [string[]] $Names
    )
    foreach ($n in $Names) {
        $prop = $Object.PSObject.Properties[$n]
        if ($null -ne $prop -and $null -ne $prop.Value) { return $prop.Value }
    }
    return $null
}

function ConvertTo-UtcDateTime {
    # Parse a value (already a [datetime], or an ISO-8601 string) into a UTC
    # [datetime]. ConvertFrom-Json may hand us a Local-kind datetime; converting
    # to universal time preserves the instant while making the kind explicit.
    param(
        [Parameter(Mandatory)] $Value,
        [string] $Context = 'value'
    )
    if ($Value -is [datetime]) {
        return ([datetime]$Value).ToUniversalTime()
    }
    try {
        $parsed = [datetime]::Parse(
            [string]$Value,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor
            [System.Globalization.DateTimeStyles]::AssumeUniversal)
        return $parsed
    }
    catch {
        throw "Could not parse $Context as a date/time: '$Value'."
    }
}

function Import-CleanupConfig {
    <#
    .SYNOPSIS
        Load a self-contained cleanup fixture/config from a JSON file.

    .DESCRIPTION
        The file bundles everything one run needs: optional referenceDate, the
        policy thresholds, a dryRun flag (defaulting to $true for safety) and the
        artifact list. Returns a config object whose Policies hashtable contains
        only the policies actually present, ready to splat into Get-CleanupPlan.

        Fails with clear, actionable messages on a missing file, malformed JSON,
        or a missing artifacts array.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Cleanup config file not found: '$Path'."
    }

    $rawText = Get-Content -LiteralPath $Path -Raw
    try {
        $doc = $rawText | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Failed to parse JSON in '$Path': $($_.Exception.Message)"
    }

    if ($null -eq $doc.PSObject.Properties['artifacts']) {
        throw "Cleanup config '$Path' has no 'artifacts' array."
    }

    # Collect only the policies that are present and non-null.
    $policies = [ordered]@{}
    $policyDoc = $doc.PSObject.Properties['policies']?.Value
    if ($null -ne $policyDoc) {
        $map = @{ maxAgeDays = 'MaxAgeDays'; keepLatestN = 'KeepLatestN'; maxTotalSizeBytes = 'MaxTotalSizeBytes' }
        foreach ($jsonKey in $map.Keys) {
            $prop = $policyDoc.PSObject.Properties[$jsonKey]
            if ($null -ne $prop -and $null -ne $prop.Value) {
                $policies[$map[$jsonKey]] = $prop.Value
            }
        }
    }

    # dryRun defaults to $true: a cleanup tool should never delete unless asked.
    $dryRun = $true
    $dryProp = $doc.PSObject.Properties['dryRun']
    if ($null -ne $dryProp -and $null -ne $dryProp.Value) { $dryRun = [bool]$dryProp.Value }

    $referenceDate = $null
    $refProp = $doc.PSObject.Properties['referenceDate']
    if ($null -ne $refProp -and $null -ne $refProp.Value) {
        $referenceDate = ConvertTo-UtcDateTime -Value $refProp.Value -Context 'referenceDate'
    }

    $artifacts = @(@($doc.artifacts) | ConvertTo-NormalizedArtifact)

    [pscustomobject]@{
        ReferenceDate = $referenceDate
        DryRun        = $dryRun
        Policies      = $policies
        Artifacts     = $artifacts
    }
}

function Format-CleanupReport {
    <#
    .SYNOPSIS
        Render a deletion plan as a deterministic, greppable text report.

    .DESCRIPTION
        Produces a stable block: a mode banner, the applied policies, one line per
        deletion (with reasons) and per retention, and a key/value SUMMARY section.
        Rows are sorted by Name and timestamps are emitted as ISO-8601 UTC so the
        output is byte-stable for exact-match assertions in CI.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Plan)

    $mode = if ($Plan.PSObject.Properties['DryRun'] -and $Plan.DryRun) { 'DRY-RUN' } else { 'LIVE' }
    $iso  = { param($d) ([datetime]$d).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }

    # Canonical reason ordering so multi-reason rows are byte-stable.
    $rank = @{ $script:ReasonMaxAge = 0; $script:ReasonKeepLatestN = 1; $script:ReasonMaxTotalSize = 2 }
    $orderReasons = { param($reasons) ($reasons | Sort-Object { $rank[$_] }) -join '|' }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('===== ARTIFACT CLEANUP PLAN =====')
    $lines.Add("Mode: $mode")
    $lines.Add("ReferenceDate: $(& $iso $Plan.ReferenceDate)")

    $policyParts = foreach ($k in $Plan.AppliedPolicies.Keys) { "$k=$($Plan.AppliedPolicies[$k])" }
    $policyText = if ($policyParts) { $policyParts -join ', ' } else { '(none)' }
    $lines.Add("Policies: $policyText")

    $lines.Add("----- DELETE ($($Plan.Summary.DeletedCount)) -----")
    foreach ($d in ($Plan.Delete | Sort-Object Name)) {
        $lines.Add("DELETE name=$($d.Name) sizeBytes=$($d.SizeBytes) createdAt=$(& $iso $d.CreatedAt) workflowRunId=$($d.WorkflowRunId) reasons=$(& $orderReasons $d.Reasons)")
    }

    $lines.Add("----- RETAIN ($($Plan.Summary.RetainedCount)) -----")
    foreach ($r in ($Plan.Retain | Sort-Object Name)) {
        $lines.Add("RETAIN name=$($r.Name) sizeBytes=$($r.SizeBytes) createdAt=$(& $iso $r.CreatedAt) workflowRunId=$($r.WorkflowRunId)")
    }

    $lines.Add('----- SUMMARY -----')
    $lines.Add("TotalArtifacts: $($Plan.Summary.TotalArtifacts)")
    $lines.Add("DeletedCount: $($Plan.Summary.DeletedCount)")
    $lines.Add("RetainedCount: $($Plan.Summary.RetainedCount)")
    $lines.Add("SpaceReclaimedBytes: $($Plan.Summary.SpaceReclaimedBytes)")
    $lines.Add("RetainedSizeBytes: $($Plan.Summary.RetainedSizeBytes)")
    $lines.Add("TotalSizeBytes: $($Plan.Summary.TotalSizeBytes)")
    $lines.Add('===== END CLEANUP PLAN =====')

    return ($lines -join [Environment]::NewLine)
}

Export-ModuleMember -Function Get-CleanupPlan, Invoke-ArtifactCleanup,
    ConvertTo-NormalizedArtifact, Import-CleanupConfig, Format-CleanupReport
