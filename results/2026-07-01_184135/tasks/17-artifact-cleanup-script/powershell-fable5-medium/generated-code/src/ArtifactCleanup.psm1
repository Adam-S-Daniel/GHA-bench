# ArtifactCleanup.psm1
# Core retention-policy engine for CI artifact cleanup.
#
# Approach:
#   Get-ArtifactCleanupPlan is a pure function: mock artifact records in,
#   deterministic deletion plan out. All policies are optional; when a policy
#   parameter is omitted that rule simply doesn't apply.
#
# Policy precedence:
#   1. KeepLatestPerWorkflow marks the newest N artifacts of each workflow run
#      as protected — protected artifacts are never deleted by any rule.
#   2. MaxAgeDays deletes unprotected artifacts older than the cutoff.
#   3. (MaxTotalSizeBytes — added in a later TDD cycle.)

function Get-ArtifactCleanupPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Artifacts,

        [Nullable[int]]$MaxAgeDays,

        [Nullable[int]]$KeepLatestPerWorkflow,

        [Nullable[long]]$MaxTotalSizeBytes,

        [datetime]$ReferenceDate = (Get-Date).ToUniversalTime()
    )

    # Reject nonsensical policy values up front with actionable messages.
    if ($null -ne $MaxAgeDays -and $MaxAgeDays -lt 0) {
        throw "MaxAgeDays must be a non-negative number of days (got $MaxAgeDays)."
    }
    if ($null -ne $KeepLatestPerWorkflow -and $KeepLatestPerWorkflow -lt 0) {
        throw "KeepLatestPerWorkflow must be a non-negative count (got $KeepLatestPerWorkflow)."
    }
    if ($null -ne $MaxTotalSizeBytes -and $MaxTotalSizeBytes -lt 0) {
        throw "MaxTotalSizeBytes must be a non-negative byte count (got $MaxTotalSizeBytes)."
    }

    # Normalize input records into working objects with parsed dates,
    # validating each record so bad fixture data fails loudly and clearly.
    $items = foreach ($artifact in $Artifacts) {
        $name = if ($artifact.PSObject.Properties['Name'] -and $artifact.Name) { [string]$artifact.Name } else { '<unnamed>' }
        foreach ($field in 'Name', 'SizeBytes', 'CreatedAt', 'WorkflowRunId') {
            $prop = $artifact.PSObject.Properties[$field]
            if (-not $prop -or $null -eq $prop.Value -or "$($prop.Value)" -eq '') {
                throw "Artifact '$name' is missing required field '$field'."
            }
        }

        $created = [datetime]::MinValue
        if (-not [datetime]::TryParse($artifact.CreatedAt,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::AdjustToUniversal,
                [ref]$created)) {
            throw "Artifact '$name' has an unparseable CreatedAt value: '$($artifact.CreatedAt)'."
        }

        $size = [long]0
        if (-not [long]::TryParse("$($artifact.SizeBytes)", [ref]$size) -or $size -lt 0) {
            throw "Artifact '$name' has an invalid SizeBytes value: '$($artifact.SizeBytes)'."
        }

        [pscustomobject]@{
            Name          = [string]$artifact.Name
            SizeBytes     = $size
            CreatedAt     = $created
            WorkflowRunId = [string]$artifact.WorkflowRunId
            Protected     = $false
            Reason        = $null
        }
    }
    $items = @($items)

    # Rule 1: protect the newest N artifacts per workflow run.
    if ($null -ne $KeepLatestPerWorkflow) {
        foreach ($group in ($items | Group-Object WorkflowRunId)) {
            $newest = $group.Group | Sort-Object CreatedAt -Descending |
                Select-Object -First $KeepLatestPerWorkflow
            foreach ($item in $newest) { $item.Protected = $true }
        }
    }

    # Rule 2: age-based deletion of unprotected artifacts.
    if ($null -ne $MaxAgeDays) {
        foreach ($item in $items) {
            $ageDays = ($ReferenceDate - $item.CreatedAt).TotalDays
            if (-not $item.Protected -and $ageDays -gt $MaxAgeDays) {
                $item.Reason = 'MaxAge'
            }
        }
    }

    # Rule 3: size budget. Evict oldest unprotected survivors until the total
    # retained size fits. Protected artifacts are kept even if the budget is
    # still exceeded (protection wins over the size rule by design).
    if ($null -ne $MaxTotalSizeBytes) {
        $survivors = @($items | Where-Object { $null -eq $_.Reason })
        $retainedSize = ($survivors | Measure-Object SizeBytes -Sum).Sum
        $evictable = @($survivors | Where-Object { -not $_.Protected } | Sort-Object CreatedAt)
        foreach ($item in $evictable) {
            if ($retainedSize -le $MaxTotalSizeBytes) { break }
            $item.Reason = 'MaxTotalSize'
            $retainedSize -= $item.SizeBytes
        }
    }

    $deleted  = @($items | Where-Object { $null -ne $_.Reason })
    $retained = @($items | Where-Object { $null -eq $_.Reason })

    # Summary gives the caller (and CI logs) the headline numbers.
    $reclaimed    = ($deleted  | Measure-Object SizeBytes -Sum).Sum
    $retainedSize = ($retained | Measure-Object SizeBytes -Sum).Sum

    [pscustomobject]@{
        Retained = $retained
        Deleted  = $deleted
        Summary  = [pscustomobject]@{
            TotalArtifacts      = $items.Count
            RetainedCount       = $retained.Count
            DeletedCount        = $deleted.Count
            SpaceReclaimedBytes = [long]($reclaimed ?? 0)
            RetainedSizeBytes   = [long]($retainedSize ?? 0)
        }
    }
}

function Invoke-ArtifactCleanup {
    <#
    .SYNOPSIS
        Executes (or dry-runs) a deletion plan produced by Get-ArtifactCleanupPlan.
    .DESCRIPTION
        The actual deletion is delegated to the -Deleter scriptblock so the
        engine stays testable: tests inject a mock deleter, production code
        would inject a call to the real artifact API. In -DryRun mode the
        deleter is never invoked; the plan is only reported.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Plan,

        [scriptblock]$Deleter = { param($artifact) Write-Verbose "Deleting $($artifact.Name)" },

        [switch]$DryRun
    )

    if (-not $DryRun) {
        foreach ($artifact in $Plan.Deleted) {
            try {
                & $Deleter $artifact
            }
            catch {
                throw "Failed to delete artifact '$($artifact.Name)': $($_.Exception.Message)"
            }
        }
    }

    [pscustomobject]@{
        DryRun              = [bool]$DryRun
        TotalArtifacts      = $Plan.Summary.TotalArtifacts
        DeletedCount        = $Plan.Summary.DeletedCount
        RetainedCount       = $Plan.Summary.RetainedCount
        SpaceReclaimedBytes = $Plan.Summary.SpaceReclaimedBytes
        RetainedSizeBytes   = $Plan.Summary.RetainedSizeBytes
    }
}

Export-ModuleMember -Function Get-ArtifactCleanupPlan, Invoke-ArtifactCleanup
