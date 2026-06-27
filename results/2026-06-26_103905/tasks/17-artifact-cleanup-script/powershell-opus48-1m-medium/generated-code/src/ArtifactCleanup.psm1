<#
.SYNOPSIS
    Artifact retention / cleanup engine.

.DESCRIPTION
    Given a list of artifacts (name, size, creation date, workflow name + run id),
    this module applies a set of retention policies and produces a *deletion plan*:
    a per-artifact decision (Keep / Delete) with a reason, plus a summary
    (space reclaimed, retained vs deleted counts and sizes).

    Policies are applied in a deliberate order so the result is predictable:

        1. MaxAgeDays            - anything strictly older than the cutoff is deleted.
        2. KeepLatestPerWorkflow - within each workflow group keep only the N newest
                                   of those still surviving; older ones are deleted.
        3. MaxTotalSizeBytes     - if the survivors still exceed the size budget,
                                   delete oldest-first until the budget is met.

    The engine itself is pure (no side effects): it never deletes anything. The
    public Invoke-ArtifactCleanup wrapper optionally performs the real deletion via
    a caller-supplied -DeleteAction script block, and supports -DryRun.
#>

Set-StrictMode -Version Latest

# Reasons are surfaced in the plan and the human-readable summary.
$script:ReasonMaxAge     = 'exceeds max age'
$script:ReasonKeepLatest = 'beyond keep-latest-N for its workflow'
$script:ReasonMaxSize    = 'over max total size budget'

function Get-SizeSum {
    # Sum the SizeBytes of a collection, returning 0 for an empty/null set.
    # (Avoids StrictMode pitfalls with Measure-Object over empty pipelines.)
    param([object[]] $Items)
    $total = [long] 0
    foreach ($i in @($Items)) { $total += [long] $i.SizeBytes }
    return $total
}

function Import-ArtifactData {
    <#
    .SYNOPSIS
        Load artifact metadata from a JSON file and normalise it into objects the
        retention engine understands.

    .PARAMETER Path
        Path to a JSON file containing an array of artifact records. Each record
        uses the keys: name, sizeBytes, createdAt, workflowName, workflowRunId.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Artifact data file not found: '$Path'"
    }

    $raw = Get-Content -LiteralPath $Path -Raw

    try {
        $records = $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Failed to parse artifact JSON in '$Path': $($_.Exception.Message)"
    }

    # A single object (not an array) is still valid JSON; coerce to an array.
    if ($null -eq $records) { $records = @() }
    $records = @($records)

    $artifacts = foreach ($r in $records) {
        # Validate required fields up front so a bad fixture fails loudly.
        foreach ($field in 'name', 'sizeBytes', 'createdAt', 'workflowName', 'workflowRunId') {
            if (-not ($r.PSObject.Properties.Name -contains $field)) {
                throw "Artifact record is missing required field '$field' in '$Path'."
            }
        }

        [pscustomobject]@{
            Name          = [string]   $r.name
            SizeBytes     = [long]     $r.sizeBytes
            CreatedAt     = [datetime] $r.createdAt
            WorkflowName  = [string]   $r.workflowName
            WorkflowRunId = [long]     $r.workflowRunId
        }
    }

    return @($artifacts)
}

