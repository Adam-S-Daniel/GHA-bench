#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Artifact retention / cleanup planner.

.DESCRIPTION
    Given a list of artifacts (name, size, creation date, workflow run id) this
    script applies a set of retention policies and produces a *deletion plan*:
    which artifacts to delete, why, and a summary (space reclaimed, retained vs
    deleted counts/sizes). It supports a dry-run mode.

    Retention policies (any policy with a 0 / unset value is disabled):

      * MaxAgeDays        - delete artifacts older than N days relative to the
                            reference date ("now").
      * KeepLatestN       - within each group (default grouping is by artifact
                            Name) keep only the N newest artifacts; delete the
                            rest.
      * MaxTotalSizeBytes - after the above rules, if the total size of the
                            still-retained artifacts exceeds this cap, delete the
                            oldest retained artifacts until the cap is met.

    The script is designed to be *dot-sourced* by the Pester test-suite (the
    functions are then available without side-effects) and also to run as a
    stand-alone CLI when invoked with -InputPath.

.EXAMPLE
    ./ArtifactCleanup.ps1 -InputPath fixtures/max-age.json
.EXAMPLE
    ./ArtifactCleanup.ps1 -InputPath fixtures/combined.json -DryRun -Format Json
#>
[CmdletBinding()]
param(
    # Path to a JSON config describing artifacts + policy. When omitted the
    # script defines its functions and exits (no "main" execution) so the test
    # suite can dot-source it safely.
    [string] $InputPath,

    # Policy overrides (used when not supplied by the JSON config).
    [int]    $MaxAgeDays,
    [long]   $MaxTotalSizeBytes,
    [int]    $KeepLatestN,
    [string] $GroupBy = 'Name',

    # Reference "now". When empty the current date is used.
    [string] $ReferenceDate,

    # When set, the plan is produced but flagged as a dry run (nothing is
    # "executed"). With mock data the only difference is the DryRun flag and the
    # report wording, which mirrors how a real deletion step would branch.
    [switch] $DryRun,

    # Output format for the CLI report.
    [ValidateSet('Text', 'Json')]
    [string] $Format = 'Text',

    # Optional path to also write the report to.
    [string] $OutputPath
)

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# Core logic
# ---------------------------------------------------------------------------

function ConvertTo-Artifact {
    <#
        Normalise a loosely-typed object (e.g. parsed JSON) into a strongly
        shaped artifact record. Throws a meaningful error on malformed input.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object] $InputObject
    )
    process {
        foreach ($prop in 'Name', 'Size', 'Created') {
            if (-not ($InputObject.PSObject.Properties.Name -contains $prop)) {
                throw "Artifact is missing required property '$prop'."
            }
        }

        [datetime] $created = [datetime]::MinValue
        if (-not [datetime]::TryParse([string]$InputObject.Created, [ref]$created)) {
            throw "Artifact '$($InputObject.Name)' has an unparseable Created date: '$($InputObject.Created)'."
        }

        [long] $size = 0
        if (-not [long]::TryParse([string]$InputObject.Size, [ref]$size)) {
            throw "Artifact '$($InputObject.Name)' has a non-numeric Size: '$($InputObject.Size)'."
        }
        if ($size -lt 0) {
            throw "Artifact '$($InputObject.Name)' has a negative Size: $size."
        }

        $runId = $null
        if ($InputObject.PSObject.Properties.Name -contains 'WorkflowRunId') {
            $runId = $InputObject.WorkflowRunId
        }

        [pscustomobject]@{
            Name          = [string]$InputObject.Name
            Size          = $size
            Created       = $created
            WorkflowRunId = $runId
        }
    }
}

function Get-SizeSum {
    # Sum the .Size of a collection, returning 0L for empty/null input.
    # (Measure-Object -Property emits no object on empty input, so we avoid it.)
    param([object[]] $Items)
    [long] $sum = 0
    foreach ($i in $Items) { $sum += [long]$i.Size }
    return $sum
}

