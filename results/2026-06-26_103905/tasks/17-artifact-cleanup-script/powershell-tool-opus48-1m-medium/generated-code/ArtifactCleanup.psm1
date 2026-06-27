# ArtifactCleanup.psm1
# Core retention/cleanup engine for CI build artifacts.
#
# The engine is intentionally pure: it takes artifact metadata + policy
# parameters and returns a deletion *plan* (an in-memory object). It never
# deletes anything itself, which makes it trivial to unit test and to run in
# dry-run mode. The thin CLI wrapper (Invoke-Cleanup.ps1) is what actually
# acts on a plan.

Set-StrictMode -Version Latest

# Validate a single artifact has the metadata we rely on. Throws a clear,
# actionable error otherwise (requirement: graceful error handling).
function Test-ArtifactShape {
    param([Parameter(Mandatory)] $Artifact, [int] $Index)

    foreach ($field in 'Name', 'Size', 'CreationDate', 'WorkflowRunId') {
        if (-not ($Artifact.PSObject.Properties.Name -contains $field)) {
            throw "Artifact at index $Index is missing required field '$field'."
        }
    }
    # Coerce/validate types so downstream math and sorting are well-defined.
    [long]$size = $Artifact.Size
    if ($size -lt 0) {
        throw "Artifact '$($Artifact.Name)' has a negative Size ($size); sizes must be >= 0."
    }
    try {
        [datetime]$Artifact.CreationDate | Out-Null
    } catch {
        throw "Artifact '$($Artifact.Name)' has an invalid CreationDate '$($Artifact.CreationDate)'."
    }
}

<#
.SYNOPSIS
    Build a deletion plan for a set of artifacts given retention policies.

.DESCRIPTION
    Policies (any combination; a value of 0 disables that policy):
      -MaxAgeDays            : delete artifacts older than N days.
      -KeepLatestPerWorkflow : within each WorkflowRunId, keep only the N newest.
      -MaxTotalSize          : keep total retained size <= N bytes by dropping
                               the oldest surviving artifacts first.

    Each artifact may accumulate multiple deletion reasons; it is deleted if it
    has at least one. The returned object exposes Delete, Retain and a Summary.
#>
function New-ArtifactCleanupPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Artifacts,
        [int]      $MaxAgeDays            = 0,
        [long]     $MaxTotalSize          = 0,
        [int]      $KeepLatestPerWorkflow = 0,
        [datetime] $Now                   = (Get-Date)
    )

    # --- Normalize & validate -------------------------------------------------
    # Wrap each input artifact in a working record carrying a mutable Reasons list.
    $records = @()
    for ($i = 0; $i -lt $Artifacts.Count; $i++) {
        $a = $Artifacts[$i]
        Test-ArtifactShape -Artifact $a -Index $i
        $records += [pscustomobject]@{
            Name          = [string]$a.Name
            Size          = [long]$a.Size
            CreationDate  = [datetime]$a.CreationDate
            WorkflowRunId = [string]$a.WorkflowRunId
            Reasons       = [System.Collections.Generic.List[string]]::new()
        }
    }

    # --- Policy 1: max age ----------------------------------------------------
    if ($MaxAgeDays -gt 0) {
        foreach ($r in $records) {
            if (($Now - $r.CreationDate).TotalDays -gt $MaxAgeDays) {
                $r.Reasons.Add('MaxAge')
            }
        }
    }

    # --- Policy 2: keep latest N per workflow ---------------------------------
    # Grouping is over the full set (independent of other policies) so the result
    # is order-insensitive and predictable.
    if ($KeepLatestPerWorkflow -gt 0) {
        foreach ($group in ($records | Group-Object WorkflowRunId)) {
            $ordered = $group.Group | Sort-Object CreationDate -Descending
            for ($idx = $KeepLatestPerWorkflow; $idx -lt $ordered.Count; $idx++) {
                if (-not $ordered[$idx].Reasons.Contains('KeepLatest')) {
                    $ordered[$idx].Reasons.Add('KeepLatest')
                }
            }
        }
    }

    # --- Policy 3: max total size --------------------------------------------
    # Only artifacts still surviving the above policies count toward the budget.
    # Drop the oldest survivors first until the retained total fits.
    if ($MaxTotalSize -gt 0) {
        $surviving = @($records | Where-Object { $_.Reasons.Count -eq 0 })
        $total = 0L
        foreach ($x in $surviving) { $total += [long]$x.Size }
        if ($total -gt $MaxTotalSize) {
            # Oldest first; deterministic tiebreak on Name.
            $candidates = $surviving | Sort-Object CreationDate, Name
            foreach ($c in $candidates) {
                if ($total -le $MaxTotalSize) { break }
                $c.Reasons.Add('MaxSize')
                $total -= $c.Size
            }
        }
    }

    # --- Partition & summarize ------------------------------------------------
    $delete = @($records | Where-Object { $_.Reasons.Count -gt 0 })
    $retain = @($records | Where-Object { $_.Reasons.Count -eq 0 })

    # Project to clean output objects (Reasons as a plain string[]).
    $project = {
        param($r)
        [pscustomobject]@{
            Name          = $r.Name
            Size          = $r.Size
            CreationDate  = $r.CreationDate
            WorkflowRunId = $r.WorkflowRunId
            Reasons       = @($r.Reasons)
        }
    }

    # Sum helper that is safe on an empty collection (Measure-Object emits
    # nothing for an empty pipeline, which StrictMode would choke on).
    $sumSize = {
        param($items)
        $s = 0L
        foreach ($x in $items) { $s += [long]$x.Size }
        $s
    }
    $reclaimed    = & $sumSize $delete
    $retainedSize = & $sumSize $retain

    [pscustomobject]@{
        Delete  = @($delete | ForEach-Object { & $project $_ })
        Retain  = @($retain | ForEach-Object { & $project $_ })
        Summary = [pscustomobject]@{
            TotalArtifacts = $records.Count
            RetainedCount  = $retain.Count
            DeletedCount   = $delete.Count
            SpaceReclaimed = [long]$reclaimed
            RetainedSize   = [long]$retainedSize
        }
    }
}

<#
.SYNOPSIS
    Render a cleanup plan into a stable, parseable text report.
.DESCRIPTION
    Produces a delimited PLAN_SUMMARY block plus per-artifact DELETE/RETAIN
    lines. The fixed key names make it safe for CI assertions.
#>
function Format-CleanupReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Plan,
        [switch] $DryRun
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('PLAN_SUMMARY_BEGIN')
    $lines.Add("TotalArtifacts: $($Plan.Summary.TotalArtifacts)")
    $lines.Add("Retained: $($Plan.Summary.RetainedCount)")
    $lines.Add("Deleted: $($Plan.Summary.DeletedCount)")
    $lines.Add("SpaceReclaimed: $($Plan.Summary.SpaceReclaimed)")
    $lines.Add("RetainedSize: $($Plan.Summary.RetainedSize)")
    $lines.Add("DryRun: $([bool]$DryRun)")
    $lines.Add('PLAN_SUMMARY_END')

    foreach ($d in ($Plan.Delete | Sort-Object Name)) {
        $lines.Add("DELETE: $($d.Name) [$([string]::Join(',', $d.Reasons))] size=$($d.Size)")
    }
    foreach ($r in ($Plan.Retain | Sort-Object Name)) {
        $lines.Add("RETAIN: $($r.Name) size=$($r.Size)")
    }

    return ($lines -join [Environment]::NewLine)
}

Export-ModuleMember -Function New-ArtifactCleanupPlan, Format-CleanupReport
