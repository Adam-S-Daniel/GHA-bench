<#
.SYNOPSIS
    Artifact retention / cleanup engine.

.DESCRIPTION
    Given a collection of artifacts (each with Name, SizeBytes, CreatedAt and
    WorkflowRunId), this module decides which artifacts to keep and which to
    delete according to three independent, optional retention policies and then
    produces a structured deletion plan with a summary.

    --------------------------------------------------------------------------
    POLICY MODEL (and precedence)
    --------------------------------------------------------------------------
    The policies are applied in a fixed, well-defined order so that results are
    deterministic and easy to reason about:

      1. keep-latest-N per workflow  (a TRIM rule with a protection floor)
         For each workflow (grouped by WorkflowRunId) the N most-recent
         artifacts are marked "Protected" (a retention floor: they are *never*
         deleted by any policy, even if old or over budget). Every artifact
         *beyond* the newest N in a group is deleted with reason 'KeepLatestN'.
         Running this policy alone therefore trims each workflow down to its N
         freshest artifacts.

      2. max-age  (a deletion rule)
         Any *non-protected* artifact older than (Now - MaxAgeDays) is marked
         for deletion with reason 'MaxAge'.

      3. max-total-size  (a deletion rule)
         If, after the steps above, the total size of the still-retained
         artifacts exceeds MaxTotalSizeBytes, *non-protected* retained
         artifacts are deleted oldest-first (reason 'MaxTotalSize') until the
         retained total fits within the budget. Protected artifacts are never
         removed, so the result may legitimately stay above budget — this is
         surfaced via the summary's OverBudget flag.

    Each policy is optional: a value of 0 / $null disables that policy.

    Sorting is fully deterministic (CreatedAt, then Name as a tie-breaker) so
    identical inputs always yield identical plans.
