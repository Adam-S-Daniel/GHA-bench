# ArtifactCleanup.psm1
#
# Core library for applying artifact retention policies and producing a
# deletion plan. Pure functions only -- no real I/O against any artifact
# store -- so the logic is fully unit-testable with mock data.

Set-StrictMode -Version Latest

function New-ArtifactRecord {
    <#
    .SYNOPSIS
        Normalises raw artifact metadata into a single record object.
    .DESCRIPTION
        Every artifact carries the four pieces of metadata the task defines:
        Name, SizeBytes, Created (creation date) and WorkflowRunId. This factory
        coerces inputs to predictable types so the rest of the pipeline can rely
        on them.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][long]$SizeBytes,
        [Parameter(Mandatory)][datetime]$Created,
        [Parameter(Mandatory)][string]$WorkflowRunId
    )

    [PSCustomObject]@{
        Name          = $Name
        SizeBytes     = $SizeBytes
        Created       = $Created
        WorkflowRunId = $WorkflowRunId
    }
}

function Get-ArtifactSizeSum {
    # Null-safe total of SizeBytes over a (possibly empty) set of items.
    # Avoids Measure-Object, whose .Sum is absent for an empty pipeline under
    # Set-StrictMode.
    [CmdletBinding()]
    param([AllowEmptyCollection()][object[]]$Items)

    $sum = 0L
    foreach ($i in $Items) { $sum += [long]$i.SizeBytes }
    return $sum
}

function Format-FileSize {
    <#
    .SYNOPSIS
        Formats a byte count as a human-readable size using binary (1024) units.
    .EXAMPLE
        Format-FileSize -Bytes 1536   # -> '1.5 KB'
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][long]$Bytes)

    $units = 'B', 'KB', 'MB', 'GB', 'TB', 'PB'
    $value = [double]$Bytes
    $unit  = 0
    while ($value -ge 1024 -and $unit -lt ($units.Count - 1)) {
        $value /= 1024
        $unit++
    }

    # Round to 2 decimals and drop trailing zeros so 1.0 -> '1', 1.50 -> '1.5'.
    $rounded = [math]::Round($value, 2)
    $number  = $rounded.ToString('0.##', [System.Globalization.CultureInfo]::InvariantCulture)
    "$number $($units[$unit])"
}

