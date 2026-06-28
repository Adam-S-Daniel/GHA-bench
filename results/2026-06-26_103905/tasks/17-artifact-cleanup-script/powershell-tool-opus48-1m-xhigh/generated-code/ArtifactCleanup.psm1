function ConvertTo-ArtifactObject {
    <#
    .SYNOPSIS
        (Private) Validate a single raw artifact record and coerce it to a typed
        object. Throws a clear, indexed error message on any problem.
    #>
    param(
        [Parameter(Mandatory)]
        $Record,

        [int]$Index = 1
    )

    $required = 'Name', 'SizeBytes', 'CreatedAt', 'WorkflowRunId'
    foreach ($field in $required) {
        $hasField = $Record.PSObject.Properties.Name -contains $field
        if (-not $hasField -or $null -eq $Record.$field -or "$($Record.$field)" -eq '') {
            throw "Artifact #$Index is missing required field '$field'."
        }
    }

    # Validate and coerce SizeBytes.
    [long]$size = 0
    if (-not [long]::TryParse("$($Record.SizeBytes)", [ref]$size)) {
        throw "Artifact #$Index ('$($Record.Name)') has a non-numeric SizeBytes value: '$($Record.SizeBytes)'."
    }
    if ($size -lt 0) {
        throw "Artifact #$Index ('$($Record.Name)') has a negative SizeBytes value: $size."
    }

    # Validate and coerce CreatedAt (parsed as UTC for deterministic ages).
    $created = [datetime]::MinValue
    $styles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
    if (-not [datetime]::TryParse("$($Record.CreatedAt)", [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$created)) {
        throw "Artifact #$Index ('$($Record.Name)') has an unparseable CreatedAt value: '$($Record.CreatedAt)'."
    }

    [pscustomobject]@{
        Name          = [string]$Record.Name
        SizeBytes     = $size
        CreatedAt     = $created
        WorkflowRunId = $Record.WorkflowRunId
    }
}

function Read-JsonFile {
    <#
    .SYNOPSIS
        (Private) Read and parse a JSON file with friendly error messages.
    #>
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "File not found: '$Path'."
    }

    $raw = Get-Content -LiteralPath $Path -Raw
    try {
        return ($raw | ConvertFrom-Json -ErrorAction Stop)
    }
    catch {
        throw "Failed to parse JSON from '$Path': $($_.Exception.Message)"
    }
}

function Import-ArtifactData {
    <#
    .SYNOPSIS
        Load and validate artifact metadata from a JSON file (a bare array).
    .DESCRIPTION
        Reads a JSON array of artifact objects, validates that each has the
        required fields (Name, SizeBytes, CreatedAt, WorkflowRunId), coerces
        them to strong types, and returns the normalized objects. Every failure
        mode throws a clear, actionable error message rather than a raw .NET
        exception.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $parsed = Read-JsonFile -Path $Path

    # A single object is valid; normalize to an array so callers iterate uniformly.
    $records = @($parsed)
    $index = 0
    $result = foreach ($record in $records) {
        $index++
        ConvertTo-ArtifactObject -Record $record -Index $index
    }

    return @($result)
}

