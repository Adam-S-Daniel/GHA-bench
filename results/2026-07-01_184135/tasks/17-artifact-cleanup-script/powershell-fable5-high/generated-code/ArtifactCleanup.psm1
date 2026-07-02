<#
.SYNOPSIS
    Artifact retention-policy engine for CI artifact cleanup.

.DESCRIPTION
    Given a list of artifact metadata records (Name, SizeBytes, CreatedAt,
    WorkflowRunId), Get-ArtifactRetentionPlan applies retention policies and
    produces a deletion plan. Built incrementally via red/green TDD — see
    tests/ArtifactCleanup.Tests.ps1 for the cycle-by-cycle history.
#>

Set-StrictMode -Version Latest

function Assert-ValidArtifact {
    <#
    .SYNOPSIS
        Validates one artifact record, throwing a meaningful error that names
        the offending artifact and the exact problem.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Artifact)

    foreach ($property in 'Name', 'SizeBytes', 'CreatedAt', 'WorkflowRunId') {
        if (-not ($Artifact.PSObject.Properties.Name -contains $property)) {
            throw "Invalid artifact record: missing required property '$property'. Record: $($Artifact | ConvertTo-Json -Compress)"
        }
    }

    if ([long]$Artifact.SizeBytes -lt 0) {
        throw "Invalid artifact '$($Artifact.Name)': negative SizeBytes ($($Artifact.SizeBytes))."
    }

    $parsed = [datetime]::MinValue
    if (-not [datetime]::TryParse([string]$Artifact.CreatedAt, [ref]$parsed)) {
        throw "Invalid artifact '$($Artifact.Name)': invalid CreatedAt value '$($Artifact.CreatedAt)' (expected an ISO 8601 date)."
    }
}

function Get-ArtifactRetentionPlan {
    <#
    .SYNOPSIS
        Applies retention policies to artifacts and returns a deletion plan.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Artifacts,

        # Artifacts older than this many days are deleted (0 = policy disabled).
        [int]$MaxAgeDays = 0,

        # The N newest artifacts of each workflow run are never deleted
        # (0 = no per-workflow protection).
        [int]$KeepLatestPerWorkflow = 0,

        # If the retained set still exceeds this many bytes after the age
        # pass, the oldest unprotected artifacts are evicted until it fits
        # (0 = no size cap).
        [long]$MaxTotalSizeBytes = 0,

        # Fixed "now" used for age calculations so results are deterministic.
        [Parameter(Mandatory)]
        [datetime]$ReferenceDate
    )

    # Fail fast with actionable messages before touching any policy logic.
    if ($MaxAgeDays -lt 0) { throw "MaxAgeDays must be >= 0 (got $MaxAgeDays)." }
    if ($KeepLatestPerWorkflow -lt 0) { throw "KeepLatestPerWorkflow must be >= 0 (got $KeepLatestPerWorkflow)." }
    if ($MaxTotalSizeBytes -lt 0) { throw "MaxTotalSizeBytes must be >= 0 (got $MaxTotalSizeBytes)." }
    foreach ($artifact in $Artifacts) { Assert-ValidArtifact -Artifact $artifact }

    $delete = [System.Collections.Generic.List[object]]::new()
    $retain = [System.Collections.Generic.List[object]]::new()

    # Build the protected set: the N newest artifacts within each workflow
    # run. Protected artifacts survive every deletion policy.
    $protected = @{}
    if ($KeepLatestPerWorkflow -gt 0) {
        foreach ($group in ($Artifacts | Group-Object WorkflowRunId)) {
            $newest = $group.Group |
                Sort-Object { [datetime]$_.CreatedAt } -Descending |
                Select-Object -First $KeepLatestPerWorkflow
            foreach ($a in $newest) { $protected[$a.Name] = $true }
        }
    }

    foreach ($artifact in $Artifacts) {
        $created = ([datetime]$artifact.CreatedAt).ToUniversalTime()
        $ageDays = ($ReferenceDate.ToUniversalTime() - $created).TotalDays

        if ($protected.ContainsKey($artifact.Name)) {
            $retain.Add($artifact)
        }
        elseif ($MaxAgeDays -gt 0 -and $ageDays -gt $MaxAgeDays) {
            $delete.Add(($artifact | Select-Object *, @{
                Name = 'Reason'; Expression = { "exceeds max age of $MaxAgeDays days" }
            }))
        }
        else {
            $retain.Add($artifact)
        }
    }

    # Size pass: if what survived the age pass is still over the cap, evict
    # the oldest unprotected artifacts first (protected ones are untouchable,
    # so the cap is best-effort when protection dominates).
    if ($MaxTotalSizeBytes -gt 0) {
        [long]$retainedBytes = 0
        foreach ($a in $retain) { $retainedBytes += [long]$a.SizeBytes }
        $evictable = $retain |
            Where-Object { -not $protected.ContainsKey($_.Name) } |
            Sort-Object { [datetime]$_.CreatedAt }

        foreach ($victim in $evictable) {
            if ($retainedBytes -le $MaxTotalSizeBytes) { break }
            $retain.Remove($victim) | Out-Null
            $retainedBytes -= $victim.SizeBytes
            $delete.Add(($victim | Select-Object *, @{
                Name = 'Reason'; Expression = { "evicted to satisfy max total size of $MaxTotalSizeBytes bytes" }
            }))
        }
    }

    # Measure-Object emits nothing for empty input under StrictMode, so
    # accumulate the totals explicitly.
    [long]$reclaimed = 0
    foreach ($d in $delete) { $reclaimed += [long]$d.SizeBytes }
    [long]$kept = 0
    foreach ($r in $retain) { $kept += [long]$r.SizeBytes }

    [pscustomobject]@{
        Delete  = $delete.ToArray()
        Retain  = $retain.ToArray()
        Summary = [pscustomobject]@{
            DeletedCount   = $delete.Count
            RetainedCount  = $retain.Count
            ReclaimedBytes = $reclaimed
            RetainedBytes  = $kept
        }
    }
}

function Invoke-ArtifactCleanup {
    <#
    .SYNOPSIS
        Executes (or dry-runs) a retention plan produced by
        Get-ArtifactRetentionPlan.

    .DESCRIPTION
        In dry-run mode the plan is reported but the deleter is never called.
        The deleter is injectable so tests (and callers targeting a real API)
        control what "delete" actually does; the default just writes a
        verbose message, since this tool operates on mock metadata.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Plan,

        [switch]$DryRun,

        # Invoked once per artifact scheduled for deletion (skipped in dry-run).
        [scriptblock]$Deleter = { param($artifact) Write-Verbose "Deleting artifact '$($artifact.Name)'" }
    )

    $deletedNames = [System.Collections.Generic.List[string]]::new()
    foreach ($artifact in $Plan.Delete) {
        if (-not $DryRun) {
            try {
                # Discard any deleter pipeline output so the function's
                # return value stays a single result object.
                $null = & $Deleter $artifact
            }
            catch {
                throw "Failed to delete artifact '$($artifact.Name)': $($_.Exception.Message)"
            }
        }
        $deletedNames.Add([string]$artifact.Name)
    }

    [pscustomobject]@{
        DryRun       = [bool]$DryRun
        DeletedNames = $deletedNames.ToArray()
        Summary      = $Plan.Summary
    }
}

Export-ModuleMember -Function Get-ArtifactRetentionPlan, Invoke-ArtifactCleanup, Assert-ValidArtifact
