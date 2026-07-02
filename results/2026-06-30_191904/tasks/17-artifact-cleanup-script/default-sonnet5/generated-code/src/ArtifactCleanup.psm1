# ArtifactCleanup.psm1
#
# Core retention-policy engine for cleaning up CI/CD build artifacts.
#
# An "artifact" is a PSCustomObject with:
#   Id            - unique identifier (string)
#   Name          - artifact name (string)
#   SizeBytes     - size in bytes (long)
#   CreatedAt     - creation timestamp (datetime)
#   WorkflowName  - the workflow that produced it (string)
#   WorkflowRunId - the specific run that produced it (string)
#
# Retention is evaluated in three independent, composable stages:
#   1. Keep-latest-N  : protect artifacts belonging to the N most recent runs
#                        per workflow (a hard floor -- never deleted by the
#                        other two policies).
#   2. Max age        : delete unprotected artifacts older than MaxAgeDays.
#   3. Max total size : if the retained set still exceeds the size budget,
#                        delete the oldest unprotected survivors first until
#                        the budget is met (or no unprotected artifacts remain).

function Get-ProtectedArtifactIds {
    <#
    .SYNOPSIS
        Returns the Ids of artifacts that belong to the latest N runs of each
        workflow. These artifacts are protected from age/size-based deletion.
    #>
    param(
        [Parameter(Mandatory)] [array] $Artifacts,
        [Parameter(Mandatory)] [int] $KeepLatestN
    )

    if ($KeepLatestN -le 0) {
        return @()
    }

    $protectedIds = [System.Collections.Generic.List[string]]::new()

    $byWorkflow = $Artifacts | Group-Object -Property WorkflowName
    foreach ($workflowGroup in $byWorkflow) {
        # Rank distinct runs (not individual artifacts) by their most recent
        # CreatedAt so that multiple artifacts from the same run are kept or
        # dropped together.
        $runs = $workflowGroup.Group |
            Group-Object -Property WorkflowRunId |
            ForEach-Object {
                [PSCustomObject]@{
                    WorkflowRunId = $_.Name
                    LatestCreatedAt = ($_.Group | Measure-Object -Property CreatedAt -Maximum).Maximum
                }
            } |
            Sort-Object -Property LatestCreatedAt -Descending

        $keptRunIds = $runs | Select-Object -First $KeepLatestN -ExpandProperty WorkflowRunId

        $workflowGroup.Group |
            Where-Object { $keptRunIds -contains $_.WorkflowRunId } |
            ForEach-Object { $protectedIds.Add($_.Id) }
    }

    return $protectedIds.ToArray()
}

function Get-ExpiredArtifactIds {
    <#
    .SYNOPSIS
        Returns the Ids of unprotected artifacts whose age (relative to -Now)
        exceeds MaxAgeDays.
    #>
    param(
        [Parameter(Mandatory)] [array] $Artifacts,
        [Parameter(Mandatory)] [int] $MaxAgeDays,
        [Parameter(Mandatory)] [datetime] $Now,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $ProtectedIds
    )

    $cutoff = $Now.AddDays(-1 * $MaxAgeDays)

    $expired = $Artifacts |
        Where-Object { $ProtectedIds -notcontains $_.Id } |
        Where-Object { $_.CreatedAt -lt $cutoff } |
        Select-Object -ExpandProperty Id

    return @($expired)
}

function Get-SizeBudgetArtifactIds {
    <#
    .SYNOPSIS
        Given the artifacts that are still retained (i.e. survived the age
        policy), returns the Ids of unprotected artifacts to evict -- oldest
        first -- until the total size is within MaxTotalSizeBytes. Protected
        artifacts are never evicted, even if the budget cannot be met without
        them.
    #>
    param(
        [Parameter(Mandatory)] [array] $Artifacts,
        [Parameter(Mandatory)] [long] $MaxTotalSizeBytes,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $ProtectedIds
    )

    $totalSize = ($Artifacts | Measure-Object -Property SizeBytes -Sum).Sum
    if (-not $totalSize) { $totalSize = 0 }

    $evicted = [System.Collections.Generic.List[string]]::new()
    if ($totalSize -le $MaxTotalSizeBytes) {
        return $evicted.ToArray()
    }

    $candidates = $Artifacts |
        Where-Object { $ProtectedIds -notcontains $_.Id } |
        Sort-Object -Property CreatedAt

    foreach ($candidate in $candidates) {
        if ($totalSize -le $MaxTotalSizeBytes) {
            break
        }
        $evicted.Add($candidate.Id)
        $totalSize -= $candidate.SizeBytes
    }

    return $evicted.ToArray()
}