function Get-ArtifactCleanupPlan {
    <#
    .SYNOPSIS
        Applies retention policies to a set of artifacts and returns a plan.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Artifacts,

        # Delete artifacts strictly older than this many days. 0 = disabled.
        [int]$MaxAgeDays = 0,

        # Keep only the N most recent runs per workflow (grouped by artifact Name).
        # 0 = disabled.
        [int]$KeepLatestPerWorkflow = 0,

        # Cap the total size of retained artifacts. Oldest survivors are evicted
        # first until the retained total fits. 0 = disabled.
        [long]$MaxTotalSizeBytes = 0,

        # Reference "now" for age calculations; injectable for deterministic tests.
        [datetime]$Now = (Get-Date)
    )

    # Annotate a *copy* of each artifact with a mutable Reasons list. We never
    # mutate the caller's input objects.
    $items = foreach ($a in $Artifacts) {
        [PSCustomObject]@{
            Name          = $a.Name
            SizeBytes     = [long]$a.SizeBytes
            Created       = [datetime]$a.Created
            WorkflowRunId = [string]$a.WorkflowRunId
            Reasons       = [System.Collections.Generic.List[string]]::new()
        }
    }
    $items = @($items)

    # --- Policy 1: maximum age -------------------------------------------------
    # An artifact violates this policy when its age exceeds MaxAgeDays. The
    # boundary (age == MaxAgeDays exactly) is retained.
    if ($MaxAgeDays -gt 0) {
        foreach ($item in $items) {
            $ageDays = ($Now - $item.Created).TotalDays
            if ($ageDays -gt $MaxAgeDays) {
                $item.Reasons.Add("Exceeds max age ($MaxAgeDays days)")
            }
        }
    }

    # --- Policy 2: keep latest N per workflow ----------------------------------
    # Group by Name (one workflow's artifact stream). Within each group order
    # newest-first -- by creation date, breaking ties on the numeric run id so a
    # higher (later) run id counts as newer. Everything past the Nth is surplus.
    if ($KeepLatestPerWorkflow -gt 0) {
        $groups = $items | Group-Object -Property Name
        foreach ($group in $groups) {
            $ordered = @($group.Group | Sort-Object `
                @{ Expression = { $_.Created }; Descending = $true }, `
                @{ Expression = {
                        $n = 0L
                        [void][long]::TryParse([string]$_.WorkflowRunId, [ref]$n)
                        $n
                    }; Descending = $true })

            if ($ordered.Count -gt $KeepLatestPerWorkflow) {
                foreach ($surplus in $ordered[$KeepLatestPerWorkflow..($ordered.Count - 1)]) {
                    $surplus.Reasons.Add("Exceeds keep-latest-N per workflow (keep $KeepLatestPerWorkflow)")
                }
            }
        }
    }

    # --- Policy 3: max total size ----------------------------------------------
    # Run last, over only the artifacts still surviving the previous policies, so
    # we never count or evict something already slated for deletion. If the
    # survivors still exceed the budget, evict oldest-first (Created ascending,
    # tie-break on the lower/older run id) until the retained total fits.
    if ($MaxTotalSizeBytes -gt 0) {
        $survivors = @($items | Where-Object { $_.Reasons.Count -eq 0 })
        $survivorBytes = Get-ArtifactSizeSum -Items $survivors

        if ($survivorBytes -gt $MaxTotalSizeBytes) {
            $oldestFirst = @($survivors | Sort-Object `
                @{ Expression = { $_.Created }; Descending = $false }, `
                @{ Expression = {
                        $n = 0L
                        [void][long]::TryParse([string]$_.WorkflowRunId, [ref]$n)
                        $n
                    }; Descending = $false })

            foreach ($victim in $oldestFirst) {
                if ($survivorBytes -le $MaxTotalSizeBytes) { break }
                $victim.Reasons.Add("Exceeds max total size ($MaxTotalSizeBytes bytes)")
                $survivorBytes -= $victim.SizeBytes
            }
        }
    }

    # An artifact is deleted if it accrued one or more policy violations.
    $deletedItems  = @($items | Where-Object { $_.Reasons.Count -gt 0 })
    $retainedItems = @($items | Where-Object { $_.Reasons.Count -eq 0 })

    # Shape the public records (Reasons as a plain array for deleted artifacts).
    $deleted = foreach ($d in $deletedItems) {
        [PSCustomObject]@{
            Name          = $d.Name
            SizeBytes     = $d.SizeBytes
            Created       = $d.Created
            WorkflowRunId = $d.WorkflowRunId
            Reasons       = @($d.Reasons)
        }
    }
    $retained = foreach ($r in $retainedItems) {
        [PSCustomObject]@{
            Name          = $r.Name
            SizeBytes     = $r.SizeBytes
            Created       = $r.Created
            WorkflowRunId = $r.WorkflowRunId
        }
    }
    $deleted  = @($deleted)
    $retained = @($retained)

    $totalBytes    = Get-ArtifactSizeSum -Items $items
    $retainedBytes = Get-ArtifactSizeSum -Items $retainedItems

    $reclaimedBytes = [long]($totalBytes - $retainedBytes)

    [PSCustomObject]@{
        Retained = $retained
        Deleted  = $deleted
        # Echo the policy thresholds that produced this plan, for the report.
        Policies = [PSCustomObject]@{
            MaxAgeDays            = $MaxAgeDays
            KeepLatestPerWorkflow = $KeepLatestPerWorkflow
            MaxTotalSizeBytes     = $MaxTotalSizeBytes
        }
        Summary  = [PSCustomObject]@{
            TotalArtifacts    = $items.Count
            RetainedCount     = $retained.Count
            DeletedCount      = $deleted.Count
            TotalSizeBytes    = $totalBytes
            RetainedSizeBytes = $retainedBytes
            ReclaimedBytes    = $reclaimedBytes
            TotalSizeHuman    = Format-FileSize -Bytes $totalBytes
            RetainedSizeHuman = Format-FileSize -Bytes $retainedBytes
            ReclaimedHuman    = Format-FileSize -Bytes $reclaimedBytes
        }
    }
}