function Import-CleanupScenario {
    <#
    .SYNOPSIS
        Load a self-contained cleanup scenario (policy + mode + artifacts).
    .DESCRIPTION
        A scenario file bundles everything a single run needs:

            {
              "referenceDate": "2026-06-28T00:00:00Z",   // optional, defaults to now
              "dryRun": true,                             // optional, defaults to true
              "policy": {                                 // optional, each field optional
                "maxAgeDays": 30,
                "maxTotalSizeBytes": 5000,
                "keepLatestPerWorkflow": 2
              },
              "artifacts": [ ... ]                        // required
            }

        This is the format consumed by the CLI and the act test harness so each
        test case is a single, fully reproducible file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $parsed = Read-JsonFile -Path $Path

    # The artifacts array is the only mandatory part of a scenario.
    $hasArtifacts = $parsed.PSObject.Properties.Name -contains 'artifacts'
    if (-not $hasArtifacts -or $null -eq $parsed.artifacts) {
        throw "Scenario file '$Path' is missing the required 'artifacts' array."
    }

    $records = @($parsed.artifacts)
    $index = 0
    $artifacts = foreach ($record in $records) {
        $index++
        ConvertTo-ArtifactObject -Record $record -Index $index
    }

    # Optional policy block; each field defaults to null (policy disabled).
    $policy = [pscustomobject]@{
        MaxAgeDays            = $null
        MaxTotalSizeBytes     = $null
        KeepLatestPerWorkflow = $null
    }
    if ($parsed.PSObject.Properties.Name -contains 'policy' -and $null -ne $parsed.policy) {
        $pol = $parsed.policy
        if ($pol.PSObject.Properties.Name -contains 'maxAgeDays'            -and $null -ne $pol.maxAgeDays)            { $policy.MaxAgeDays            = [int]$pol.maxAgeDays }
        if ($pol.PSObject.Properties.Name -contains 'maxTotalSizeBytes'     -and $null -ne $pol.maxTotalSizeBytes)     { $policy.MaxTotalSizeBytes     = [long]$pol.maxTotalSizeBytes }
        if ($pol.PSObject.Properties.Name -contains 'keepLatestPerWorkflow' -and $null -ne $pol.keepLatestPerWorkflow) { $policy.KeepLatestPerWorkflow = [int]$pol.keepLatestPerWorkflow }
    }

    # dryRun defaults to $true (a destructive tool should be safe by default).
    $dryRun = $true
    if ($parsed.PSObject.Properties.Name -contains 'dryRun' -and $null -ne $parsed.dryRun) {
        $dryRun = [bool]$parsed.dryRun
    }

    # referenceDate defaults to "now" when absent.
    $referenceDate = Get-Date
    if ($parsed.PSObject.Properties.Name -contains 'referenceDate' -and "$($parsed.referenceDate)" -ne '') {
        $parsedDate = [datetime]::MinValue
        $styles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
        if (-not [datetime]::TryParse("$($parsed.referenceDate)", [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$parsedDate)) {
            throw "Scenario file '$Path' has an unparseable referenceDate: '$($parsed.referenceDate)'."
        }
        $referenceDate = $parsedDate
    }

    [pscustomobject]@{
        ReferenceDate = $referenceDate
        DryRun        = $dryRun
        Policy        = $policy
        Artifacts     = @($artifacts)
    }
}

function Get-ArtifactCleanupPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Artifacts,

        # Delete artifacts strictly older than this many days. The boundary is
        # inclusive: an artifact exactly MaxAgeDays old is retained.
        [ValidateRange(0, [int]::MaxValue)]
        [Nullable[int]]$MaxAgeDays,

        # Keep the N most-recently-created artifacts within each workflow run and
        # mark the rest for deletion. The kept N are also "protected": no other
        # policy (max-age, max-total-size) may delete them.
        [ValidateRange(0, [int]::MaxValue)]
        [Nullable[int]]$KeepLatestPerWorkflow,

        # Cap the total retained size (in bytes). When the retained set exceeds
        # this, delete the oldest still-retained artifacts until it fits.
        [ValidateRange(0, [long]::MaxValue)]
        [Nullable[long]]$MaxTotalSizeBytes,

        [datetime]$ReferenceDate = (Get-Date)
    )

    # Composition model: the policies are independent filters combined as a
    # UNION of deletions. An artifact is retained only if it satisfies EVERY
    # enabled policy (it is within the newest-N of its workflow run AND within
    # the max age AND it still fits under the size cap). max-total-size is the
    # aggregate trim and therefore runs last. This keeps the three policies
    # genuinely composable -- no single policy can mask the others.

    $warnings = [System.Collections.Generic.List[string]]::new()

    # Build a working record for each artifact. Action starts as 'Retain' and is
    # flipped to 'Delete' by the policy passes below; Reason explains the decision.
    $items = foreach ($a in $Artifacts) {
        [pscustomobject]@{
            Name          = $a.Name
            SizeBytes     = [long]$a.SizeBytes
            CreatedAt     = [datetime]$a.CreatedAt
            WorkflowRunId = $a.WorkflowRunId
            Action        = 'Retain'
            Reason        = 'Retained: satisfies every enabled retention policy'
        }
    }
    $items = @($items)

    # --- Policy: keep latest N per workflow ----------------------------------
    # Within each workflow run, rank artifacts newest-first and delete everything
    # ranked beyond the newest N. Ties on CreatedAt fall back to Name so the
    # ranking is fully deterministic.
    if ($null -ne $KeepLatestPerWorkflow) {
        $groups = $items | Group-Object -Property WorkflowRunId
        foreach ($group in $groups) {
            $ranked = @($group.Group | Sort-Object -Property @{Expression='CreatedAt';Descending=$true}, @{Expression='Name';Descending=$false})
            for ($i = $KeepLatestPerWorkflow; $i -lt $ranked.Count; $i++) {
                $ranked[$i].Action = 'Delete'
                $ranked[$i].Reason = "Deleted: not among the newest $KeepLatestPerWorkflow artifact(s) of workflow run $($ranked[$i].WorkflowRunId)"
            }
        }
    }

    # --- Policy: maximum age -------------------------------------------------
    # Anything created before the cutoff is past its retention window. Applied
    # independently of keep-latest: a recent-enough-to-be-kept artifact is still
    # removed if it is too old.
    if ($null -ne $MaxAgeDays) {
        $cutoff = $ReferenceDate.AddDays(-$MaxAgeDays)
        foreach ($item in $items) {
            if ($item.Action -eq 'Delete') { continue }
            if ($item.CreatedAt -lt $cutoff) {
                $ageDays = [math]::Floor(($ReferenceDate - $item.CreatedAt).TotalDays)
                $item.Action = 'Delete'
                $item.Reason = "Deleted: age ${ageDays}d exceeds max age ${MaxAgeDays}d"
            }
        }
    }

    # --- Policy: maximum total retained size ---------------------------------
    # Aggregate trim: while the retained total exceeds the cap, delete the oldest
    # still-retained artifact (ties broken by Name) until it fits.
    if ($null -ne $MaxTotalSizeBytes) {
        # If a single artifact is larger than the whole cap it can never be kept;
        # surface that as a warning so the operator can spot a too-small cap.
        $largest = [long](($items | Measure-Object -Property SizeBytes -Maximum).Maximum)
        if ($items.Count -gt 0 -and $largest -gt $MaxTotalSizeBytes) {
            $warnings.Add("Max total size cap ($MaxTotalSizeBytes bytes) is smaller than the largest artifact ($largest bytes); such artifacts can never be retained under this cap.")
        }

        $retainedSize = [long](($items | Where-Object Action -eq 'Retain' | Measure-Object -Property SizeBytes -Sum).Sum)
        if ($retainedSize -gt $MaxTotalSizeBytes) {
            # Evict oldest-first until the retained total fits.
            $candidates = @($items |
                Where-Object Action -eq 'Retain' |
                Sort-Object -Property @{Expression='CreatedAt';Descending=$false}, @{Expression='Name';Descending=$false})

            foreach ($item in $candidates) {
                if ($retainedSize -le $MaxTotalSizeBytes) { break }
                $item.Action = 'Delete'
                $item.Reason = "Deleted: max total size cap of $MaxTotalSizeBytes bytes exceeded (oldest-first eviction)"
                $retainedSize -= $item.SizeBytes
            }
        }
    }

    $deleted  = @($items | Where-Object Action -eq 'Delete')
    $retained = @($items | Where-Object Action -eq 'Retain')

    $summary = [pscustomobject]@{
        TotalArtifacts      = $items.Count
        RetainedCount       = $retained.Count
        DeletedCount        = $deleted.Count
        SpaceReclaimedBytes = [long](($deleted  | Measure-Object -Property SizeBytes -Sum).Sum)
        RetainedSizeBytes   = [long](($retained | Measure-Object -Property SizeBytes -Sum).Sum)
        Warnings            = @($warnings)
    }

    [pscustomobject]@{
        Items   = $items
        Summary = $summary
    }
}