function Get-ArtifactCleanupPlan {
    <#
    .SYNOPSIS
        Apply retention policies and return a deletion plan object.

    .OUTPUTS
        A PSCustomObject with:
          Delete   - artifacts marked for deletion (each annotated with Reasons)
          Retain   - artifacts kept
          Summary  - aggregate counts / sizes
          DryRun   - whether this is a dry run
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Artifacts,

        [int]      $MaxAgeDays = 0,
        [long]     $MaxTotalSizeBytes = 0,
        [int]      $KeepLatestN = 0,
        [string]   $GroupBy = 'Name',
        [datetime] $ReferenceDate = (Get-Date),
        [switch]   $DryRun
    )

    if ($MaxAgeDays -lt 0)        { throw "MaxAgeDays must be >= 0 (got $MaxAgeDays)." }
    if ($MaxTotalSizeBytes -lt 0) { throw "MaxTotalSizeBytes must be >= 0 (got $MaxTotalSizeBytes)." }
    if ($KeepLatestN -lt 0)       { throw "KeepLatestN must be >= 0 (got $KeepLatestN)." }

    # Work on normalised copies so the policy stages can attach reasons without
    # mutating the caller's objects. A hashtable keyed by a synthetic id tracks
    # the deletion reasons accumulated across stages.
    $items = @()
    $idx = 0
    foreach ($a in $Artifacts) {
        $items += [pscustomobject]@{
            Id            = $idx
            Name          = $a.Name
            Size          = [long]$a.Size
            Created       = [datetime]$a.Created
            WorkflowRunId = ($a.PSObject.Properties.Name -contains 'WorkflowRunId') ? $a.WorkflowRunId : $null
            Reasons       = [System.Collections.Generic.List[string]]::new()
        }
        $idx++
    }

    # Stage 1: max age -----------------------------------------------------
    if ($MaxAgeDays -gt 0) {
        $cutoff = $ReferenceDate.AddDays(-$MaxAgeDays)
        foreach ($it in $items) {
            if ($it.Created -lt $cutoff) {
                $it.Reasons.Add('MaxAge')
            }
        }
    }

    # Stage 2: keep-latest-N per group ------------------------------------
    if ($KeepLatestN -gt 0) {
        $groups = $items | Group-Object -Property $GroupBy
        foreach ($g in $groups) {
            # Newest first; everything past the first N is surplus.
            $ordered = $g.Group | Sort-Object -Property Created -Descending
            for ($i = $KeepLatestN; $i -lt $ordered.Count; $i++) {
                if ($ordered[$i].Reasons -notcontains 'KeepLatestN') {
                    $ordered[$i].Reasons.Add('KeepLatestN')
                }
            }
        }
    }

    # Stage 3: max total size --------------------------------------------
    # Consider only artifacts still retained after stages 1-2; delete the
    # oldest of those until the retained total is within the cap.
    if ($MaxTotalSizeBytes -gt 0) {
        $retained = @($items | Where-Object { $_.Reasons.Count -eq 0 })
        $retainedTotal = Get-SizeSum $retained

        if ($retainedTotal -gt $MaxTotalSizeBytes) {
            # Oldest first so we shed the least-valuable artifacts.
            $oldestFirst = $retained | Sort-Object -Property Created
            foreach ($it in $oldestFirst) {
                if ($retainedTotal -le $MaxTotalSizeBytes) { break }
                $it.Reasons.Add('MaxTotalSize')
                $retainedTotal -= $it.Size
            }
        }
    }

    # Partition ----------------------------------------------------------
    $delete = @($items | Where-Object { $_.Reasons.Count -gt 0 })
    $retain = @($items | Where-Object { $_.Reasons.Count -eq 0 })

    $project = {
        param($it)
        [pscustomobject]@{
            Name          = $it.Name
            Size          = $it.Size
            Created       = $it.Created
            WorkflowRunId = $it.WorkflowRunId
            Reasons       = @($it.Reasons)
        }
    }

    $reclaimed = Get-SizeSum $delete
    $retainedSize = Get-SizeSum $retain

    [pscustomobject]@{
        DryRun  = [bool]$DryRun
        Delete  = @($delete | ForEach-Object { & $project $_ })
        Retain  = @($retain | ForEach-Object { & $project $_ })
        Summary = [pscustomobject]@{
            TotalArtifacts      = $items.Count
            DeletedCount        = $delete.Count
            RetainedCount       = $retain.Count
            SpaceReclaimedBytes = [long]$reclaimed
            RetainedSizeBytes   = [long]$retainedSize
        }
        Policy  = [pscustomobject]@{
            MaxAgeDays        = $MaxAgeDays
            MaxTotalSizeBytes = $MaxTotalSizeBytes
            KeepLatestN       = $KeepLatestN
            GroupBy           = $GroupBy
            ReferenceDate     = $ReferenceDate
        }
    }
}

