#
# ArtifactCleanup.psm1
#
# Applies GitHub Actions artifact retention policies (max age, max total
# size, keep-latest-N per workflow) to a set of artifact metadata records
# and produces a deletion plan with a summary. Supports dry-run execution.
#

function Import-ArtifactData {
    <#
    .SYNOPSIS
        Loads artifact metadata (Name, SizeBytes, CreatedDate, WorkflowId)
        from a JSON fixture file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Artifact data file not found: $Path"
    }

    $raw = Get-Content -LiteralPath $Path -Raw
    try {
        $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Failed to parse artifact data file '$Path' as JSON: $($_.Exception.Message)"
    }

    # ConvertFrom-Json returns a single object (not an array) when the JSON
    # document is a single object; normalize to an array either way.
    $items = @($parsed)

    foreach ($item in $items) {
        [pscustomobject]@{
            Name        = $item.Name
            SizeBytes   = [int64]$item.SizeBytes
            CreatedDate = [datetime]::Parse($item.CreatedDate, $null, [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal)
            WorkflowId  = $item.WorkflowId
        }
    }
}

function Get-ArtifactRetentionPlan {
    <#
    .SYNOPSIS
        Applies retention policies to a set of artifacts and returns a
        deletion plan (per-artifact action/reason) plus a summary.

    .DESCRIPTION
        Policy evaluation order per workflow group:
          1. KeepLatestN: the N most recently created artifacts in each
             WorkflowId group are protected and will never be deleted.
          2. MaxAge: any unprotected artifact older than MaxAgeDays is
             marked for deletion.
          3. MaxTotalSize: if the total size of artifacts still standing
             (protected + retained-by-age) exceeds MaxTotalSizeBytes,
             the oldest unprotected, not-yet-deleted artifacts are marked
             for deletion (oldest first) until the budget is met.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Artifacts,

        [Parameter(Mandatory = $true)]
        [int]$MaxAgeDays,

        [Parameter(Mandatory = $true)]
        [int64]$MaxTotalSizeBytes,

        [Parameter(Mandatory = $true)]
        [int]$KeepLatestN,

        [datetime]$Now = (Get-Date).ToUniversalTime()
    )

    if ($MaxAgeDays -lt 0) {
        throw "MaxAgeDays must be zero or greater (received $MaxAgeDays)."
    }
    if ($KeepLatestN -lt 0) {
        throw "KeepLatestN must be zero or greater (received $KeepLatestN)."
    }
    if ($MaxTotalSizeBytes -lt 0) {
        throw "MaxTotalSizeBytes must be zero or greater (received $MaxTotalSizeBytes)."
    }

    $totalSizeBefore = [int64]0
    foreach ($a in $Artifacts) { $totalSizeBefore += [int64]$a.SizeBytes }

    # Working entries carry Action/Reason alongside the source fields.
    $entries = foreach ($a in $Artifacts) {
        [pscustomobject]@{
            Name        = $a.Name
            SizeBytes   = [int64]$a.SizeBytes
            CreatedDate = $a.CreatedDate
            WorkflowId  = $a.WorkflowId
            Action      = 'Retain'
            Reason      = 'Retained'
        }
    }

    # Step 1: protect the latest N per workflow.
    $grouped = $entries | Group-Object -Property WorkflowId
    foreach ($group in $grouped) {
        $latest = $group.Group | Sort-Object -Property CreatedDate -Descending | Select-Object -First $KeepLatestN
        foreach ($item in $latest) {
            $item.Reason = 'Protected:KeepLatestN'
        }
    }
    $protectedNames = @{}
    foreach ($e in $entries) {
        if ($e.Reason -eq 'Protected:KeepLatestN') { $protectedNames[$e.Name] = $true }
    }

    # Step 2: max age, unprotected artifacts only.
    foreach ($e in $entries) {
        if ($protectedNames.ContainsKey($e.Name)) { continue }
        $ageDays = ($Now - $e.CreatedDate).TotalDays
        if ($ageDays -gt $MaxAgeDays) {
            $e.Action = 'Delete'
            $e.Reason = 'MaxAge'
        }
    }

    # Step 3: max total size, oldest unprotected/not-yet-deleted first.
    $remaining = ($entries | Where-Object { $_.Action -ne 'Delete' } | Measure-Object -Property SizeBytes -Sum).Sum
    if (-not $remaining) { $remaining = [int64]0 }

    if ($remaining -gt $MaxTotalSizeBytes) {
        $candidates = $entries |
            Where-Object { $_.Action -ne 'Delete' -and -not $protectedNames.ContainsKey($_.Name) } |
            Sort-Object -Property CreatedDate
        foreach ($c in $candidates) {
            if ($remaining -le $MaxTotalSizeBytes) { break }
            $c.Action = 'Delete'
            $c.Reason = 'MaxTotalSize'
            $remaining -= $c.SizeBytes
        }
    }

    $deleted = @($entries | Where-Object { $_.Action -eq 'Delete' })
    $retained = @($entries | Where-Object { $_.Action -ne 'Delete' })
    $spaceReclaimed = [int64]0
    foreach ($d in $deleted) { $spaceReclaimed += $d.SizeBytes }
    $remainingSize = $totalSizeBefore - $spaceReclaimed

    [pscustomobject]@{
        Artifacts = @($entries)
        Summary   = [pscustomobject]@{
            TotalArtifacts       = $entries.Count
            DeletedCount         = $deleted.Count
            RetainedCount        = $retained.Count
            TotalSizeBytesBefore = $totalSizeBefore
            SpaceReclaimedBytes  = $spaceReclaimed
            RemainingSizeBytes   = $remainingSize
        }
    }
}

function Remove-Artifact {
    <#
    .SYNOPSIS
        Performs the actual deletion side effect for a single artifact.
        Isolated into its own function so it can be mocked in tests and so
        a real implementation (e.g. calling the GitHub Actions artifacts
        API) can be substituted without touching the planning logic.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )
    # Mock data has no real artifact store to delete from; a real
    # implementation would call the GitHub API here.
    if ($PSCmdlet.ShouldProcess($Name, 'Remove artifact')) {
        Write-Verbose "Removed artifact '$Name'."
    }
}

function Invoke-ArtifactCleanup {
    <#
    .SYNOPSIS
        Executes (or simulates, in -DryRun mode) the deletions determined
        by a retention plan produced by Get-ArtifactRetentionPlan.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Plan,

        [switch]$DryRun
    )

    $toDelete = @($Plan.Artifacts | Where-Object { $_.Action -eq 'Delete' })
    $deletedNames = @()

    foreach ($artifact in $toDelete) {
        # Write-Host (not Write-Output): this is log/console output, kept out
        # of the function's return value so callers can assign $result =
        # Invoke-ArtifactCleanup ... without swallowing these lines.
        if ($DryRun) {
            Write-Host "[DRY RUN] Would delete: $($artifact.Name) ($($artifact.SizeBytes) bytes, reason: $($artifact.Reason))"
        } else {
            Remove-Artifact -Name $artifact.Name
            Write-Host "Deleted: $($artifact.Name) ($($artifact.SizeBytes) bytes, reason: $($artifact.Reason))"
        }
        $deletedNames += $artifact.Name
    }

    [pscustomobject]@{
        DryRun       = [bool]$DryRun
        DeletedNames = $deletedNames
        Summary      = $Plan.Summary
    }
}

Export-ModuleMember -Function Import-ArtifactData, Get-ArtifactRetentionPlan, Remove-Artifact, Invoke-ArtifactCleanup