function Format-Bytes {
    <#
    .SYNOPSIS
        Render a byte count as a compact human-readable size (e.g. 1.5 KB).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [long]$Bytes
    )

    if ($Bytes -lt 0) { throw "Format-Bytes: byte count must be non-negative (got $Bytes)." }

    $units = 'B', 'KB', 'MB', 'GB', 'TB', 'PB'
    $value = [double]$Bytes
    $unitIndex = 0
    while ($value -ge 1024 -and $unitIndex -lt ($units.Count - 1)) {
        $value /= 1024
        $unitIndex++
    }

    if ($unitIndex -eq 0) {
        return "$([long]$value) B"   # whole bytes, no decimal point
    }

    # Round to two decimals and drop trailing zeros (1.50 -> "1.5", 1.00 -> "1").
    $rounded = [math]::Round($value, 2)
    $text = $rounded.ToString([System.Globalization.CultureInfo]::InvariantCulture)
    return "$text $($units[$unitIndex])"
}

function Invoke-ArtifactCleanup {
    <#
    .SYNOPSIS
        Orchestrate a cleanup: load data (or accept it directly), build the
        retention plan, and tag it with the run mode and applied policy.
    .DESCRIPTION
        This is the high-level entry point used by the CLI wrapper. It forwards
        only the policy parameters that were actually supplied so the engine can
        tell "policy disabled" apart from a literal zero value. Dry-run mode is
        recorded on the returned plan; it changes reporting only -- the plan
        itself is identical either way (this tool operates on mock data and does
        not call the GitHub API).
    #>
    [CmdletBinding(DefaultParameterSetName = 'Artifacts')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Path')]
        [string]$Path,

        [Parameter(Mandatory, ParameterSetName = 'Artifacts')]
        [AllowEmptyCollection()]
        [object[]]$Artifacts,

        [Nullable[int]]$MaxAgeDays,
        [Nullable[long]]$MaxTotalSizeBytes,
        [Nullable[int]]$KeepLatestPerWorkflow,
        [datetime]$ReferenceDate = (Get-Date),
        [switch]$DryRun
    )

    if ($PSCmdlet.ParameterSetName -eq 'Path') {
        $Artifacts = Import-ArtifactData -Path $Path
    }

    $planArgs = @{ Artifacts = $Artifacts; ReferenceDate = $ReferenceDate }
    if ($null -ne $MaxAgeDays)            { $planArgs.MaxAgeDays            = $MaxAgeDays }
    if ($null -ne $MaxTotalSizeBytes)     { $planArgs.MaxTotalSizeBytes     = $MaxTotalSizeBytes }
    if ($null -ne $KeepLatestPerWorkflow) { $planArgs.KeepLatestPerWorkflow = $KeepLatestPerWorkflow }

    $plan = Get-ArtifactCleanupPlan @planArgs

    Add-Member -InputObject $plan -NotePropertyName DryRun -NotePropertyValue ([bool]$DryRun)
    Add-Member -InputObject $plan -NotePropertyName Policy -NotePropertyValue ([pscustomobject]@{
        MaxAgeDays            = $MaxAgeDays
        MaxTotalSizeBytes     = $MaxTotalSizeBytes
        KeepLatestPerWorkflow = $KeepLatestPerWorkflow
    })

    return $plan
}

