# ArtifactCleanup.psm1
#
# Core logic for applying artifact retention policies and producing a
# deletion plan. Pure / side-effect free: it never deletes anything itself,
# it only *decides* what should be deleted. That keeps it trivially testable
# and means the same code path drives both dry-run and "real" execution.
#
# An artifact is any object exposing these properties:
#   Name          [string]   - artifact name
#   SizeBytes     [long]     - size in bytes
#   CreatedAt     [datetime] - creation timestamp
#   WorkflowRunId [long]     - id of the workflow run that produced it
#
# Retention policies (all optional; omit/0 to disable):
#   -MaxAgeDays         delete artifacts older than this many days
#   -KeepLatestN        per workflow run id, keep only the N newest artifacts
#   -MaxTotalSizeBytes  cap on total retained size; oldest are dropped to fit
#
# The policies are applied in a deliberate order (age -> keep-latest-N ->
# size). An artifact is deleted if *any* policy condition marks it; the
# first matching policy wins the "Reason" so the most specific cause is
# reported.

Set-StrictMode -Version Latest

# Required artifact properties, validated up front so we fail loudly with a
# helpful message rather than producing a silently-wrong plan later.
$script:RequiredProperties = @('Name', 'SizeBytes', 'CreatedAt', 'WorkflowRunId')

function Assert-ArtifactShape {
    <#
        Validates that each artifact carries every required property.
        Throws a meaningful error naming the first missing property so the
        caller can correct their input data.
    #>
    param([AllowEmptyCollection()] [object[]] $Artifacts)

    foreach ($artifact in $Artifacts) {
        $present = $artifact.PSObject.Properties.Name
        foreach ($prop in $script:RequiredProperties) {
            if ($present -notcontains $prop) {
                throw "Artifact '$($artifact.Name)' is missing required property '$prop'."
            }
        }
    }
}

