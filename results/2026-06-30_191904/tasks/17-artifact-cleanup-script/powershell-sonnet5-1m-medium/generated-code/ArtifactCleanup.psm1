#requires -Version 7.0

<#
    ArtifactCleanup module.

    Applies GitHub Actions artifact retention policies to a list of artifact
    records and produces a deletion plan (which artifacts to keep / delete,
    plus a space-reclaimed summary). Deletion itself is delegated to
    Remove-Artifact so callers (and tests) can substitute a real GitHub API
    call, a mock, or a dry-run no-op.
#>

Set-StrictMode -Version Latest

$script:RequiredArtifactProperties = @('Name', 'SizeBytes', 'CreatedAt', 'WorkflowRunId', 'WorkflowName')

function Test-ArtifactRecord {
    <#
        Validates a single artifact record has the properties this module
        needs, throwing a message that names the artifact and the missing
        or invalid field so failures are easy to diagnose from CI logs.
    #>
    param(
        [Parameter(Mandatory)]
        $Artifact,

        [Parameter(Mandatory)]
        [int]$Index
    )

    $label = "Artifact at index $Index"
    if ($Artifact.PSObject.Properties.Name -contains 'Name' -and $Artifact.Name) {
        $label = "Artifact '$($Artifact.Name)' (index $Index)"
    }

    foreach ($prop in $script:RequiredArtifactProperties) {
        if (-not ($Artifact.PSObject.Properties.Name -contains $prop) -or $null -eq $Artifact.$prop -or $Artifact.$prop -eq '') {
            throw "$label is missing required property '$prop'."
        }
    }

    if ($Artifact.SizeBytes -isnot [int] -and $Artifact.SizeBytes -isnot [long] -and $Artifact.SizeBytes -isnot [double]) {
        throw "$label has a non-numeric SizeBytes value: '$($Artifact.SizeBytes)'."
    }
    if ($Artifact.SizeBytes -lt 0) {
        throw "$label has a negative SizeBytes value: '$($Artifact.SizeBytes)'."
    }

    try {
        [datetime]$Artifact.CreatedAt | Out-Null
    } catch {
        throw "$label has a CreatedAt value that cannot be parsed as a date: '$($Artifact.CreatedAt)'."
    }
}

