<#
    ArtifactCleanup module
    Applies retention policies (max age, max total size, keep-latest-N per
    workflow) to a list of CI artifacts and produces a deletion plan.
#>

function ConvertTo-UtcDateTime {
    <#
        Normalizes a date value to a Kind=Utc [datetime], regardless of
        whether it arrives as a raw ISO 8601 string or as a [datetime]
        already produced by ConvertFrom-Json (which auto-converts ISO 8601
        strings to [datetime] with Kind=Utc, preserving the original
        wall-clock digits). Re-stringifying such a value with a plain
        [string] cast drops the UTC marker and Parse/ToUniversalTime would
        then reinterpret it as local time -- shifting it by the host's UTC
        offset. Handling [datetime] inputs directly avoids that round trip.
    #>
    param(
        [Parameter(Mandatory)]
        $Value
    )

    if ($Value -is [datetime]) {
        switch ($Value.Kind) {
            'Utc' { return $Value }
            'Local' { return $Value.ToUniversalTime() }
            default { return [datetime]::SpecifyKind($Value, [System.DateTimeKind]::Utc) }
        }
    }

    $styles = [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal
    $parsed = [datetime]::MinValue
    $ok = [datetime]::TryParse([string]$Value, [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$parsed)
    if (-not $ok) {
        throw "Value '$Value' could not be parsed as a date."
    }
    return $parsed
}

function ConvertTo-ArtifactObject {
    <#
        Normalizes a raw artifact record (PSCustomObject/hashtable, e.g. from
        JSON) into a typed artifact object, validating required fields so bad
        input fails fast with a meaningful message rather than propagating
        nulls through the retention logic.
    #>
    param(
        [Parameter(Mandatory)]
        $Raw
    )

    if (-not $Raw.name) {
        throw "Artifact is missing required field 'Name'."
    }
    if ($null -eq $Raw.sizeBytes -or $Raw.sizeBytes -lt 0) {
        throw "Artifact '$($Raw.name)' has an invalid 'SizeBytes' value: must be a non-negative number."
    }
    if (-not $Raw.workflowId) {
        throw "Artifact '$($Raw.name)' is missing required field 'WorkflowId'."
    }

    try {
        $createdAt = ConvertTo-UtcDateTime -Value $Raw.createdAt
    } catch {
        throw "Artifact '$($Raw.name)' has an invalid 'CreatedAt' value: '$($Raw.createdAt)' could not be parsed as a date."
    }

    [PSCustomObject]@{
        Name       = [string]$Raw.name
        SizeBytes  = [long]$Raw.sizeBytes
        CreatedAt  = $createdAt
        WorkflowId = [string]$Raw.workflowId
    }
}

function Get-ArtifactCleanupPlan {
    <#
        Pure planning function: given a set of artifacts and retention policy
        limits, decides which artifacts to delete and which to retain. Never
        mutates or deletes anything itself -- Invoke-ArtifactCleanup performs
        the actual (mock) deletion based on this plan, which is what makes
        DryRun mode possible without duplicating the decision logic.

        Precedence rules (highest to lowest):
          1. KeepLatestPerWorkflow protects the N newest artifacts of each
             workflow from every other rule.
          2. MaxAgeDays deletes any unprotected artifact older than the limit.
          3. MaxTotalSizeBytes evicts remaining unprotected artifacts,
             oldest-first, until the survivor set fits under the cap.
    #>
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Artifact,

        [int] $MaxAgeDays = 0,
        [long] $MaxTotalSizeBytes = 0,
        [int] $KeepLatestPerWorkflow = 0,
        [datetime] $ReferenceDate = (Get-Date)
    )

    if ($MaxAgeDays -lt 0) {
        throw "MaxAgeDays must be zero (disabled) or positive, got $MaxAgeDays."
    }
    if ($MaxTotalSizeBytes -lt 0) {
        throw "MaxTotalSizeBytes must be zero (disabled) or positive, got $MaxTotalSizeBytes."
    }
    if ($KeepLatestPerWorkflow -lt 0) {
        throw "KeepLatestPerWorkflow must be zero (disabled) or positive, got $KeepLatestPerWorkflow."
    }

    # Decision record per artifact: Deleted (bool) + Reason (string), carried
    # alongside the original artifact fields so the caller gets full context.
    $decisions = foreach ($item in $Artifact) {
        [PSCustomObject]@{
            Name       = $item.Name
            SizeBytes  = [long]$item.SizeBytes
            CreatedAt  = $item.CreatedAt
            WorkflowId = $item.WorkflowId
            Deleted    = $false
            Protected  = $false
            Reason     = $null
        }
    }

    # Rule 1: keep-latest-N per workflow protects the newest N artifacts of
    # each workflow group from age/size eviction.
    if ($KeepLatestPerWorkflow -gt 0) {
        $groups = $decisions | Group-Object -Property WorkflowId
        foreach ($group in $groups) {
            $newest = $group.Group | Sort-Object -Property CreatedAt -Descending | Select-Object -First $KeepLatestPerWorkflow
            foreach ($item in $newest) {
                $item.Protected = $true
                $item.Reason = 'kept-latest-N'
            }
        }
    }

    # Rule 2: max age deletes unprotected artifacts older than the limit.
    if ($MaxAgeDays -gt 0) {
        foreach ($item in $decisions) {
            if ($item.Protected -or $item.Deleted) { continue }
            $ageDays = ($ReferenceDate - $item.CreatedAt).TotalDays
            if ($ageDays -gt $MaxAgeDays) {
                $item.Deleted = $true
                $item.Reason = 'max-age-exceeded'
            }
        }
    }

    # Rule 3: max total size evicts remaining unprotected artifacts,
    # oldest-first, until the survivor set fits under the cap.
    if ($MaxTotalSizeBytes -gt 0) {
        $survivors = $decisions | Where-Object { -not $_.Deleted }
        $totalSize = ($survivors | Measure-Object -Property SizeBytes -Sum).Sum
        if (-not $totalSize) { $totalSize = 0 }

        if ($totalSize -gt $MaxTotalSizeBytes) {
            $evictionCandidates = $survivors | Where-Object { -not $_.Protected } | Sort-Object -Property CreatedAt
            foreach ($item in $evictionCandidates) {
                if ($totalSize -le $MaxTotalSizeBytes) { break }
                $item.Deleted = $true
                $item.Reason = 'max-total-size-exceeded'
                $totalSize -= $item.SizeBytes
            }
        }
    }

    foreach ($item in $decisions) {
        if (-not $item.Deleted -and -not $item.Reason) {
            $item.Reason = 'within-policy'
        }
    }

    $toDelete = @($decisions | Where-Object Deleted)
    $toRetain = @($decisions | Where-Object { -not $_.Deleted })
    $bytesReclaimed = ($toDelete | Measure-Object -Property SizeBytes -Sum).Sum
    if (-not $bytesReclaimed) { $bytesReclaimed = 0 }
    $retainedBytes = ($toRetain | Measure-Object -Property SizeBytes -Sum).Sum
    if (-not $retainedBytes) { $retainedBytes = 0 }

    [PSCustomObject]@{
        ToDelete = $toDelete
        ToRetain = $toRetain
        Summary  = [PSCustomObject]@{
            TotalArtifacts = $decisions.Count
            DeletedCount   = $toDelete.Count
            RetainedCount  = $toRetain.Count
            BytesReclaimed = [long]$bytesReclaimed
            RetainedBytes  = [long]$retainedBytes
        }
    }
}

function Remove-Artifact {
    <#
        Performs the actual (mock) deletion of a single artifact. In a real
        pipeline this would call the GitHub Artifacts REST API
        (DELETE /repos/{owner}/{repo}/actions/artifacts/{artifact_id}); here
        it is a seam that Pester can -Mock to verify Invoke-ArtifactCleanup
        calls it the right number of times without hitting a network.
    #>
    param(
        [Parameter(Mandatory)]
        $Artifact
    )

    [PSCustomObject]@{
        Name      = $Artifact.Name
        Deleted   = $true
        Timestamp = (Get-Date).ToString('o')
    }
}

function Invoke-ArtifactCleanup {
    <#
        Orchestrates a cleanup run: computes the retention plan via
        Get-ArtifactCleanupPlan, then executes it by calling Remove-Artifact
        for every artifact marked for deletion -- unless -DryRun is set, in
        which case the plan is still computed and returned (so callers can
        see exactly what *would* happen) but no removal calls are made.
    #>
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Artifact,

        [int] $MaxAgeDays = 0,
        [long] $MaxTotalSizeBytes = 0,
        [int] $KeepLatestPerWorkflow = 0,
        [datetime] $ReferenceDate = (Get-Date),
        [switch] $DryRun
    )

    $plan = Get-ArtifactCleanupPlan -Artifact $Artifact -MaxAgeDays $MaxAgeDays `
        -MaxTotalSizeBytes $MaxTotalSizeBytes -KeepLatestPerWorkflow $KeepLatestPerWorkflow `
        -ReferenceDate $ReferenceDate

    $removed = 0
    if (-not $DryRun) {
        foreach ($item in $plan.ToDelete) {
            $null = Remove-Artifact -Artifact $item
            $removed++
        }
    }

    [PSCustomObject]@{
        Plan                     = $plan
        DryRun                   = [bool]$DryRun
        ArtifactsActuallyRemoved = $removed
    }
}

Export-ModuleMember -Function ConvertTo-UtcDateTime, ConvertTo-ArtifactObject, Get-ArtifactCleanupPlan, Remove-Artifact, Invoke-ArtifactCleanup