function Import-ArtifactConfig {
    <#
        Read a JSON config file describing referenceDate, policy, dryRun and
        artifacts. Returns a hashtable of normalised values ready to splat into
        Get-ArtifactCleanupPlan.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Input file not found: $Path"
    }

    try {
        $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        $cfg = $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Failed to parse JSON config '$Path': $($_.Exception.Message)"
    }

    if (-not ($cfg.PSObject.Properties.Name -contains 'artifacts')) {
        throw "Config '$Path' has no 'artifacts' array."
    }

    $artifacts = @($cfg.artifacts | ConvertTo-Artifact)

    $result = @{ Artifacts = $artifacts }

    if ($cfg.PSObject.Properties.Name -contains 'referenceDate' -and $cfg.referenceDate) {
        [datetime] $ref = [datetime]::MinValue
        if (-not [datetime]::TryParse([string]$cfg.referenceDate, [ref]$ref)) {
            throw "Config '$Path' has an unparseable referenceDate: '$($cfg.referenceDate)'."
        }
        $result.ReferenceDate = $ref
    }

    if ($cfg.PSObject.Properties.Name -contains 'dryRun') {
        $result.DryRun = [bool]$cfg.dryRun
    }

    if ($cfg.PSObject.Properties.Name -contains 'policy' -and $cfg.policy) {
        $p = $cfg.policy
        if ($p.PSObject.Properties.Name -contains 'maxAgeDays')        { $result.MaxAgeDays = [int]$p.maxAgeDays }
        if ($p.PSObject.Properties.Name -contains 'maxTotalSizeBytes') { $result.MaxTotalSizeBytes = [long]$p.maxTotalSizeBytes }
        if ($p.PSObject.Properties.Name -contains 'keepLatestN')       { $result.KeepLatestN = [int]$p.keepLatestN }
        if ($p.PSObject.Properties.Name -contains 'groupBy' -and $p.groupBy) { $result.GroupBy = [string]$p.groupBy }
    }

    return $result
}