function Get-ArtifactRetentionPlan {
    <#
        .SYNOPSIS
        Computes which artifacts should be deleted under a combination of
        retention policies, and which should be retained.

        .PARAMETER Artifacts
        Objects with Name, SizeBytes, CreatedAt, WorkflowRunId, WorkflowName.

        .PARAMETER MaxAgeDays
        Delete artifacts older than this many days. 0 disables the policy.

        .PARAMETER MaxTotalSizeBytes
        After age/keep-latest-N are applied, trim the oldest remaining
        artifacts until total retained size is at or under this budget.
        0 disables the policy.

        .PARAMETER KeepLatestN
        Per WorkflowName, keep only the N most recently created artifacts.
        0 disables the policy.

        .PARAMETER Now
        The reference "current time" used for age calculations. Defaults to
        Get-Date; tests and CI pass a fixed value for determinism.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [array]$Artifacts,

        [int]$MaxAgeDays = 0,

        [long]$MaxTotalSizeBytes = 0,

        [int]$KeepLatestN = 0,

        [datetime]$Now = (Get-Date)
    )

    for ($i = 0; $i -lt $Artifacts.Count; $i++) {
        Test-ArtifactRecord -Artifact $Artifacts[$i] -Index $i
    }

    # Wrap each artifact in a mutable plan item so multiple policies can mark
    # the same artifact for deletion without conflicting or double counting.
    $items = for ($i = 0; $i -lt $Artifacts.Count; $i++) {
        $a = $Artifacts[$i]
        [PSCustomObject]@{
            Index         = $i
            Name          = $a.Name
            SizeBytes     = [long]$a.SizeBytes
            CreatedAt     = [datetime]$a.CreatedAt
            WorkflowRunId = $a.WorkflowRunId
            WorkflowName  = $a.WorkflowName
            Delete        = $false
            Reason        = $null
        }
    }

    # Policy 1: max age.
    if ($MaxAgeDays -gt 0) {
        foreach ($item in $items) {
            $ageDays = ($Now - $item.CreatedAt).TotalDays
            if ($ageDays -gt $MaxAgeDays) {
                $item.Delete = $true
                $item.Reason = 'MaxAge'
            }
        }
    }

    # Policy 2: keep only the latest N artifacts per workflow.
    if ($KeepLatestN -gt 0 -and $items.Count -gt 0) {
        $groups = $items | Group-Object -Property WorkflowName
        foreach ($group in $groups) {
            $sorted = $group.Group | Sort-Object -Property CreatedAt -Descending
            if ($sorted.Count -gt $KeepLatestN) {
                $excess = $sorted | Select-Object -Skip $KeepLatestN
                foreach ($item in $excess) {
                    if (-not $item.Delete) {
                        $item.Delete = $true
                        $item.Reason = 'KeepLatestN'
                    }
                }
            }
        }
    }

    # Policy 3: total size budget. Applied last, trimming the oldest of
    # whatever policies 1 and 2 left retained, until under budget.
    if ($MaxTotalSizeBytes -gt 0) {
        $retained = @($items | Where-Object { -not $_.Delete })
        $totalSize = 0
        if ($retained.Count -gt 0) { $totalSize = ($retained | Measure-Object -Property SizeBytes -Sum).Sum }

        if ($totalSize -gt $MaxTotalSizeBytes) {
            $oldestFirst = $retained | Sort-Object -Property CreatedAt
            foreach ($item in $oldestFirst) {
                if ($totalSize -le $MaxTotalSizeBytes) { break }
                $item.Delete = $true
                $item.Reason = 'MaxTotalSize'
                $totalSize -= $item.SizeBytes
            }
        }
    }

    $toDelete = @($items | Where-Object { $_.Delete } | Sort-Object Index)
    $toRetain = @($items | Where-Object { -not $_.Delete } | Sort-Object Index)

    $spaceReclaimed = 0
    if ($toDelete.Count -gt 0) { $spaceReclaimed = ($toDelete | Measure-Object -Property SizeBytes -Sum).Sum }
    $spaceRetained = 0
    if ($toRetain.Count -gt 0) { $spaceRetained = ($toRetain | Measure-Object -Property SizeBytes -Sum).Sum }

    [PSCustomObject]@{
        ToDelete            = $toDelete
        ToRetain            = $toRetain
        TotalArtifacts      = $Artifacts.Count
        DeletedCount        = $toDelete.Count
        RetainedCount       = $toRetain.Count
        SpaceReclaimedBytes = [long]$spaceReclaimed
        SpaceRetainedBytes  = [long]$spaceRetained
    }
}

function Remove-Artifact {
    <#
        Deletes a single artifact. This is a stub: in a real pipeline this
        would call the GitHub REST API
        (DELETE /repos/{owner}/{repo}/actions/artifacts/{artifact_id})
        using a token with the `actions:write` permission. It is left as a
        stub here so the CI workflow in this repo can run without secrets
        or network access, and so tests can Mock it to assert deletions
        happen (or don't, in dry-run mode) without touching a real API.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Artifact
    )

    Write-Output "Removed artifact '$($Artifact.Name)' (workflow run: $($Artifact.WorkflowRunId), reason: $($Artifact.Reason))"
}

function Invoke-ArtifactCleanup {
    <#
        .SYNOPSIS
        Computes a retention plan and carries it out: deletes (or, in
        -DryRun mode, reports without deleting) every artifact the plan
        marks for deletion.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [array]$Artifacts,

        [int]$MaxAgeDays = 0,

        [long]$MaxTotalSizeBytes = 0,

        [int]$KeepLatestN = 0,

        [switch]$DryRun,

        [datetime]$Now = (Get-Date)
    )

    $plan = Get-ArtifactRetentionPlan -Artifacts $Artifacts -MaxAgeDays $MaxAgeDays -MaxTotalSizeBytes $MaxTotalSizeBytes -KeepLatestN $KeepLatestN -Now $Now

    foreach ($artifact in $plan.ToDelete) {
        if ($DryRun) {
            Write-Output "[DryRun] Would delete artifact '$($artifact.Name)' (workflow run: $($artifact.WorkflowRunId), reason: $($artifact.Reason))"
        } else {
            Remove-Artifact -Artifact $artifact
        }
    }

    $plan | Add-Member -NotePropertyName DryRun -NotePropertyValue ([bool]$DryRun) -PassThru
}

Export-ModuleMember -Function Get-ArtifactRetentionPlan, Remove-Artifact, Invoke-ArtifactCleanup
