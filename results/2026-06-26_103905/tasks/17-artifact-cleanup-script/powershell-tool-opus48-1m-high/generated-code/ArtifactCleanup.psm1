#region ArtifactCleanup.psm1
<#
.SYNOPSIS
    Artifact retention / cleanup engine.

.DESCRIPTION
    Given a list of artifacts (each with a Name, Size in bytes, CreatedAt
    timestamp and WorkflowRunId), this module decides which artifacts to delete
    according to three independent, all-optional retention policies:

      * MaxAgeDays            - delete anything older than N days.
      * KeepLatestPerWorkflow - within each workflow run group, keep only the N
                                most-recently created artifacts.
      * MaxTotalSize          - cap the total retained size; once the survivors
                                of the above rules still exceed the cap, delete
                                oldest-first until the total fits.

    The engine is *pure*: it produces a deletion plan (a decision per artifact
    plus a summary) and never performs side effects. Actual deletion is the job
    of Invoke-ArtifactCleanup, which honours a -DryRun switch.

    Grouping note: the only workflow-identifying field in the supplied metadata
    is WorkflowRunId, so "per workflow" is implemented as "per WorkflowRunId".
#>

Set-StrictMode -Version Latest

# Reason codes attached to a delete decision. Multiple may apply to one artifact.
$script:ReasonMaxAge      = 'max-age'
$script:ReasonKeepLatest  = 'keep-latest'
$script:ReasonMaxTotal    = 'max-total-size'

function Get-SizeSum {
    # Sum the Size field over a collection, returning 0 for an empty/null set.
    # Avoids the StrictMode pitfall where Measure-Object over an empty pipeline
    # produces no object and accessing .Sum then throws.
    param([object[]] $Items)
    [long]$total = 0
    foreach ($i in $Items) { $total += [long]$i.Size }
    $total
}

