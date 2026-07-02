<#
    ArtifactCleanup.psm1

    Core retention-policy engine for cleaning up CI/CD build artifacts.

    Three independent retention policies can be applied to a list of artifacts:
      - MaxAgeDays        : delete artifacts older than N days
      - MaxTotalSizeBytes : delete the oldest artifacts first until the total
                            size of the survivors is at or below the budget
      - KeepLatestN       : per WorkflowName, delete anything beyond the N
                            most recently created artifacts

    Each policy is evaluated independently against the full artifact set and
    the final deletion set is the UNION of every policy's matches (an
    artifact flagged by more than one policy simply carries multiple
    comma-separated reasons). This keeps each policy simple to reason about
    and test in isolation, and matches how most real-world artifact cleanup
    tools compose these rules (each rule is its own trigger, not a cascading
    pipeline).
#>

Set-StrictMode -Version Latest

function Assert-ValidArtifact {
    <#
        Validates that a single artifact object carries the fields the
        policy engine depends on, throwing a descriptive error identifying
        both the offending artifact and the missing field.
    #>
    param(
        [Parameter(Mandatory)]
        [object] $Artifact,

        [Parameter(Mandatory)]
        [int] $Index
    )

    $label = if ($Artifact.PSObject.Properties.Name -contains 'Name' -and $Artifact.Name) {
        $Artifact.Name
    }
    else {
        "at index $Index"
    }

    foreach ($field in @('Name', 'SizeBytes', 'CreatedAt', 'WorkflowName')) {
        $prop = $Artifact.PSObject.Properties[$field]
        if (-not $prop -or $null -eq $prop.Value -or $prop.Value -eq '') {
            throw "Artifact '$label' is missing required field '$field'."
        }
    }

    if (-not ($Artifact.SizeBytes -is [int] -or $Artifact.SizeBytes -is [long] -or $Artifact.SizeBytes -is [double])) {
        throw "Artifact '$label' has a non-numeric SizeBytes value: '$($Artifact.SizeBytes)'."
    }

    if ([long]$Artifact.SizeBytes -lt 0) {
        throw "Artifact '$label' has a negative SizeBytes value: '$($Artifact.SizeBytes)'."
    }
}