function Get-ArtifactRetentionPlan {
    <#
    .SYNOPSIS
        Compute a deletion plan from a set of artifacts and retention policies.

    .OUTPUTS
        A PSCustomObject with:
          .Items   - one decision object per artifact (Action, Reason, Executed, ...)
          .Summary - aggregate counts / sizes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Artifacts,

        # Delete artifacts strictly older than this many days. 0/unset disables.
        [Nullable[int]] $MaxAgeDays,

        # Keep only the N newest artifacts per workflow group. 0/unset disables.
        [Nullable[int]] $KeepLatestPerWorkflow,

        # Cap the retained total size in bytes. 0/unset disables.
        [Nullable[long]] $MaxTotalSizeBytes,

        # Reference "now" for age calculations; defaults to the current time.
        [datetime] $ReferenceTime = (Get-Date)
    )

    # --- input validation -----------------------------------------------------
    if ($null -ne $MaxAgeDays -and $MaxAgeDays -lt 0) {
        throw "MaxAgeDays must be zero or positive (got $MaxAgeDays)."
    }
    if ($null -ne $KeepLatestPerWorkflow -and $KeepLatestPerWorkflow -lt 0) {
        throw "KeepLatestPerWorkflow must be zero or positive (got $KeepLatestPerWorkflow)."
    }
    if ($null -ne $MaxTotalSizeBytes -and $MaxTotalSizeBytes -lt 0) {
        throw "MaxTotalSizeBytes must be zero or positive (got $MaxTotalSizeBytes)."
    }

    # Build a mutable decision record for every artifact. Default: keep.
    $items = foreach ($a in @($Artifacts)) {
        [pscustomobject]@{
            Name          = $a.Name
            SizeBytes     = $a.SizeBytes
            CreatedAt     = $a.CreatedAt
            WorkflowName  = $a.WorkflowName
            WorkflowRunId = $a.WorkflowRunId
            AgeDays       = [math]::Floor(($ReferenceTime - $a.CreatedAt).TotalDays)
            Action        = 'Keep'
            Reason        = ''
            Executed      = $false
        }
    }
    $items = @($items)

    # Helper: mark an item deleted (only the first reason "wins" so the earliest
    # policy in the pipeline is the recorded cause).
    $markDelete = {
        param($item, $reason)
        if ($item.Action -ne 'Delete') {
            $item.Action = 'Delete'
            $item.Reason = $reason
        }
    }

    # --- policy 1: max age ----------------------------------------------------
    # Strictly older than the cutoff is deleted; exactly-at-cutoff is retained.
    if ($null -ne $MaxAgeDays -and $MaxAgeDays -gt 0) {
        foreach ($item in $items) {
            if ($item.AgeDays -gt $MaxAgeDays) {
                & $markDelete $item $script:ReasonMaxAge
            }
        }
    }

    # --- policy 2: keep latest N per workflow ---------------------------------
    if ($null -ne $KeepLatestPerWorkflow -and $KeepLatestPerWorkflow -ge 0) {
        $groups = $items | Where-Object Action -eq 'Keep' | Group-Object WorkflowName
        foreach ($group in $groups) {
            # Newest first; everything past index N-1 is surplus.
            $ordered = $group.Group | Sort-Object CreatedAt -Descending
            if ($ordered.Count -gt $KeepLatestPerWorkflow) {
                $surplus = $ordered | Select-Object -Skip $KeepLatestPerWorkflow
                foreach ($item in $surplus) {
                    & $markDelete $item $script:ReasonKeepLatest
                }
            }
        }
    }

    # --- policy 3: max total size ---------------------------------------------
    # Among survivors, drop oldest-first until the retained total fits the budget.
    if ($null -ne $MaxTotalSizeBytes -and $MaxTotalSizeBytes -ge 0) {
        $survivors = @($items | Where-Object Action -eq 'Keep')
        $retainedSize = Get-SizeSum $survivors

        if ($retainedSize -gt $MaxTotalSizeBytes) {
            # Oldest first so we keep the freshest artifacts.
            $candidates = $survivors | Sort-Object CreatedAt
            foreach ($item in $candidates) {
                if ($retainedSize -le $MaxTotalSizeBytes) { break }
                & $markDelete $item $script:ReasonMaxSize
                $retainedSize -= $item.SizeBytes
            }
        }
    }

    # --- summary --------------------------------------------------------------
    $deleted  = @($items | Where-Object Action -eq 'Delete')
    $retained = @($items | Where-Object Action -eq 'Keep')

    $reclaimed    = Get-SizeSum $deleted
    $retainedSize = Get-SizeSum $retained

    $summary = [pscustomobject]@{
        TotalCount     = $items.Count
        DeletedCount   = $deleted.Count
        RetainedCount  = $retained.Count
        SpaceReclaimed = [long] $reclaimed
        RetainedSize   = [long] $retainedSize
    }

    return [pscustomobject]@{
        Items   = $items
        Summary = $summary
    }
}