function ConvertTo-ArtifactObject {
    <#
    .SYNOPSIS
        Normalises a raw artifact (hashtable / PSCustomObject / parsed JSON)
        into a validated object with strongly-typed fields.
    .DESCRIPTION
        Accepts loosely shaped input and returns a PSCustomObject with:
        Name [string], Size [long], CreatedAt [datetime], WorkflowRunId [string].
        Throws a meaningful error when a required field is missing or a value
        cannot be coerced to the expected type.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object] $InputObject
    )
    process {
        # Resolve a property/key value across hashtable and object inputs.
        $get = {
            param($obj, $name)
            if ($obj -is [System.Collections.IDictionary]) {
                if ($obj.Contains($name)) { return $obj[$name] }
                return $null
            }
            $prop = $obj.PSObject.Properties[$name]
            if ($prop) { return $prop.Value }
            return $null
        }

        $name = & $get $InputObject 'Name'
        if ([string]::IsNullOrWhiteSpace([string]$name)) {
            throw "Artifact is missing a required 'Name' field."
        }

        $rawSize = & $get $InputObject 'Size'
        if ($null -eq $rawSize) {
            throw "Artifact '$name' is missing a required 'Size' field."
        }
        [long]$size = 0
        if (-not [long]::TryParse([string]$rawSize, [ref]$size)) {
            throw "Artifact '$name' has a non-numeric Size value: '$rawSize'."
        }
        if ($size -lt 0) {
            throw "Artifact '$name' has a negative Size value: $size."
        }

        $rawDate = & $get $InputObject 'CreatedAt'
        if ($null -eq $rawDate) {
            throw "Artifact '$name' is missing a required 'CreatedAt' field."
        }
        $createdAt = $null
        if ($rawDate -is [datetime]) {
            $createdAt = $rawDate
        }
        else {
            # Parse ISO-8601 style strings as universal time for determinism.
            $parsed = [datetime]::MinValue
            $styles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor `
                      [System.Globalization.DateTimeStyles]::AdjustToUniversal
            if (-not [datetime]::TryParse([string]$rawDate,
                    [System.Globalization.CultureInfo]::InvariantCulture,
                    $styles, [ref]$parsed)) {
                throw "Artifact '$name' has an unparseable CreatedAt value: '$rawDate'."
            }
            $createdAt = $parsed
        }

        $runId = & $get $InputObject 'WorkflowRunId'
        if ([string]::IsNullOrWhiteSpace([string]$runId)) {
            throw "Artifact '$name' is missing a required 'WorkflowRunId' field."
        }

        [PSCustomObject]@{
            Name          = [string]$name
            Size          = $size
            CreatedAt     = $createdAt
            WorkflowRunId = [string]$runId
        }
    }
}

function Get-ArtifactDeletionPlan {
    <#
    .SYNOPSIS
        Builds a deletion plan for a set of artifacts from retention policies.
    .PARAMETER Artifacts
        The artifacts to evaluate. Each must expose Name, Size, CreatedAt and
        WorkflowRunId (hashtable, PSCustomObject or parsed JSON are all fine).
    .PARAMETER MaxAgeDays
        Delete artifacts older than this many days. 0 (default) disables the rule.
    .PARAMETER KeepLatestPerWorkflow
        Keep only the N newest artifacts per WorkflowRunId. 0 (default) disables.
    .PARAMETER MaxTotalSize
        Maximum total retained size in bytes. 0 (default) disables the cap.
    .PARAMETER ReferenceDate
        "Now" used for age calculations. Defaults to the current UTC time;
        supply it explicitly for deterministic tests.
    .PARAMETER DryRun
        Recorded on the plan summary. Does not change the decisions (the plan is
        identical), only the DryRun flag downstream consumers inspect.
    .OUTPUTS
        PSCustomObject with .Decisions (one per artifact) and .Summary.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Artifacts,

        [ValidateScript({ $_ -ge 0 -or (throw "MaxAgeDays must be >= 0.") })]
        [int] $MaxAgeDays = 0,

        [ValidateScript({ $_ -ge 0 -or (throw "KeepLatestPerWorkflow must be >= 0.") })]
        [int] $KeepLatestPerWorkflow = 0,

        [ValidateScript({ $_ -ge 0 -or (throw "MaxTotalSize must be >= 0.") })]
        [long] $MaxTotalSize = 0,

        [datetime] $ReferenceDate = [datetime]::UtcNow,

        [switch] $DryRun
    )

    # --- Normalise & validate input -------------------------------------------
    $items = @()
    foreach ($a in $Artifacts) {
        $items += (ConvertTo-ArtifactObject -InputObject $a)
    }

    # Build a mutable decision record per artifact. Reasons accumulate.
    $decisions = foreach ($it in $items) {
        [PSCustomObject]@{
            Name          = $it.Name
            Size          = $it.Size
            CreatedAt     = $it.CreatedAt
            WorkflowRunId = $it.WorkflowRunId
            Action        = 'Retain'
            Reasons       = [System.Collections.Generic.List[string]]::new()
        }
    }
    # Ensure an array even for 0/1 elements so .Count etc. behave.
    $decisions = @($decisions)

    # --- Policy 1: max age -----------------------------------------------------
    if ($MaxAgeDays -gt 0) {
        $cutoff = $ReferenceDate.AddDays(-$MaxAgeDays)
        foreach ($d in $decisions) {
            if ($d.CreatedAt -lt $cutoff) {
                $d.Reasons.Add($script:ReasonMaxAge)
            }
        }
    }

    # --- Policy 2: keep-latest-N per workflow run ------------------------------
    if ($KeepLatestPerWorkflow -gt 0) {
        $groups = $decisions | Group-Object -Property WorkflowRunId
        foreach ($g in $groups) {
            # Newest first; tie-break on Name for deterministic ordering.
            $ordered = $g.Group | Sort-Object -Property `
                @{ Expression = 'CreatedAt'; Descending = $true }, `
                @{ Expression = 'Name'; Descending = $false }
            $rank = 0
            foreach ($d in $ordered) {
                $rank++
                if ($rank -gt $KeepLatestPerWorkflow) {
                    $d.Reasons.Add($script:ReasonKeepLatest)
                }
            }
        }
    }

    # --- Policy 3: max total retained size -------------------------------------
    # Applied only to artifacts that survived the rules above; remove oldest
    # first until the retained total fits under the cap.
    if ($MaxTotalSize -gt 0) {
        $survivors = @($decisions | Where-Object { $_.Reasons.Count -eq 0 })
        [long]$retainedSize = Get-SizeSum -Items $survivors

        if ($retainedSize -gt $MaxTotalSize) {
            # Oldest first; tie-break on Name so the choice is deterministic.
            $byAge = $survivors | Sort-Object -Property `
                @{ Expression = 'CreatedAt'; Descending = $false }, `
                @{ Expression = 'Name'; Descending = $false }
            foreach ($d in $byAge) {
                if ($retainedSize -le $MaxTotalSize) { break }
                $d.Reasons.Add($script:ReasonMaxTotal)
                $retainedSize -= $d.Size
            }
        }
    }

    # --- Finalise actions ------------------------------------------------------
    foreach ($d in $decisions) {
        $d.Action = if ($d.Reasons.Count -gt 0) { 'Delete' } else { 'Retain' }
        # Freeze reasons to a plain array for cleaner downstream/JSON output.
        $d.Reasons = [string[]]$d.Reasons
    }

    $deleted  = @($decisions | Where-Object { $_.Action -eq 'Delete' })
    $retained = @($decisions | Where-Object { $_.Action -eq 'Retain' })

    [long]$totalBefore   = Get-SizeSum -Items $decisions
    [long]$reclaimed     = Get-SizeSum -Items $deleted
    [long]$retainedBytes = Get-SizeSum -Items $retained

    $summary = [PSCustomObject]@{
        TotalArtifacts  = $decisions.Count
        RetainedCount   = $retained.Count
        DeletedCount    = $deleted.Count
        TotalSizeBefore = $totalBefore
        RetainedSize    = $retainedBytes
        SpaceReclaimed  = $reclaimed
        DryRun          = [bool]$DryRun
    }

    [PSCustomObject]@{
        Decisions = $decisions
        Summary   = $summary
    }
}

function Invoke-ArtifactCleanup {
    <#
    .SYNOPSIS
        Builds a deletion plan and (unless -DryRun) performs the deletions.
    .DESCRIPTION
        Side-effecting wrapper around Get-ArtifactDeletionPlan. The actual
        deletion is delegated to the -DeleteAction scriptblock (the artifact
        decision object is passed as $args[0]); this keeps the module free of a
        hard dependency on any specific storage/API. In -DryRun mode no action
        runs and the plan's summary records DryRun = $true.
    .OUTPUTS
        The same plan object Get-ArtifactDeletionPlan returns.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Artifacts,

        [int]  $MaxAgeDays = 0,
        [int]  $KeepLatestPerWorkflow = 0,
        [long] $MaxTotalSize = 0,
        [datetime] $ReferenceDate = [datetime]::UtcNow,
        [switch] $DryRun,

        # Invoked once per artifact that is to be deleted (skipped in DryRun).
        [scriptblock] $DeleteAction
    )

    $plan = Get-ArtifactDeletionPlan -Artifacts $Artifacts `
        -MaxAgeDays $MaxAgeDays `
        -KeepLatestPerWorkflow $KeepLatestPerWorkflow `
        -MaxTotalSize $MaxTotalSize `
        -ReferenceDate $ReferenceDate `
        -DryRun:$DryRun

    if (-not $DryRun) {
        foreach ($d in ($plan.Decisions | Where-Object { $_.Action -eq 'Delete' })) {
            if ($DeleteAction) {
                try {
                    & $DeleteAction $d
                }
                catch {
                    throw "Failed to delete artifact '$($d.Name)': $($_.Exception.Message)"
                }
            }
        }
    }

    $plan
}

function Format-DeletionPlanSummary {
    <#
    .SYNOPSIS
        Renders a deletion plan as human-readable text plus machine-parseable
        RESULT_* lines (used by the CI workflow for exact-value assertions).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object] $Plan
    )
    process {
        $s = $Plan.Summary
        $lines = [System.Collections.Generic.List[string]]::new()

        $mode = if ($s.DryRun) { 'DRY-RUN (no artifacts were deleted)' } else { 'LIVE' }
        $lines.Add('=== Artifact Cleanup Plan ===')
        $lines.Add("Mode: $mode")
        $lines.Add('')
        $lines.Add('Per-artifact decisions:')
        foreach ($d in $Plan.Decisions) {
            $reasons = if ($d.Reasons -and $d.Reasons.Count -gt 0) {
                ' [' + ($d.Reasons -join ', ') + ']'
            } else { '' }
            $lines.Add(("  {0,-7} {1,-22} {2,10} bytes  run={3}{4}" -f `
                $d.Action, $d.Name, $d.Size, $d.WorkflowRunId, $reasons))
        }
        $lines.Add('')
        $lines.Add('Summary:')
        $lines.Add("  Total artifacts : $($s.TotalArtifacts)")
        $lines.Add("  Retained        : $($s.RetainedCount) ($($s.RetainedSize) bytes)")
        $lines.Add("  Deleted         : $($s.DeletedCount)")
        $lines.Add("  Space reclaimed : $($s.SpaceReclaimed) bytes")
        $lines.Add('')
        # Machine-parseable contract — stable keys the CI harness asserts on.
        $lines.Add("RESULT_TOTAL=$($s.TotalArtifacts)")
        $lines.Add("RESULT_RETAINED=$($s.RetainedCount)")
        $lines.Add("RESULT_DELETED=$($s.DeletedCount)")
        $lines.Add("RESULT_RECLAIMED=$($s.SpaceReclaimed)")
        $lines.Add("RESULT_RETAINED_SIZE=$($s.RetainedSize)")
        $lines.Add("RESULT_DRYRUN=$($s.DryRun.ToString().ToLowerInvariant())")

        $lines -join [Environment]::NewLine
    }
}

function Import-ArtifactFixture {
    <#
    .SYNOPSIS
        Loads an array of artifacts from a JSON file and validates each one.
    .DESCRIPTION
        Reads the file, parses JSON (an array of objects), and returns
        normalised artifact objects. Throws meaningful errors for a missing
        file or malformed JSON.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Artifact fixture file not found: '$Path'."
    }

    try {
        $raw = Get-Content -LiteralPath $Path -Raw
        $data = $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Failed to parse JSON from '$Path': $($_.Exception.Message)"
    }

    # Accept either a bare array or an object with an 'artifacts' property.
    if ($data -is [System.Management.Automation.PSCustomObject] -and
        $data.PSObject.Properties['artifacts']) {
        $data = $data.artifacts
    }

    @($data | ConvertTo-ArtifactObject)
}

Export-ModuleMember -Function `
    Get-ArtifactDeletionPlan, `
    Invoke-ArtifactCleanup, `
    Format-DeletionPlanSummary, `
    Import-ArtifactFixture, `
    ConvertTo-ArtifactObject
#endregion