function Format-ArtifactCleanupPlan {
    <#
    .SYNOPSIS
        Renders a cleanup plan as human-readable report lines.
    .OUTPUTS
        [string[]] one line per row of the report.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Plan,
        [switch]$DryRun
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    $add = { param($t) $lines.Add([string]$t) }

    & $add '============================================================'
    if ($DryRun) {
        & $add ' ARTIFACT CLEANUP PLAN  [DRY RUN - no artifacts deleted]'
    } else {
        & $add ' ARTIFACT CLEANUP PLAN'
    }
    & $add '============================================================'

    # Policies in effect (a dash means the policy is disabled).
    $p = $Plan.Policies
    & $add 'Policies:'
    & $add ("  Max age (days)............ {0}" -f $(if ($p.MaxAgeDays -gt 0) { $p.MaxAgeDays } else { '-' }))
    & $add ("  Keep latest N / workflow.. {0}" -f $(if ($p.KeepLatestPerWorkflow -gt 0) { $p.KeepLatestPerWorkflow } else { '-' }))
    & $add ("  Max total size............ {0}" -f $(if ($p.MaxTotalSizeBytes -gt 0) { Format-FileSize -Bytes $p.MaxTotalSizeBytes } else { '-' }))
    & $add ''

    # Deletion detail.
    & $add ("Artifacts to DELETE ({0}):" -f $Plan.Summary.DeletedCount)
    if ($Plan.Summary.DeletedCount -eq 0) {
        & $add '  (none)'
    } else {
        foreach ($d in $Plan.Deleted) {
            $verb = if ($DryRun) { 'WOULD DELETE' } else { 'DELETE' }
            & $add ("  [{0}] {1} (run {2}, {3}, created {4:yyyy-MM-dd})" -f `
                $verb, $d.Name, $d.WorkflowRunId, (Format-FileSize -Bytes $d.SizeBytes), $d.Created)
            & $add ("      reason(s): {0}" -f ($d.Reasons -join '; '))
        }
    }
    & $add ''

    # Summary block.
    & $add 'Summary:'
    & $add ("  Artifacts:       {0} total" -f $Plan.Summary.TotalArtifacts)
    & $add ("  To retain:       {0} ({1})" -f $Plan.Summary.RetainedCount, $Plan.Summary.RetainedSizeHuman)
    & $add ("  To delete:       {0}" -f $Plan.Summary.DeletedCount)
    & $add ("  Space reclaimed: {0} ({1} bytes)" -f $Plan.Summary.ReclaimedHuman, $Plan.Summary.ReclaimedBytes)
    & $add '============================================================'

    return $lines.ToArray()
}

function Import-ArtifactFixture {
    <#
    .SYNOPSIS
        Loads artifacts + optional policy/reference-date defaults from a JSON file.
    .DESCRIPTION
        Accepts either a bare JSON array of artifacts, or an object of the shape
        { referenceDate, policies:{...}, artifacts:[...] }. Errors are surfaced
        with actionable messages.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Artifact fixture not found: '$Path'"
    }

    $raw = Get-Content -LiteralPath $Path -Raw
    try {
        $data = $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Failed to parse JSON fixture '$Path': $($_.Exception.Message)"
    }

    # Normalise to { referenceDate, policies, artifacts }. Guard every property
    # access -- under Set-StrictMode reading an absent property throws.
    $hasProp = { param($obj, $name) $obj -and $obj.PSObject.Properties[$name] }
    if ($data -is [System.Array]) {
        $rawArtifacts = $data
        $referenceDate = $null
        $policies = $null
    } else {
        $rawArtifacts  = if (& $hasProp $data 'artifacts')     { $data.artifacts }     else { $null }
        $referenceDate = if (& $hasProp $data 'referenceDate') { $data.referenceDate } else { $null }
        $policies      = if (& $hasProp $data 'policies')      { $data.policies }      else { $null }
    }

    if ($null -eq $rawArtifacts) {
        throw "Fixture '$Path' contains no 'artifacts' array."
    }

    $required = 'name', 'sizeBytes', 'created', 'workflowRunId'
    $artifacts = foreach ($a in @($rawArtifacts)) {
        foreach ($field in $required) {
            if ($null -eq $a.PSObject.Properties[$field] -or $null -eq $a.$field) {
                throw "Artifact entry is missing required field '$field' in fixture '$Path'."
            }
        }
        New-ArtifactRecord -Name $a.name -SizeBytes ([long]$a.sizeBytes) `
            -Created ([datetime]$a.created) -WorkflowRunId ([string]$a.workflowRunId)
    }

    [PSCustomObject]@{
        Artifacts     = @($artifacts)
        ReferenceDate = $referenceDate
        Policies      = $policies
    }
}

function Get-ArtifactCleanupMetricLines {
    <#
    .SYNOPSIS
        Emits stable KEY=VALUE lines from a plan for machine parsing (CI, act).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Plan,
        [bool]$DryRun = $false
    )

    @(
        "ARTIFACTS_TOTAL=$($Plan.Summary.TotalArtifacts)"
        "ARTIFACTS_RETAINED=$($Plan.Summary.RetainedCount)"
        "ARTIFACTS_DELETED=$($Plan.Summary.DeletedCount)"
        "TOTAL_SIZE_BYTES=$($Plan.Summary.TotalSizeBytes)"
        "RETAINED_SIZE_BYTES=$($Plan.Summary.RetainedSizeBytes)"
        "SPACE_RECLAIMED_BYTES=$($Plan.Summary.ReclaimedBytes)"
        "SPACE_RECLAIMED_HUMAN=$($Plan.Summary.ReclaimedHuman)"
        "DRY_RUN=$(if ($DryRun) { 'true' } else { 'false' })"
    )
}

function Invoke-ArtifactCleanup {
    <#
    .SYNOPSIS
        End-to-end driver: load artifacts, build a deletion plan, optionally
        perform deletions, and return the plan plus rendered report/metrics.
    .DESCRIPTION
        With -DryRun, no deletions are performed (the DeleteAction is never
        invoked). Without it, DeleteAction is invoked once per deleted artifact.
        DeleteAction defaults to a no-op because the task works on mock data with
        no real artifact store to call.
    .PARAMETER Path
        JSON fixture path. Mutually informative with -Artifacts.
    .PARAMETER Artifacts
        Pre-built artifact records (bypasses file loading; handy for tests).
    #>
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Path')][string]$Path,
        [Parameter(Mandatory, ParameterSetName = 'Artifacts')][AllowEmptyCollection()][object[]]$Artifacts,

        [int]$MaxAgeDays = 0,
        [int]$KeepLatestPerWorkflow = 0,
        [long]$MaxTotalSizeBytes = 0,
        [datetime]$Now = (Get-Date),
        [switch]$DryRun,

        # Called as DeleteAction.Invoke($artifact) for each deletion (non-dry-run).
        [scriptblock]$DeleteAction = { param($artifact) }
    )

    # Resolve the artifact set and merge any fixture-provided defaults. Explicit
    # parameters always win over fixture values.
    $explicit = $PSBoundParameters
    if ($PSCmdlet.ParameterSetName -eq 'Path') {
        $loaded = Import-ArtifactFixture -Path $Path
        $Artifacts = $loaded.Artifacts

        if (-not $explicit.ContainsKey('Now') -and $loaded.ReferenceDate) {
            $Now = [datetime]$loaded.ReferenceDate
        }
        if ($loaded.Policies) {
            if (-not $explicit.ContainsKey('MaxAgeDays') -and $loaded.Policies.PSObject.Properties['maxAgeDays']) {
                $MaxAgeDays = [int]$loaded.Policies.maxAgeDays
            }
            if (-not $explicit.ContainsKey('KeepLatestPerWorkflow') -and $loaded.Policies.PSObject.Properties['keepLatestPerWorkflow']) {
                $KeepLatestPerWorkflow = [int]$loaded.Policies.keepLatestPerWorkflow
            }
            if (-not $explicit.ContainsKey('MaxTotalSizeBytes') -and $loaded.Policies.PSObject.Properties['maxTotalSizeBytes']) {
                $MaxTotalSizeBytes = [long]$loaded.Policies.maxTotalSizeBytes
            }
        }
    }

    $plan = Get-ArtifactCleanupPlan -Artifacts @($Artifacts) `
        -MaxAgeDays $MaxAgeDays `
        -KeepLatestPerWorkflow $KeepLatestPerWorkflow `
        -MaxTotalSizeBytes $MaxTotalSizeBytes `
        -Now $Now

    # Perform (or simulate) deletions. Dry-run never touches the delete action.
    $performed = 0
    if (-not $DryRun) {
        foreach ($artifact in $plan.Deleted) {
            try {
                & $DeleteAction $artifact
                $performed++
            } catch {
                Write-Error "Failed to delete artifact '$($artifact.Name)' (run $($artifact.WorkflowRunId)): $($_.Exception.Message)"
            }
        }
    }

    [PSCustomObject]@{
        Plan             = $plan
        DryRun           = [bool]$DryRun
        DeletedPerformed = $performed
        ReportLines      = Format-ArtifactCleanupPlan -Plan $plan -DryRun:$DryRun
        MetricLines      = Get-ArtifactCleanupMetricLines -Plan $plan -DryRun:([bool]$DryRun)
    }
}

Export-ModuleMember -Function New-ArtifactRecord, Get-ArtifactCleanupPlan, Format-FileSize,
    Format-ArtifactCleanupPlan, Import-ArtifactFixture, Get-ArtifactCleanupMetricLines, Invoke-ArtifactCleanup