function Format-CleanupSummary {
    <#
    .SYNOPSIS
        Render a deletion plan as a human-readable, parser-friendly report.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Plan
    )

    $s = $Plan.Summary
    $sb = [System.Text.StringBuilder]::new()

    [void]$sb.AppendLine('===== Artifact Cleanup Plan =====')
    foreach ($item in $Plan.Items) {
        if ($item.Action -eq 'Delete') {
            [void]$sb.AppendLine(("DELETE  {0,-12} {1,10} bytes  [{2}]" -f $item.Name, $item.SizeBytes, $item.Reason))
        }
        else {
            [void]$sb.AppendLine(("KEEP    {0,-12} {1,10} bytes" -f $item.Name, $item.SizeBytes))
        }
    }
    [void]$sb.AppendLine('---------------------------------')
    [void]$sb.AppendLine("Artifacts total: $($s.TotalCount)")
    [void]$sb.AppendLine("Artifacts deleted: $($s.DeletedCount)")
    [void]$sb.AppendLine("Artifacts retained: $($s.RetainedCount)")
    [void]$sb.AppendLine("Space reclaimed: $($s.SpaceReclaimed) bytes ($(Format-Bytes $s.SpaceReclaimed))")
    [void]$sb.AppendLine("Retained size: $($s.RetainedSize) bytes ($(Format-Bytes $s.RetainedSize))")
    [void]$sb.AppendLine('=================================')

    return $sb.ToString()
}

function Format-Bytes {
    # Tiny helper: pretty-print a byte count. Kept private (not exported).
    param([long] $Bytes)
    $units = 'B', 'KB', 'MB', 'GB', 'TB'
    $value = [double] $Bytes
    $i = 0
    while ($value -ge 1024 -and $i -lt ($units.Count - 1)) {
        $value /= 1024
        $i++
    }
    return ('{0:0.##} {1}' -f $value, $units[$i])
}

function Invoke-ArtifactCleanup {
    <#
    .SYNOPSIS
        Load artifacts, compute a retention plan and (optionally) execute the
        deletions. Supports dry-run.

    .PARAMETER Path
        JSON fixture / data file (see Import-ArtifactData).

    .PARAMETER DeleteAction
        Script block invoked once per deleted artifact in execute mode. Receives
        the artifact decision object as its only argument. Defaults to a no-op so
        the engine is safe to run without wiring a real deleter.

    .PARAMETER DryRun
        When set, no deletion is performed; the plan is returned with DryRun=$true.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Nullable[int]]  $MaxAgeDays,
        [Nullable[int]]  $KeepLatestPerWorkflow,
        [Nullable[long]] $MaxTotalSizeBytes,

        [scriptblock] $DeleteAction = { param($artifact) },

        [switch] $DryRun,

        [datetime] $ReferenceTime = (Get-Date)
    )

    $artifacts = Import-ArtifactData -Path $Path

    # Forward only the policy parameters that were actually supplied.
    $planArgs = @{
        Artifacts     = $artifacts
        ReferenceTime = $ReferenceTime
    }
    if ($null -ne $MaxAgeDays)            { $planArgs.MaxAgeDays            = $MaxAgeDays }
    if ($null -ne $KeepLatestPerWorkflow) { $planArgs.KeepLatestPerWorkflow = $KeepLatestPerWorkflow }
    if ($null -ne $MaxTotalSizeBytes)     { $planArgs.MaxTotalSizeBytes     = $MaxTotalSizeBytes }

    $plan = Get-ArtifactRetentionPlan @planArgs

    if (-not $DryRun) {
        foreach ($item in ($plan.Items | Where-Object Action -eq 'Delete')) {
            try {
                & $DeleteAction $item
                $item.Executed = $true
            }
            catch {
                # Don't abort the whole run because one deletion failed; record it.
                Write-Warning "Failed to delete artifact '$($item.Name)': $($_.Exception.Message)"
                $item.Executed = $false
            }
        }
    }

    return [pscustomobject]@{
        DryRun  = [bool] $DryRun
        Items   = $plan.Items
        Summary = $plan.Summary
    }
}

Export-ModuleMember -Function Import-ArtifactData, Get-ArtifactRetentionPlan,
    Format-CleanupSummary, Invoke-ArtifactCleanup
