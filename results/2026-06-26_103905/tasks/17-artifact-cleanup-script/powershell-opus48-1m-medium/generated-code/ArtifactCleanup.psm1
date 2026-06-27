<#
    ArtifactCleanup.psm1

    A small retention engine for CI build artifacts. Given a collection of
    artifact metadata objects (Name, Size, Created, WorkflowRunId) it applies up
    to three independent retention policies and produces a deletion *plan*:

        * MaxAgeDays   - delete anything older than N days
        * KeepLatestN  - per "workflow" (grouped by artifact Name), keep only the
                         newest N artifacts and delete the older ones
        * MaxTotalSize - cap the total retained size; delete the oldest survivors
                         until the retained set fits under the cap

    The engine is pure: it never deletes anything itself. It only decides what
    *would* be deleted, which makes it trivial to test and to run in dry-run mode.

    Grouping note: the task's metadata exposes a per-run "WorkflowRunId" but the
    natural identity of a *workflow* (a recurring stream of artifacts) is the
    artifact Name, so "keep latest N per workflow" groups by Name. The run id is
    preserved on every artifact for reporting.
#>

Set-StrictMode -Version Latest

function New-ArtifactObject {
    <#
        .SYNOPSIS
            Normalises raw artifact metadata into a consistent object, parsing
            string dates and validating inputs. Used by the entry script when
            loading JSON fixtures.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][long]$Size,
        [Parameter(Mandatory)]$Created,
        [Parameter(Mandatory)]$WorkflowRunId
    )

    if ($Size -lt 0) {
        throw "Invalid artifact '$Name': Size must be non-negative (got $Size)."
    }

    # Accept either a real [datetime] or an ISO-8601 string from JSON.
    $createdDate = $Created -as [datetime]
    if ($null -eq $createdDate) {
        try {
            $createdDate = [datetime]::Parse(
                $Created, [cultureinfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor
                [System.Globalization.DateTimeStyles]::AssumeUniversal)
        } catch {
            throw "Invalid artifact '$Name': Created value '$Created' is not a valid date."
        }
    }

    [pscustomobject]@{
        Name          = $Name
        Size          = $Size
        Created       = $createdDate
        WorkflowRunId = $WorkflowRunId
    }
}

function Invoke-ArtifactRetention {
    <#
        .SYNOPSIS
            Applies retention policies and returns a deletion plan.

        .OUTPUTS
            A PSCustomObject with:
              Deleted   - artifacts selected for deletion
              Retained  - artifacts that survive every policy
              Summary   - { DeletedCount, RetainedCount, SpaceReclaimed, DryRun }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $Artifacts,

        [int]$MaxAgeDays = 0,        # 0 / unset => policy disabled
        [long]$MaxTotalSize = 0,     # 0 / unset => policy disabled
        [int]$KeepLatestN = 0,       # 0 / unset => policy disabled

        # Reference "now" for age calculations. Defaults to the real clock but
        # tests/CI pass a fixed value for determinism.
        [datetime]$ReferenceDate = [datetime]::UtcNow,

        [switch]$DryRun
    )

    if ($null -eq $Artifacts) {
        throw 'Artifacts collection cannot be null.'
    }

    # Force into an array so a single object is still iterable/countable.
    $items = @($Artifacts)

    # Track deletion decisions keyed by object identity. A hashtable of the
    # artifact reference -> reason keeps the union of policies simple.
    $toDelete = [System.Collections.Generic.List[object]]::new()
    $deleteSet = @{}

    function Add-Delete([object]$item, [string]$reason) {
        if (-not $deleteSet.ContainsKey($item)) {
            $deleteSet[$item] = $reason
            $toDelete.Add($item)
        }
    }

    # --- Policy 1: keep latest N per workflow (grouped by Name) ----------------
    if ($KeepLatestN -gt 0) {
        foreach ($group in ($items | Group-Object -Property Name)) {
            $ordered = $group.Group | Sort-Object -Property Created -Descending
            # Everything past the first N is excess and gets deleted.
            $excess = $ordered | Select-Object -Skip $KeepLatestN
            foreach ($a in $excess) {
                Add-Delete $a "exceeds keep-latest-$KeepLatestN"
            }
        }
    }

    # --- Policy 2: max age -----------------------------------------------------
    if ($MaxAgeDays -gt 0) {
        foreach ($a in $items) {
            $ageDays = ($ReferenceDate - $a.Created).TotalDays
            if ($ageDays -gt $MaxAgeDays) {
                Add-Delete $a "older than $MaxAgeDays days"
            }
        }
    }

    # --- Policy 3: max total size (applied to survivors of policies 1 & 2) -----
    if ($MaxTotalSize -gt 0) {
        $survivors = $items | Where-Object { -not $deleteSet.ContainsKey($_) }
        $totalSize = ($survivors | Measure-Object -Property Size -Sum).Sum
        if ($null -eq $totalSize) { $totalSize = 0 }

        if ($totalSize -gt $MaxTotalSize) {
            # Delete oldest survivors first until we fit under the cap.
            $oldestFirst = $survivors | Sort-Object -Property Created
            foreach ($a in $oldestFirst) {
                if ($totalSize -le $MaxTotalSize) { break }
                Add-Delete $a "total size exceeds $MaxTotalSize bytes"
                $totalSize -= $a.Size
            }
        }
    }

    $deleted  = @($items | Where-Object {  $deleteSet.ContainsKey($_) })
    $retained = @($items | Where-Object { -not $deleteSet.ContainsKey($_) })
    $reclaimed = ($deleted | Measure-Object -Property Size -Sum).Sum
    if ($null -eq $reclaimed) { $reclaimed = 0 }

    [pscustomobject]@{
        Deleted  = $deleted
        Retained = $retained
        Summary  = [pscustomobject]@{
            DeletedCount   = $deleted.Count
            RetainedCount  = $retained.Count
            SpaceReclaimed = [long]$reclaimed
            DryRun         = [bool]$DryRun
        }
    }
}

Export-ModuleMember -Function New-ArtifactObject, Invoke-ArtifactRetention