function New-RetentionPlan {
    <#
    .SYNOPSIS
        Applies keep-latest-N, max-age, and max-total-size retention policies
        to a list of artifacts and returns a plan describing what would be
        retained and deleted.
    #>
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [array] $Artifacts,
        [Parameter(Mandatory)] [int] $MaxAgeDays,
        [Parameter(Mandatory)] [long] $MaxTotalSizeBytes,
        [Parameter(Mandatory)] [int] $KeepLatestN,
        [Parameter(Mandatory)] [datetime] $Now
    )

    if ($MaxAgeDays -lt 0) {
        throw "New-RetentionPlan: MaxAgeDays must be zero or greater (got $MaxAgeDays)."
    }
    if ($MaxTotalSizeBytes -lt 0) {
        throw "New-RetentionPlan: MaxTotalSizeBytes must be zero or greater (got $MaxTotalSizeBytes)."
    }
    if ($KeepLatestN -lt 0) {
        throw "New-RetentionPlan: KeepLatestN must be zero or greater (got $KeepLatestN)."
    }

    $duplicateIds = $Artifacts | Group-Object -Property Id | Where-Object { $_.Count -gt 1 }
    if ($duplicateIds) {
        $names = ($duplicateIds | Select-Object -ExpandProperty Name) -join ', '
        throw "New-RetentionPlan: found duplicate artifact Id(s): $names. Each artifact must have a unique Id."
    }

    $totalSizeBefore = ($Artifacts | Measure-Object -Property SizeBytes -Sum).Sum
    if (-not $totalSizeBefore) { $totalSizeBefore = 0 }

    $protectedIds = Get-ProtectedArtifactIds -Artifacts $Artifacts -KeepLatestN $KeepLatestN
    $expiredIds = Get-ExpiredArtifactIds -Artifacts $Artifacts -MaxAgeDays $MaxAgeDays -Now $Now -ProtectedIds $protectedIds

    $survivingAfterAge = $Artifacts | Where-Object { $expiredIds -notcontains $_.Id }
    $sizeEvictedIds = Get-SizeBudgetArtifactIds -Artifacts $survivingAfterAge -MaxTotalSizeBytes $MaxTotalSizeBytes -ProtectedIds $protectedIds

    $deletedIds = @($expiredIds) + @($sizeEvictedIds)

    $deletedArtifacts = @($Artifacts | Where-Object { $deletedIds -contains $_.Id })
    $retainedArtifacts = @($Artifacts | Where-Object { $deletedIds -notcontains $_.Id })

    $reclaimedBytes = ($deletedArtifacts | Measure-Object -Property SizeBytes -Sum).Sum
    if (-not $reclaimedBytes) { $reclaimedBytes = 0 }

    $totalSizeAfter = $totalSizeBefore - $reclaimedBytes

    return [PSCustomObject]@{
        Now                  = $Now
        Policy               = [PSCustomObject]@{
            MaxAgeDays         = $MaxAgeDays
            MaxTotalSizeBytes  = $MaxTotalSizeBytes
            KeepLatestN        = $KeepLatestN
        }
        TotalArtifactCount   = $Artifacts.Count
        RetainedArtifacts    = $retainedArtifacts
        DeletedArtifacts     = $deletedArtifacts
        RetainedCount        = $retainedArtifacts.Count
        DeletedCount         = $deletedArtifacts.Count
        TotalSizeBytesBefore = $totalSizeBefore
        TotalSizeBytesAfter  = $totalSizeAfter
        ReclaimedBytes       = $reclaimedBytes
    }
}

function Invoke-ArtifactCleanup {
    <#
    .SYNOPSIS
        Executes (or simulates, in -DryRun mode) the deletions described by a
        retention plan. The actual deletion mechanism is injected via
        -DeleteAction so callers can plug in a real API call while tests can
        plug in a mock.
    #>
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Plan,
        [switch] $DryRun,
        [Parameter(Mandatory)] [scriptblock] $DeleteAction
    )

    $actionsInvoked = 0
    if (-not $DryRun) {
        foreach ($artifact in $Plan.DeletedArtifacts) {
            & $DeleteAction $artifact
            $actionsInvoked++
        }
    }

    return [PSCustomObject]@{
        DryRun         = [bool]$DryRun
        ActionsInvoked = $actionsInvoked
    }
}

function Format-RetentionSummary {
    <#
    .SYNOPSIS
        Renders a retention plan as a human-readable, deterministically
        worded text report suitable for CI logs.
    #>
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Plan,
        [switch] $DryRun
    )

    $mb = [Math]::Round($Plan.ReclaimedBytes / 1000000, 2)
    $mbText = $mb.ToString('0.00', [System.Globalization.CultureInfo]::InvariantCulture)

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('Artifact Cleanup Plan' + $(if ($DryRun) { ' (DRY RUN)' } else { '' }))
    $lines.Add('=====================')
    $lines.Add("Policy: MaxAgeDays=$($Plan.Policy.MaxAgeDays), MaxTotalSizeBytes=$($Plan.Policy.MaxTotalSizeBytes), KeepLatestN=$($Plan.Policy.KeepLatestN)")
    $lines.Add("Total artifacts scanned: $($Plan.TotalArtifactCount)")
    $lines.Add("Artifacts retained: $($Plan.RetainedCount)")
    $lines.Add("Artifacts deleted: $($Plan.DeletedCount)")
    $lines.Add("Total space reclaimed: $($Plan.ReclaimedBytes) bytes ($mbText MB)")
    if ($DryRun) {
        $lines.Add('Mode: DRY RUN - no artifacts were actually deleted.')
    }

    return ($lines -join [Environment]::NewLine)
}

Export-ModuleMember -Function Get-ProtectedArtifactIds, Get-ExpiredArtifactIds, Get-SizeBudgetArtifactIds, New-RetentionPlan, Invoke-ArtifactCleanup, Format-RetentionSummary