function Get-ArtifactCleanupPlan {
    <#
        .SYNOPSIS
            Build a deletion plan from a set of artifacts and retention policies.

        .DESCRIPTION
            Returns an object describing which artifacts to delete vs retain,
            the reason for each deletion, and a roll-up summary including the
            total space that would be reclaimed.

        .PARAMETER Artifacts
            The artifacts to evaluate (see module header for required shape).

        .PARAMETER MaxAgeDays
            Delete artifacts strictly older than this many days. 0 disables.

        .PARAMETER KeepLatestN
            Keep only the N newest artifacts per workflow run id. 0 disables.

        .PARAMETER MaxTotalSizeBytes
            Cap on total retained size in bytes. Oldest surviving artifacts are
            dropped until the cap is satisfied. 0 disables.

        .PARAMETER Now
            Reference timestamp used for age calculations. Defaults to UTC now;
            tests pass a fixed value for determinism.

        .PARAMETER DryRun
            Marks the plan as a dry run (no execution implied). The planning
            logic is identical either way; this flag is informational and is
            surfaced in the summary so callers/CI can branch on it.
    #>
    [CmdletBinding()]
    param(
        # Not declared Mandatory so we can accept an empty array and emit our
        # own friendly message on $null rather than a binding exception.
        # AllowEmptyCollection lets callers pass @() for "no artifacts".
        [AllowEmptyCollection()]
        [AllowNull()]
        [object[]] $Artifacts,

        [int]  $MaxAgeDays = 0,
        [int]  $KeepLatestN = 0,
        [long] $MaxTotalSizeBytes = 0,

        [datetime] $Now = [datetime]::UtcNow,

        [switch] $DryRun
    )

    # -- Guard clauses ---------------------------------------------------
    if ($null -eq $Artifacts) {
        throw "Parameter 'Artifacts' cannot be null. Pass an empty array for no artifacts."
    }
    if ($MaxAgeDays -lt 0)        { throw "MaxAgeDays cannot be negative (got $MaxAgeDays)." }
    if ($KeepLatestN -lt 0)       { throw "KeepLatestN cannot be negative (got $KeepLatestN)." }
    if ($MaxTotalSizeBytes -lt 0) { throw "MaxTotalSizeBytes cannot be negative (got $MaxTotalSizeBytes)." }

    Assert-ArtifactShape -Artifacts $Artifacts

    # Work on lightweight decision records so we never mutate the caller's
    # objects. Each record tracks whether it is slated for deletion and why.
    $records = foreach ($a in $Artifacts) {
        [pscustomobject]@{
            Name          = $a.Name
            SizeBytes     = [long]$a.SizeBytes
            CreatedAt     = [datetime]$a.CreatedAt
            WorkflowRunId = $a.WorkflowRunId
            Delete        = $false
            Reason        = $null
        }
    }
    # Normalise to an array so .Count / indexing behave with 0 or 1 element.
    $records = @($records)

    # Helper: mark a record for deletion, keeping the first reason recorded.
    $markDelete = {
        param($record, $reason)
        if (-not $record.Delete) {
            $record.Delete = $true
            $record.Reason = $reason
        }
    }

    # -- Policy 1: max age ----------------------------------------------
    if ($MaxAgeDays -gt 0) {
        $cutoff = $Now.AddDays(-$MaxAgeDays)
        foreach ($r in $records) {
            if ($r.CreatedAt -lt $cutoff) {
                & $markDelete $r "Exceeds max age of $MaxAgeDays day(s)"
            }
        }
    }

    # -- Policy 2: keep latest N per workflow ---------------------------
    if ($KeepLatestN -gt 0) {
        $byWorkflow = $records | Group-Object -Property WorkflowRunId
        foreach ($group in $byWorkflow) {
            # Newest first; anything beyond the Nth is surplus.
            $ordered = $group.Group | Sort-Object -Property CreatedAt -Descending
            for ($i = $KeepLatestN; $i -lt $ordered.Count; $i++) {
                & $markDelete $ordered[$i] "Beyond keep-latest-$KeepLatestN for workflow $($group.Name)"
            }
        }
    }

    # -- Policy 3: max total retained size ------------------------------
    # Only survivors of the previous policies count toward the cap. If the
    # survivors still exceed the cap, drop oldest-first until they fit.
    if ($MaxTotalSizeBytes -gt 0) {
        $survivors = @($records | Where-Object { -not $_.Delete } |
            Sort-Object -Property CreatedAt -Descending)  # newest kept first
        $running = 0L
        foreach ($r in $survivors) {
            if (($running + $r.SizeBytes) -gt $MaxTotalSizeBytes) {
                & $markDelete $r "Exceeds max total size of $MaxTotalSizeBytes byte(s)"
            }
            else {
                $running += $r.SizeBytes
            }
        }
    }

    # -- Build result sets and summary ----------------------------------
    $toDelete = @($records | Where-Object { $_.Delete } |
        ForEach-Object {
            [pscustomobject]@{
                Name          = $_.Name
                SizeBytes     = $_.SizeBytes
                CreatedAt     = $_.CreatedAt
                WorkflowRunId = $_.WorkflowRunId
                Reason        = $_.Reason
            }
        })
    $toRetain = @($records | Where-Object { -not $_.Delete } |
        ForEach-Object {
            [pscustomobject]@{
                Name          = $_.Name
                SizeBytes     = $_.SizeBytes
                CreatedAt     = $_.CreatedAt
                WorkflowRunId = $_.WorkflowRunId
            }
        })

    # Sum sizes with explicit loops: Measure-Object on an empty pipeline under
    # StrictMode does not expose a .Sum property, so we avoid it entirely.
    $reclaimed = 0L
    foreach ($d in $toDelete) { $reclaimed += $d.SizeBytes }
    $retainedSize = 0L
    foreach ($r in $toRetain) { $retainedSize += $r.SizeBytes }

    $summary = [pscustomobject]@{
        TotalArtifacts      = $records.Count
        DeletedCount        = $toDelete.Count
        RetainedCount       = $toRetain.Count
        SpaceReclaimedBytes = $reclaimed
        RetainedSizeBytes   = $retainedSize
        # Executed is always false here: this module only plans. A real
        # executor would flip this once deletions have actually run.
        Executed            = $false
    }

    [pscustomobject]@{
        DryRun   = [bool]$DryRun
        ToDelete = $toDelete
        ToRetain = $toRetain
        Summary  = $summary
    }
}

Export-ModuleMember -Function Get-ArtifactCleanupPlan