#>

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# Internal helper: normalise + validate a single raw artifact into a clean
# working object. Accepts either real DateTime values or ISO-8601 strings for
# CreatedAt (JSON fixtures arrive as strings). Throws a meaningful error that
# names the offending artifact when a field is missing or invalid.
# ---------------------------------------------------------------------------
function ConvertTo-NormalizedArtifact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Artifact,
        [Parameter(Mandatory)] [int] $Index
    )

    # Build a label used in error messages so problems are easy to trace.
    $label = "artifact #$Index"
    if ($Artifact -and ($Artifact.PSObject.Properties.Name -contains 'Name') -and $Artifact.Name) {
        $label = "artifact '$($Artifact.Name)' (#$Index)"
    }

    foreach ($required in 'Name', 'SizeBytes', 'CreatedAt', 'WorkflowRunId') {
        if (-not ($Artifact.PSObject.Properties.Name -contains $required)) {
            throw "Invalid input: $label is missing required field '$required'."
        }
    }

    if ([string]::IsNullOrWhiteSpace([string]$Artifact.Name)) {
        throw "Invalid input: $label has an empty 'Name'."
    }

    # Size must be a non-negative whole number of bytes.
    [long] $size = 0
    if (-not [long]::TryParse([string]$Artifact.SizeBytes, [ref] $size)) {
        throw "Invalid input: $label has a non-numeric 'SizeBytes' value '$($Artifact.SizeBytes)'."
    }
    if ($size -lt 0) {
        throw "Invalid input: $label has a negative 'SizeBytes' value '$size'."
    }

    # CreatedAt may already be a DateTime, or an ISO-8601 string from JSON.
    [datetime] $created = [datetime]::MinValue
    if ($Artifact.CreatedAt -is [datetime]) {
        $created = $Artifact.CreatedAt
    }
    else {
        $parsed = [datetime]::MinValue
        $styles = [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor `
                  [System.Globalization.DateTimeStyles]::AssumeUniversal
        if (-not [datetime]::TryParse(
                [string]$Artifact.CreatedAt,
                [System.Globalization.CultureInfo]::InvariantCulture,
                $styles,
                [ref] $parsed)) {
            throw "Invalid input: $label has an unparseable 'CreatedAt' value '$($Artifact.CreatedAt)'."
        }
        $created = $parsed
    }
    # Normalise to UTC so comparisons against a UTC "Now" are correct.
    $created = $created.ToUniversalTime()

    [pscustomobject]@{
        Name          = [string]$Artifact.Name
        SizeBytes     = $size
        CreatedAt     = $created
        WorkflowRunId = [string]$Artifact.WorkflowRunId
        # Decision state, mutated as policies are applied.
        Decision      = 'Retain'   # 'Retain' | 'Delete'
        Reason        = $null      # why it was deleted (null while retained)
        Protected     = $false     # set by keep-latest-N; immune to deletion
    }
}

# ---------------------------------------------------------------------------
# Internal helper: sum the SizeBytes of a (possibly empty / single-item)
# collection. We avoid `Measure-Object -Sum` here because, under
# Set-StrictMode, accessing `.Sum` on its result is fragile for empty input.
# ---------------------------------------------------------------------------
function Get-TotalSizeBytes {
    param([object[]] $Items)
    [long] $sum = 0
    foreach ($item in $Items) { $sum += [long]$item.SizeBytes }
    return $sum
}

function Get-ArtifactCleanupPlan {
    <#
    .SYNOPSIS
        Compute (but do not execute) an artifact deletion plan.

    .DESCRIPTION
        Pure function: takes artifacts + policy parameters and returns a plan
        object describing what would be deleted and what would be retained,
        plus a summary. Has no side effects.

    .PARAMETER Artifacts
        The artifacts to evaluate. Each item must expose Name, SizeBytes,
        CreatedAt and WorkflowRunId. May be empty.

    .PARAMETER MaxAgeDays
        Delete non-protected artifacts older than this many days. 0 = disabled.

    .PARAMETER MaxTotalSizeBytes
        Cap the total retained size to this many bytes. 0 = disabled.

    .PARAMETER KeepLatestN
        Protect the N newest artifacts per workflow (WorkflowRunId). 0 = disabled.

    .PARAMETER Now
        The reference "current time" used for age calculations. Defaults to
        the current UTC time; inject a fixed value for deterministic tests.

    .OUTPUTS
        A PSCustomObject with Deleted, Retained and Summary members.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Artifacts,

        [ValidateRange(0, [int]::MaxValue)]
        [int] $MaxAgeDays = 0,

        [ValidateRange(0, [long]::MaxValue)]
        [long] $MaxTotalSizeBytes = 0,

        [ValidateRange(0, [int]::MaxValue)]
        [int] $KeepLatestN = 0,

        [datetime] $Now = [datetime]::UtcNow
    )

    # Always compare in UTC.
    $nowUtc = $Now.ToUniversalTime()

    # 1) Normalise + validate every artifact up front (fail fast on bad data).
    $items = @()
    for ($i = 0; $i -lt $Artifacts.Count; $i++) {
        $items += ConvertTo-NormalizedArtifact -Artifact $Artifacts[$i] -Index $i
    }

    # --- Policy 1: keep-latest-N per workflow (trim + protection floor) -----
    if ($KeepLatestN -gt 0) {
        $groups = $items | Group-Object -Property WorkflowRunId
        foreach ($g in $groups) {
            # Newest first; Name as a deterministic tie-breaker.
            $ordered = @($g.Group | Sort-Object -Property @{Expression = 'CreatedAt'; Descending = $true},
                                                           @{Expression = 'Name'; Descending = $true})
            for ($k = 0; $k -lt $ordered.Count; $k++) {
                if ($k -lt $KeepLatestN) {
                    # Within the keep window: protect (immune to age/size too).
                    $ordered[$k].Protected = $true
                }
                else {
                    # Beyond the newest N: trim it.
                    $ordered[$k].Decision = 'Delete'
                    $ordered[$k].Reason   = 'KeepLatestN'
                }
            }
        }
    }

    # --- Policy 2: max-age --------------------------------------------------
    if ($MaxAgeDays -gt 0) {
        $cutoff = $nowUtc.AddDays(-$MaxAgeDays)
        foreach ($item in $items) {
            if (-not $item.Protected -and $item.Decision -eq 'Retain' -and $item.CreatedAt -lt $cutoff) {
                $item.Decision = 'Delete'
                $item.Reason   = 'MaxAge'
            }
        }
    }

    # --- Policy 3: max-total-size ------------------------------------------
    $overBudget = $false
    if ($MaxTotalSizeBytes -gt 0) {
        $retainedSize = Get-TotalSizeBytes -Items @($items | Where-Object { $_.Decision -eq 'Retain' })

        if ($retainedSize -gt $MaxTotalSizeBytes) {
            # Evict non-protected, still-retained artifacts oldest-first.
            $candidates = $items |
                Where-Object { $_.Decision -eq 'Retain' -and -not $_.Protected } |
                Sort-Object -Property @{Expression = 'CreatedAt'; Descending = $false},
                                      @{Expression = 'Name'; Descending = $false}

            foreach ($item in $candidates) {
                if ($retainedSize -le $MaxTotalSizeBytes) { break }
                $item.Decision = 'Delete'
                $item.Reason   = 'MaxTotalSize'
                $retainedSize -= $item.SizeBytes
            }

            # If protected artifacts alone exceed the budget we cannot get
            # under it without violating the keep-latest-N guarantee.
            if ($retainedSize -gt $MaxTotalSizeBytes) {
                $overBudget = $true
            }
        }
    }

    # --- Build the plan ----------------------------------------------------
    $deleted  = @($items | Where-Object { $_.Decision -eq 'Delete' } |
        Sort-Object -Property @{Expression = 'CreatedAt'; Descending = $false}, 'Name')
    $retained = @($items | Where-Object { $_.Decision -eq 'Retain' } |
        Sort-Object -Property @{Expression = 'CreatedAt'; Descending = $false}, 'Name')

    $totalSize    = Get-TotalSizeBytes -Items $items
    $deletedSize  = Get-TotalSizeBytes -Items $deleted
    $retainedSize = Get-TotalSizeBytes -Items $retained

    # Record which policies were actually in effect (handy for the report).
    $applied = @()
    if ($KeepLatestN -gt 0)       { $applied += "KeepLatestN=$KeepLatestN" }
    if ($MaxAgeDays -gt 0)        { $applied += "MaxAgeDays=$MaxAgeDays" }
    if ($MaxTotalSizeBytes -gt 0) { $applied += "MaxTotalSizeBytes=$MaxTotalSizeBytes" }

    $summary = [pscustomobject]@{
        TotalArtifacts      = $items.Count
        RetainedCount       = $retained.Count
        DeletedCount        = $deleted.Count
        TotalSizeBytes      = [long]$totalSize
        RetainedSizeBytes   = [long]$retainedSize
        DeletedSizeBytes    = [long]$deletedSize
        SpaceReclaimedBytes = [long]$deletedSize   # space freed == sum of deleted sizes
        PoliciesApplied     = $applied
        OverBudget          = $overBudget
    }

    [pscustomobject]@{
        Deleted  = $deleted
        Retained = $retained
        Summary  = $summary
    }
}

function Invoke-ArtifactCleanup {
    <#
    .SYNOPSIS
        Compute a deletion plan and (optionally) execute the deletions.

    .DESCRIPTION
        Wraps Get-ArtifactCleanupPlan with execution semantics:
          * In dry-run mode (-DryRun) nothing is "deleted": the DeleteAction is
            never invoked. The plan is returned for inspection.
          * In live mode the DeleteAction script block is invoked once per
            artifact slated for deletion. The default action simply writes a
            message; a caller can supply a real deletion callback.

        The returned object is the plan from Get-ArtifactCleanupPlan augmented
        with DryRun and Executed flags.

    .PARAMETER DeleteAction
        Script block invoked (in live mode) with each artifact to delete.

    .PARAMETER DryRun
        When set, report the plan but perform no deletions.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Artifacts,

        [int]  $MaxAgeDays = 0,
        [long] $MaxTotalSizeBytes = 0,
        [int]  $KeepLatestN = 0,
        [datetime] $Now = [datetime]::UtcNow,

        [switch] $DryRun,

        [scriptblock] $DeleteAction = { param($a) Write-Verbose "Deleting artifact '$($a.Name)' ($($a.SizeBytes) bytes)" }
    )

    $plan = Get-ArtifactCleanupPlan -Artifacts $Artifacts `
        -MaxAgeDays $MaxAgeDays `
        -MaxTotalSizeBytes $MaxTotalSizeBytes `
        -KeepLatestN $KeepLatestN `
        -Now $Now

    $executed = $false
    if (-not $DryRun) {
        # Live mode: actually run the deletion callback for each artifact.
        foreach ($artifact in $plan.Deleted) {
            & $DeleteAction $artifact
        }
        $executed = $true
    }

    # Augment the plan with execution metadata without mutating the original.
    [pscustomobject]@{
        Deleted  = $plan.Deleted
        Retained = $plan.Retained
        Summary  = $plan.Summary
        DryRun   = [bool]$DryRun
        Executed = $executed
    }
}

Export-ModuleMember -Function Get-ArtifactCleanupPlan, Invoke-ArtifactCleanup
