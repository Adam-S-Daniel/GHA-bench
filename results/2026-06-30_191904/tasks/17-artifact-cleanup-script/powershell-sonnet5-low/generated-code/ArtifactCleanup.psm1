# ArtifactCleanup.psm1
# Applies retention policies to a list of build artifacts and produces a
# deletion plan (what to delete, what to retain, and a summary of the result).
#
# Policies (all optional, applied in combination):
#   - MaxAgeDays:        delete artifacts older than N days
#   - KeepLatestN:       within each WorkflowRunId group, keep only the N newest
#   - MaxTotalSizeBytes: after the above, if retained artifacts still exceed the
#                        size cap, delete oldest-first until under the cap

function Get-ArtifactCleanupPlan {
    <#
    .SYNOPSIS
        Applies retention policies to a set of artifacts and returns a cleanup plan.
    #>
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Artifacts,

        [int]$MaxAgeDays = 0,

        [int]$KeepLatestN = 0,

        [Nullable[long]]$MaxTotalSizeBytes = $null,

        [DateTime]$Now = (Get-Date)
    )

    if ($null -ne $MaxTotalSizeBytes -and $MaxTotalSizeBytes -lt 0) {
        throw "MaxTotalSizeBytes must be a non-negative value; got $MaxTotalSizeBytes."
    }

    foreach ($artifact in $Artifacts) {
        foreach ($prop in @('Name', 'SizeBytes', 'CreatedAt', 'WorkflowRunId')) {
            if (-not (Get-Member -InputObject $artifact -Name $prop -MemberType NoteProperty)) {
                throw "Artifact is missing required property '$prop'. Each artifact must have Name, SizeBytes, CreatedAt, and WorkflowRunId."
            }
        }
    }

    # Track deletion reasons per artifact via a hashtable keyed by object identity.
    $toDeleteSet = [System.Collections.Generic.HashSet[object]]::new()

    # Policy 1: Max age
    if ($MaxAgeDays -gt 0) {
        foreach ($artifact in $Artifacts) {
            $ageDays = ($Now - $artifact.CreatedAt).TotalDays
            if ($ageDays -gt $MaxAgeDays) {
                [void]$toDeleteSet.Add($artifact)
            }
        }
    }

    # Policy 2: Keep latest N per workflow run
    if ($KeepLatestN -gt 0) {
        $groups = $Artifacts | Group-Object -Property WorkflowRunId
        foreach ($group in $groups) {
            $sorted = $group.Group | Sort-Object -Property CreatedAt -Descending
            $excess = $sorted | Select-Object -Skip $KeepLatestN
            foreach ($artifact in $excess) {
                [void]$toDeleteSet.Add($artifact)
            }
        }
    }

    # Policy 3: Max total size (evaluated against what's left after the above policies)
    if ($null -ne $MaxTotalSizeBytes) {
        $remaining = $Artifacts | Where-Object { -not $toDeleteSet.Contains($_) }
        $oldestFirst = $remaining | Sort-Object -Property CreatedAt
        $runningTotal = ($remaining | Measure-Object -Property SizeBytes -Sum).Sum
        if (-not $runningTotal) { $runningTotal = 0 }

        foreach ($artifact in $oldestFirst) {
            if ($runningTotal -le $MaxTotalSizeBytes) { break }
            [void]$toDeleteSet.Add($artifact)
            $runningTotal -= $artifact.SizeBytes
        }
    }

    $toDelete = $Artifacts | Where-Object { $toDeleteSet.Contains($_) }
    $toRetain = $Artifacts | Where-Object { -not $toDeleteSet.Contains($_) }

    $spaceReclaimed = ($toDelete | Measure-Object -Property SizeBytes -Sum).Sum
    if (-not $spaceReclaimed) { $spaceReclaimed = 0 }

    $summary = [PSCustomObject]@{
        TotalSpaceReclaimedBytes = $spaceReclaimed
        RetainedCount            = @($toRetain).Count
        DeletedCount             = @($toDelete).Count
    }

    [PSCustomObject]@{
        ToDelete = @($toDelete)
        ToRetain = @($toRetain)
        Summary  = $summary
    }
}

function Invoke-ArtifactCleanup {
    <#
    .SYNOPSIS
        Computes a cleanup plan and, unless -DryRun is specified, executes it by
        invoking DeleteAction for each artifact marked for deletion.
    #>
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Artifacts,

        [int]$MaxAgeDays = 0,

        [int]$KeepLatestN = 0,

        [Nullable[long]]$MaxTotalSizeBytes = $null,

        [DateTime]$Now = (Get-Date),

        [switch]$DryRun,

        [Parameter(Mandatory)]
        [ScriptBlock]$DeleteAction
    )

    $plan = Get-ArtifactCleanupPlan -Artifacts $Artifacts -MaxAgeDays $MaxAgeDays -KeepLatestN $KeepLatestN -MaxTotalSizeBytes $MaxTotalSizeBytes -Now $Now

    if (-not $DryRun) {
        foreach ($artifact in $plan.ToDelete) {
            try {
                & $DeleteAction $artifact
            } catch {
                throw "Failed to delete artifact '$($artifact.Name)': $($_.Exception.Message)"
            }
        }
    }

    [PSCustomObject]@{
        Plan   = $plan
        DryRun = [bool]$DryRun
    }
}

function Format-CleanupReport {
    <#
    .SYNOPSIS
        Renders a human-readable text report for a cleanup plan.
    #>
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Plan,

        [switch]$DryRun
    )

    $lines = @()
    $lines += '=== Artifact Cleanup Report ==='
    if ($DryRun) {
        $lines += '[DRY RUN] No artifacts were actually deleted.'
    }
    $lines += "Deleted: $($Plan.Summary.DeletedCount)"
    $lines += "Retained: $($Plan.Summary.RetainedCount)"
    $lines += "Space reclaimed: $($Plan.Summary.TotalSpaceReclaimedBytes) bytes"

    if ($Plan.ToDelete.Count -gt 0) {
        $lines += ''
        $lines += 'Artifacts to delete:'
        foreach ($artifact in $Plan.ToDelete) {
            $lines += "  - $($artifact.Name) ($($artifact.SizeBytes) bytes, run $($artifact.WorkflowRunId))"
        }
    }

    if ($Plan.ToRetain.Count -gt 0) {
        $lines += ''
        $lines += 'Artifacts retained:'
        foreach ($artifact in $Plan.ToRetain) {
            $lines += "  - $($artifact.Name) ($($artifact.SizeBytes) bytes, run $($artifact.WorkflowRunId))"
        }
    }

    $lines -join [Environment]::NewLine
}

Export-ModuleMember -Function Get-ArtifactCleanupPlan, Invoke-ArtifactCleanup, Format-CleanupReport