function Get-ArtifactCleanupPlan {
    <#
        .SYNOPSIS
        Applies retention policies to a list of artifacts and returns a
        deletion plan.

        .DESCRIPTION
        Returns a PSCustomObject with three properties:
          Retained - artifacts that survive every policy
          Deleted  - artifacts flagged for deletion, each annotated with a
                     .DeletionReason property (comma-separated policy names)
          Summary  - counts and byte totals for the plan

        .PARAMETER Artifacts
        The full artifact inventory. Each artifact must expose Name,
        SizeBytes, CreatedAt (parseable date/string), and WorkflowName.

        .PARAMETER MaxAgeDays
        Delete artifacts whose age (relative to -Now) exceeds this many days.
        Omit or pass $null to disable this policy.

        .PARAMETER MaxTotalSizeBytes
        Delete the oldest artifacts first until total size is at or below
        this budget. Omit or pass $null to disable this policy.

        .PARAMETER KeepLatestN
        Per WorkflowName group, delete every artifact beyond the N most
        recently created. Omit or pass $null to disable this policy.

        .PARAMETER DryRun
        Marks the plan's Summary.IsDryRun flag. Does not change which
        artifacts are selected -- the plan always reports what WOULD happen;
        callers decide whether to actually act on it.

        .PARAMETER Now
        The reference "current time" used for age calculations. Defaults to
        the real current time; tests pass a fixed value for determinism.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Artifacts,

        [Nullable[int]] $MaxAgeDays = $null,

        [Nullable[long]] $MaxTotalSizeBytes = $null,

        [Nullable[int]] $KeepLatestN = $null,

        [switch] $DryRun,

        [datetime] $Now = (Get-Date).ToUniversalTime()
    )

    if ($null -ne $MaxAgeDays -and $MaxAgeDays -lt 0) {
        throw "MaxAgeDays must be zero or greater; got '$MaxAgeDays'."
    }
    if ($null -ne $MaxTotalSizeBytes -and $MaxTotalSizeBytes -lt 0) {
        throw "MaxTotalSizeBytes must be zero or greater; got '$MaxTotalSizeBytes'."
    }
    if ($null -ne $KeepLatestN -and $KeepLatestN -lt 0) {
        throw "KeepLatestN must be zero or greater; got '$KeepLatestN'."
    }

    # Normalize each artifact: validate required fields and attach a parsed
    # CreatedAtUtc [datetime] for reliable comparisons/sorting.
    $normalized = @()
    for ($i = 0; $i -lt $Artifacts.Count; $i++) {
        $artifact = $Artifacts[$i]
        Assert-ValidArtifact -Artifact $artifact -Index $i

        $createdAtUtc = [datetime]::Parse($artifact.CreatedAt, [System.Globalization.CultureInfo]::InvariantCulture).ToUniversalTime()

        $normalized += [pscustomobject]@{
            Name            = $artifact.Name
            SizeBytes       = [long]$artifact.SizeBytes
            CreatedAt       = $artifact.CreatedAt
            CreatedAtUtc    = $createdAtUtc
            WorkflowName    = $artifact.WorkflowName
            WorkflowRunId   = $artifact.PSObject.Properties['WorkflowRunId'] ? $artifact.WorkflowRunId : $null
            DeletionReasons = [System.Collections.Generic.List[string]]::new()
        }
    }

    # --- Policy 1: MaxAgeDays -------------------------------------------------
    if ($null -ne $MaxAgeDays) {
        foreach ($artifact in $normalized) {
            $ageDays = ($Now - $artifact.CreatedAtUtc).TotalDays
            if ($ageDays -gt $MaxAgeDays) {
                $artifact.DeletionReasons.Add('MaxAge')
            }
        }
    }

    # --- Policy 2: MaxTotalSizeBytes ------------------------------------------
    # Delete the oldest artifacts first (across the whole set, regardless of
    # workflow) until the running total is at or below the budget.
    if ($null -ne $MaxTotalSizeBytes) {
        $totalSize = 0
        if ($normalized.Count -gt 0) {
            $totalSize = ($normalized | Measure-Object -Property SizeBytes -Sum).Sum
        }

        if ($totalSize -gt $MaxTotalSizeBytes) {
            $oldestFirst = $normalized | Sort-Object -Property CreatedAtUtc
            $running = $totalSize
            foreach ($artifact in $oldestFirst) {
                if ($running -le $MaxTotalSizeBytes) { break }
                $artifact.DeletionReasons.Add('MaxTotalSize')
                $running -= $artifact.SizeBytes
            }
        }
    }

    # --- Policy 3: KeepLatestN (per workflow) ---------------------------------
    if ($null -ne $KeepLatestN) {
        $groups = $normalized | Group-Object -Property WorkflowName
        foreach ($group in $groups) {
            $newestFirst = $group.Group | Sort-Object -Property CreatedAtUtc -Descending
            $excess = $newestFirst | Select-Object -Skip $KeepLatestN
            foreach ($artifact in $excess) {
                $artifact.DeletionReasons.Add('KeepLatestN')
            }
        }
    }

    $deleted = @($normalized | Where-Object { $_.DeletionReasons.Count -gt 0 })
    $retained = @($normalized | Where-Object { $_.DeletionReasons.Count -eq 0 })

    foreach ($artifact in $deleted) {
        $artifact | Add-Member -NotePropertyName DeletionReason -NotePropertyValue ($artifact.DeletionReasons -join ',') -Force
    }

    $totalSizeBytes = [long]0
    if ($normalized.Count -gt 0) {
        $totalSizeBytes = [long]($normalized | Measure-Object -Property SizeBytes -Sum).Sum
    }
    $reclaimedBytes = [long]0
    if ($deleted.Count -gt 0) {
        $reclaimedBytes = [long]($deleted | Measure-Object -Property SizeBytes -Sum).Sum
    }

    [pscustomobject]@{
        Retained = $retained
        Deleted  = $deleted
        Summary  = [pscustomobject]@{
            RetainedCount  = $retained.Count
            DeletedCount   = $deleted.Count
            TotalSizeBytes = $totalSizeBytes
            ReclaimedBytes = $reclaimedBytes
            IsDryRun       = [bool]$DryRun
        }
    }
}

function Format-ArtifactCleanupSummary {
    <#
        .SYNOPSIS
        Formats a cleanup plan as both a human-readable block and a single
        machine-parseable "SCENARIO=... RETAINED=... DELETED=..." line so CI
        logs and test harnesses can assert on exact values.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Plan,

        [Parameter(Mandatory)]
        [string] $ScenarioName
    )

    $summary = $Plan.Summary
    "SCENARIO=$ScenarioName DRYRUN=$($summary.IsDryRun) RETAINED=$($summary.RetainedCount) DELETED=$($summary.DeletedCount) RECLAIMED_BYTES=$($summary.ReclaimedBytes) TOTAL_BYTES=$($summary.TotalSizeBytes)"
}

Export-ModuleMember -Function Get-ArtifactCleanupPlan, Format-ArtifactCleanupSummary