function Format-CleanupReport {
    <#
    .SYNOPSIS
        Render a cleanup plan as a human- and machine-readable text report.
    .DESCRIPTION
        The summary section uses stable "Key: value" lines so downstream
        automation (and the act-based test harness) can assert exact values.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Plan
    )

    $isDryRun = [bool]$Plan.DryRun
    $mode = if ($isDryRun) { 'DRY-RUN' } else { 'EXECUTE' }

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('=== Artifact Cleanup Plan ===')
    [void]$sb.AppendLine("Mode: $mode")

    # Echo the applied policy so the report is self-describing.
    if ($Plan.PSObject.Properties.Name -contains 'Policy') {
        $p = $Plan.Policy
        $maxAge  = if ($null -ne $p.MaxAgeDays)            { "$($p.MaxAgeDays)d" }            else { 'off' }
        $maxSize = if ($null -ne $p.MaxTotalSizeBytes)     { (Format-Bytes -Bytes $p.MaxTotalSizeBytes) } else { 'off' }
        $keepN   = if ($null -ne $p.KeepLatestPerWorkflow) { "$($p.KeepLatestPerWorkflow)" }  else { 'off' }
        [void]$sb.AppendLine("Policy: MaxAge=$maxAge; MaxTotalSize=$maxSize; KeepLatestPerWorkflow=$keepN")
    }

    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('--- Artifacts ---')
    foreach ($item in $Plan.Items) {
        $tag = $item.Action.ToUpperInvariant()   # DELETE / RETAIN
        $size = Format-Bytes -Bytes $item.SizeBytes
        $created = $item.CreatedAt.ToString('yyyy-MM-dd')
        [void]$sb.AppendLine(("  [{0}] {1}  size={2}  run={3}  created={4}  reason: {5}" -f `
            $tag, $item.Name, $size, $item.WorkflowRunId, $created, $item.Reason))
    }

    $s = $Plan.Summary
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('--- Summary ---')
    [void]$sb.AppendLine("TotalArtifacts: $($s.TotalArtifacts)")
    [void]$sb.AppendLine("RetainedCount: $($s.RetainedCount)")
    [void]$sb.AppendLine("DeletedCount: $($s.DeletedCount)")
    [void]$sb.AppendLine("SpaceReclaimedBytes: $($s.SpaceReclaimedBytes)")
    [void]$sb.AppendLine("SpaceReclaimedHuman: $(Format-Bytes -Bytes $s.SpaceReclaimedBytes)")
    [void]$sb.AppendLine("RetainedSizeBytes: $($s.RetainedSizeBytes)")
    [void]$sb.AppendLine("RetainedSizeHuman: $(Format-Bytes -Bytes $s.RetainedSizeBytes)")

    foreach ($w in $s.Warnings) {
        [void]$sb.AppendLine("WARNING: $w")
    }

    [void]$sb.AppendLine('')
    if ($isDryRun) {
        [void]$sb.AppendLine("[DRY-RUN] No artifacts were deleted. Re-run without -DryRun to apply this plan.")
    }
    else {
        [void]$sb.AppendLine("[EXECUTE] Deleted $($s.DeletedCount) artifact(s), reclaiming $(Format-Bytes -Bytes $s.SpaceReclaimedBytes).")
    }

    return $sb.ToString()
}

Export-ModuleMember -Function Import-ArtifactData, Import-CleanupScenario, Get-ArtifactCleanupPlan, Format-Bytes, Invoke-ArtifactCleanup, Format-CleanupReport
