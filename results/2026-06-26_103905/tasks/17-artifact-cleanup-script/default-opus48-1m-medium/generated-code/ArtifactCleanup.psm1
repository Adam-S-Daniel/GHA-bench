# ArtifactCleanup.psm1
# Core library for applying artifact retention policies and producing a
# deletion plan. Built incrementally via red/green TDD (see ArtifactCleanup.Tests.ps1).

function New-Artifact {
    <#
    .SYNOPSIS
        Factory for a normalised artifact object.
    .DESCRIPTION
        Used both by callers and by tests as a fixture factory. The CreatedAt
        value is parsed into a [datetime] so downstream date math is reliable.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]   $Name,
        [Parameter(Mandatory)][long]     $SizeBytes,
        [Parameter(Mandatory)]           $CreatedAt,
        [Parameter(Mandatory)][string]   $WorkflowName,
        [Parameter(Mandatory)][long]     $WorkflowRunId
    )

    # Accept either a [datetime] or an ISO-8601 string and normalise to UTC.
    $created = if ($CreatedAt -is [datetime]) {
        $CreatedAt.ToUniversalTime()
    } else {
        [datetime]::Parse($CreatedAt, [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor
            [System.Globalization.DateTimeStyles]::AssumeUniversal)
    }

    [pscustomobject]@{
        Name          = $Name
        SizeBytes     = $SizeBytes
        CreatedAt     = $created
        WorkflowName  = $WorkflowName
        WorkflowRunId = $WorkflowRunId
    }
}

function Get-ArtifactDeletionPlan {
    <#
    .SYNOPSIS
        Apply retention policies to a set of artifacts and return a deletion plan.
    .DESCRIPTION
        Policies are applied in a deterministic order so results are predictable:
          1. MaxAgeDays         - delete artifacts older than N days.
          2. KeepLatestN        - per workflow, keep only the N newest artifacts.
          3. MaxTotalSizeBytes  - if survivors still exceed the cap, delete oldest first.
        An artifact deleted by an earlier policy is not re-evaluated by later ones.
        Returns an object with .Delete and .Retain arrays; each deleted artifact
        carries a .Reason explaining which policy removed it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Artifacts,
        [int]      $MaxAgeDays,
        [int]      $KeepLatestN,
        [long]     $MaxTotalSizeBytes,
        [datetime] $Now = [datetime]::UtcNow
    )

    # Work on a mutable copy so we never mutate the caller's objects. Each entry
    # tracks whether it has been marked for deletion and why.
    $items = foreach ($a in $Artifacts) {
        [pscustomobject]@{ Artifact = $a; Delete = $false; Reason = $null }
    }

    # --- Policy 1: maximum age ------------------------------------------------
    if ($PSBoundParameters.ContainsKey('MaxAgeDays')) {
        $cutoff = $Now.AddDays(-$MaxAgeDays)
        foreach ($i in $items) {
            if (-not $i.Delete -and $i.Artifact.CreatedAt -lt $cutoff) {
                $ageDays = [math]::Floor(($Now - $i.Artifact.CreatedAt).TotalDays)
                $i.Delete = $true
                $i.Reason = "Exceeds max age ($MaxAgeDays days): artifact is $ageDays days old"
            }
        }
    }

    # --- Policy 2: keep latest N per workflow ---------------------------------
    if ($PSBoundParameters.ContainsKey('KeepLatestN')) {
        # Group surviving items by workflow name; within each group sort newest
        # first and mark anything beyond the first N for deletion.
        $survivors = $items | Where-Object { -not $_.Delete }
        $groups = $survivors | Group-Object { $_.Artifact.WorkflowName }
        foreach ($g in $groups) {
            $ordered = $g.Group | Sort-Object { $_.Artifact.CreatedAt } -Descending
            $rank = 0
            foreach ($i in $ordered) {
                $rank++
                if ($rank -gt $KeepLatestN) {
                    $i.Delete = $true
                    $i.Reason = "Exceeds keep-latest-$KeepLatestN for workflow '$($i.Artifact.WorkflowName)'"
                }
            }
        }
    }

    # --- Policy 3: maximum total retained size --------------------------------
    if ($PSBoundParameters.ContainsKey('MaxTotalSizeBytes')) {
        $survivors = @($items | Where-Object { -not $_.Delete })
        $retainedBytes = ($survivors | Measure-Object -Property { $_.Artifact.SizeBytes } -Sum).Sum
        if ($null -eq $retainedBytes) { $retainedBytes = 0 }

        if ($retainedBytes -gt $MaxTotalSizeBytes) {
            # Delete oldest survivors first until we are within the cap.
            $oldestFirst = $survivors | Sort-Object { $_.Artifact.CreatedAt }
            foreach ($i in $oldestFirst) {
                if ($retainedBytes -le $MaxTotalSizeBytes) { break }
                $i.Delete = $true
                $i.Reason = "Exceeds max total size ($MaxTotalSizeBytes bytes): freed $($i.Artifact.SizeBytes) bytes"
                $retainedBytes -= $i.Artifact.SizeBytes
            }
        }
    }

    Build-DeletionPlanResult -Items $items
}