function Format-ArtifactCleanupReport {
    <#
        Render a deletion plan as either human-readable text or JSON. The text
        form emits a stable, machine-greppable SUMMARY line that the act-based
        integration tests assert against.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object] $Plan,

        [ValidateSet('Text', 'Json')]
        [string] $Format = 'Text',

        # Optional label echoed into the summary line (e.g. the fixture name).
        [string] $Case = ''
    )
    process {
        if ($Format -eq 'Json') {
            return ($Plan | ConvertTo-Json -Depth 6)
        }

        $s = $Plan.Summary
        $mode = $Plan.DryRun ? 'DRY-RUN' : 'EXECUTE'
        $lines = [System.Collections.Generic.List[string]]::new()
        $lines.Add("=== Artifact Cleanup Plan ($mode) ===")
        if ($Case) { $lines.Add("Case: $Case") }
        $lines.Add('Artifacts marked for deletion:')
        if ($Plan.Delete.Count -eq 0) {
            $lines.Add('  (none)')
        } else {
            foreach ($d in $Plan.Delete) {
                $reasons = ($d.Reasons -join ',')
                $lines.Add(("  - {0} ({1} bytes, created {2:yyyy-MM-dd}, run {3}) [{4}]" -f `
                            $d.Name, $d.Size, $d.Created, $d.WorkflowRunId, $reasons))
            }
        }
        # Stable, single-line summary for exact-value assertions.
        $lines.Add(("SUMMARY: case={0} total={1} retained={2} deleted={3} reclaimed={4} retainedSize={5} dryRun={6}" -f `
                    $Case, $s.TotalArtifacts, $s.RetainedCount, $s.DeletedCount, `
                    $s.SpaceReclaimedBytes, $s.RetainedSizeBytes, $Plan.DryRun.ToString().ToLower()))

        return ($lines -join [Environment]::NewLine)
    }
}

# ---------------------------------------------------------------------------
# CLI "main" - only runs when -InputPath is supplied.
# ---------------------------------------------------------------------------
function Invoke-ArtifactCleanupCli {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $InputPath,
        [int]    $MaxAgeDays,
        [long]   $MaxTotalSizeBytes,
        [int]    $KeepLatestN,
        [string] $GroupBy,
        [string] $ReferenceDate,
        [switch] $DryRun,
        [string] $Format,
        [string] $OutputPath,
        [hashtable] $BoundParameters
    )

    $cfg = Import-ArtifactConfig -Path $InputPath

    # CLI-supplied parameters override values from the config file.
    if ($BoundParameters.ContainsKey('MaxAgeDays'))        { $cfg.MaxAgeDays = $MaxAgeDays }
    if ($BoundParameters.ContainsKey('MaxTotalSizeBytes')) { $cfg.MaxTotalSizeBytes = $MaxTotalSizeBytes }
    if ($BoundParameters.ContainsKey('KeepLatestN'))       { $cfg.KeepLatestN = $KeepLatestN }
    if ($BoundParameters.ContainsKey('GroupBy'))           { $cfg.GroupBy = $GroupBy }
    if ($BoundParameters.ContainsKey('DryRun') -and $DryRun) { $cfg.DryRun = $true }
    if ($BoundParameters.ContainsKey('ReferenceDate') -and $ReferenceDate) {
        [datetime] $ref = [datetime]::MinValue
        if (-not [datetime]::TryParse($ReferenceDate, [ref]$ref)) {
            throw "Unparseable -ReferenceDate: '$ReferenceDate'."
        }
        $cfg.ReferenceDate = $ref
    }

    $planArgs = @{ Artifacts = $cfg.Artifacts }
    foreach ($k in 'MaxAgeDays', 'MaxTotalSizeBytes', 'KeepLatestN', 'GroupBy', 'ReferenceDate') {
        if ($cfg.ContainsKey($k)) { $planArgs[$k] = $cfg[$k] }
    }
    if ($cfg.ContainsKey('DryRun') -and $cfg.DryRun) { $planArgs.DryRun = $true }

    $plan = Get-ArtifactCleanupPlan @planArgs

    $case = [System.IO.Path]::GetFileNameWithoutExtension($InputPath)
    $report = Format-ArtifactCleanupReport -Plan $plan -Format $Format -Case $case

    if ($OutputPath) {
        Set-Content -LiteralPath $OutputPath -Value $report -Encoding utf8
    }

    return $report
}

# Detect direct invocation vs dot-sourcing. $MyInvocation.InvocationName is '.'
# when dot-sourced; we only run main when an InputPath was actually provided.
if ($PSBoundParameters.ContainsKey('InputPath') -and $InputPath) {
    try {
        $output = Invoke-ArtifactCleanupCli `
            -InputPath $InputPath `
            -MaxAgeDays $MaxAgeDays `
            -MaxTotalSizeBytes $MaxTotalSizeBytes `
            -KeepLatestN $KeepLatestN `
            -GroupBy $GroupBy `
            -ReferenceDate $ReferenceDate `
            -DryRun:$DryRun `
            -Format $Format `
            -OutputPath $OutputPath `
            -BoundParameters $PSBoundParameters
        Write-Output $output
    } catch {
        Write-Error $_.Exception.Message
        exit 1
    }
}