function Get-ArtifactSummary {
    <#
    .SYNOPSIS
        Produce summary statistics for a deletion plan.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Plan)

    $reclaimed = ($Plan.Delete | Measure-Object -Property SizeBytes -Sum).Sum
    $retained  = ($Plan.Retain | Measure-Object -Property SizeBytes -Sum).Sum
    if ($null -eq $reclaimed) { $reclaimed = 0 }
    if ($null -eq $retained)  { $retained  = 0 }

    [pscustomobject]@{
        DeletedCount        = $Plan.Delete.Count
        RetainedCount       = $Plan.Retain.Count
        TotalArtifacts      = $Plan.Delete.Count + $Plan.Retain.Count
        SpaceReclaimedBytes = [long]$reclaimed
        SpaceRetainedBytes  = [long]$retained
    }
}

function Build-DeletionPlanResult {
    # Internal helper: split the working list into Delete/Retain projections.
    param([object[]] $Items)

    $delete = foreach ($i in ($Items | Where-Object Delete)) {
        $i.Artifact | Add-Member -NotePropertyName Reason -NotePropertyValue $i.Reason -PassThru -Force
    }
    $retain = foreach ($i in ($Items | Where-Object { -not $_.Delete })) { $i.Artifact }

    [pscustomobject]@{
        Delete = @($delete)
        Retain = @($retain)
    }
}

function ConvertTo-Artifact {
    <#
    .SYNOPSIS
        Normalise raw objects (e.g. parsed JSON) into validated artifact objects.
    .DESCRIPTION
        Each input object must expose name, sizeBytes, createdAt, workflowName and
        workflowRunId. Missing fields raise a clear, actionable error.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()] $InputObject)

    $required = 'name', 'sizeBytes', 'createdAt', 'workflowName', 'workflowRunId'

    foreach ($o in @($InputObject)) {
        foreach ($field in $required) {
            if ($null -eq $o.$field) {
                throw "Invalid artifact record: required field '$field' is missing or null in: $($o | ConvertTo-Json -Compress)"
            }
        }
        New-Artifact -Name $o.name -SizeBytes ([long]$o.sizeBytes) -CreatedAt $o.createdAt `
            -WorkflowName $o.workflowName -WorkflowRunId ([long]$o.workflowRunId)
    }
}

function Invoke-ArtifactCleanup {
    <#
    .SYNOPSIS
        Top-level orchestration: build a plan, summarise it, and (unless -DryRun)
        "execute" the deletions by invoking the -OnDelete callback per artifact.
    .DESCRIPTION
        Because the artifacts are mock data, "execution" is modelled by an
        injectable callback so the behaviour stays fully testable. In dry-run
        mode no callback is invoked; the plan is returned for inspection only.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Artifacts,
        [int]          $MaxAgeDays,
        [int]          $KeepLatestN,
        [long]         $MaxTotalSizeBytes,
        [datetime]     $Now = [datetime]::UtcNow,
        [switch]       $DryRun,
        [scriptblock]  $OnDelete
    )

    # Forward only the policy parameters the caller actually supplied so the
    # plan function can distinguish "not set" from "set to 0".
    $planArgs = @{ Artifacts = $Artifacts; Now = $Now }
    foreach ($p in 'MaxAgeDays', 'KeepLatestN', 'MaxTotalSizeBytes') {
        if ($PSBoundParameters.ContainsKey($p)) { $planArgs[$p] = $PSBoundParameters[$p] }
    }

    $plan    = Get-ArtifactDeletionPlan @planArgs
    $summary = Get-ArtifactSummary -Plan $plan

    if (-not $DryRun -and $OnDelete) {
        foreach ($artifact in $plan.Delete) {
            & $OnDelete $artifact
        }
    }

    [pscustomobject]@{
        DryRun  = [bool]$DryRun
        Plan    = $plan
        Summary = $summary
    }
}

Export-ModuleMember -Function New-Artifact, Get-ArtifactDeletionPlan, Get-ArtifactSummary, ConvertTo-Artifact, Invoke-ArtifactCleanup
