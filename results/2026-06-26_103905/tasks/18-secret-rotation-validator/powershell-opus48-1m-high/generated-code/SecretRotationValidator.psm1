#
# SecretRotationValidator.psm1
#
# Core logic for evaluating secret-rotation health. Given secret metadata
# (name, last-rotated date, rotation policy in days, required-by services),
# the functions here classify each secret by urgency (expired / warning / ok)
# and render a rotation report as a markdown table or JSON.
#
# The module is intentionally pure: functions take explicit inputs (including
# the "reference date" used as "now") so behaviour is deterministic and easy
# to test. No global state, no implicit clock reads inside the core logic.
#

Set-StrictMode -Version Latest

function Get-SecretRotationStatus {
    <#
    .SYNOPSIS
        Classify a single secret by rotation urgency.
    .DESCRIPTION
        Computes the due date (lastRotated + policyDays) and compares it to the
        reference date. Returns an enriched object carrying the original
        metadata plus computed fields: dueDate, daysUntilDue and urgency.

        Urgency rules:
          * expired  -> the secret is past its due date (daysUntilDue < 0)
          * warning  -> due within the warning window (0 <= daysUntilDue <= WarningDays)
          * ok       -> due further out than the warning window
    .PARAMETER Secret
        An object with: name, lastRotated (parseable date), policyDays (int),
        and requiredBy (array of service names).
    .PARAMETER ReferenceDate
        The date treated as "now". Defaults to the current date.
    .PARAMETER WarningDays
        Size of the warning window in days. Must be >= 0.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Secret,

        [datetime] $ReferenceDate = (Get-Date),

        [ValidateRange(0, [int]::MaxValue)]
        [int] $WarningDays = 14
    )

    # --- Validate required metadata up front with meaningful errors --------
    foreach ($field in 'name', 'lastRotated', 'policyDays') {
        if (-not ($Secret.PSObject.Properties.Name -contains $field)) {
            throw "Secret is missing required field '$field'."
        }
    }

    $name = $Secret.name
    if ([string]::IsNullOrWhiteSpace([string]$name)) {
        throw "Secret has an empty 'name' field."
    }

    # Parse the last-rotated date; surface a clear error if it is malformed.
    [datetime] $lastRotated = [datetime]::MinValue
    if (-not [datetime]::TryParse([string]$Secret.lastRotated, [ref] $lastRotated)) {
        throw "Secret '$name' has an unparseable lastRotated value: '$($Secret.lastRotated)'."
    }

    # Policy days must be a positive integer.
    [int] $policyDays = 0
    if (-not [int]::TryParse([string]$Secret.policyDays, [ref] $policyDays) -or $policyDays -le 0) {
        throw "Secret '$name' has an invalid policyDays value: '$($Secret.policyDays)' (expected a positive integer)."
    }

    # requiredBy is optional; default to an empty list when absent/null.
    $requiredBy = @()
    if ($Secret.PSObject.Properties.Name -contains 'requiredBy' -and $null -ne $Secret.requiredBy) {
        $requiredBy = @($Secret.requiredBy)
    }

    # --- Compute due date and urgency -------------------------------------
    # Normalise to date boundaries so partial days don't skew the comparison.
    $dueDate = $lastRotated.Date.AddDays($policyDays)
    $daysUntilDue = [int]($dueDate - $ReferenceDate.Date).TotalDays

    $urgency =
        if ($daysUntilDue -lt 0) { 'expired' }
        elseif ($daysUntilDue -le $WarningDays) { 'warning' }
        else { 'ok' }

    [pscustomobject]@{
        name         = [string]$name
        lastRotated  = $lastRotated.ToString('yyyy-MM-dd')
        policyDays   = $policyDays
        requiredBy   = $requiredBy
        dueDate      = $dueDate.ToString('yyyy-MM-dd')
        daysUntilDue = $daysUntilDue
        urgency      = $urgency
    }
}

function Get-SecretRotationReport {
    <#
    .SYNOPSIS
        Evaluate a collection of secrets and build a grouped rotation report.
    .DESCRIPTION
        Classifies every secret via Get-SecretRotationStatus, then sorts the
        results by urgency (expired -> warning -> ok) and, within each bucket,
        by daysUntilDue ascending (most overdue / soonest-due first). Returns a
        structured report object with:
          * referenceDate / warningDays : the evaluation parameters
          * summary                      : counts per urgency + total
          * groups                       : hashtable of urgency -> secret list
          * secrets                      : flat, fully-sorted list
    .PARAMETER Secrets
        Collection of secret metadata objects.
    .PARAMETER ReferenceDate
        The date treated as "now".
    .PARAMETER WarningDays
        Size of the warning window in days.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Secrets,

        [datetime] $ReferenceDate = (Get-Date),

        [ValidateRange(0, [int]::MaxValue)]
        [int] $WarningDays = 14
    )

    # Classify each secret. Failures carry the secret name (added by the inner
    # function) so the caller can pinpoint the offending entry.
    $statuses = foreach ($secret in $Secrets) {
        Get-SecretRotationStatus -Secret $secret -ReferenceDate $ReferenceDate -WarningDays $WarningDays
    }
    $statuses = @($statuses)

    # Rank urgency so expired sorts before warning before ok.
    $rank = @{ expired = 0; warning = 1; ok = 2 }
    $sorted = @($statuses | Sort-Object @{ Expression = { $rank[$_.urgency] } }, daysUntilDue, name)

    # Build per-urgency groups, always present (possibly empty) for stable shape.
    $groups = [ordered]@{ expired = @(); warning = @(); ok = @() }
    foreach ($key in 'expired', 'warning', 'ok') {
        $groups[$key] = @($sorted | Where-Object urgency -EQ $key)
    }

    $summary = [pscustomobject]@{
        expired = $groups.expired.Count
        warning = $groups.warning.Count
        ok      = $groups.ok.Count
        total   = $sorted.Count
    }

    [pscustomobject]@{
        referenceDate = ([datetime]$ReferenceDate).ToString('yyyy-MM-dd')
        warningDays   = $WarningDays
        summary       = $summary
        groups        = $groups
        secrets       = $sorted
    }
}

function Import-SecretConfig {
    <#
    .SYNOPSIS
        Load secret metadata from a JSON config file.
    .DESCRIPTION
        Accepts either a top-level JSON array of secrets, or an object with a
        top-level "secrets" array. Returns the array of secret objects. Errors
        (missing file, malformed JSON, unexpected shape) are reported with
        actionable messages.
    .PARAMETER Path
        Path to the JSON configuration file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Secret config file not found: '$Path'."
    }

    $raw = Get-Content -LiteralPath $Path -Raw
    try {
        $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Secret config file '$Path' contains invalid JSON: $($_.Exception.Message)"
    }

    # Accept both the bare-array form and the { "secrets": [...] } wrapper.
    $secrets =
        if ($null -ne $parsed -and ($parsed.PSObject.Properties.Name -contains 'secrets')) {
            $parsed.secrets
        }
        else {
            $parsed
        }

    if ($null -eq $secrets) {
        throw "Secret config file '$Path' did not contain any secrets."
    }

    return @($secrets)
}

function Format-RotationReport {
    <#
    .SYNOPSIS
        Render a rotation report as a markdown table or JSON document.
    .PARAMETER Report
        The report object produced by Get-SecretRotationReport.
    .PARAMETER Format
        Output format: 'markdown' (human-readable table grouped by urgency with
        a summary line) or 'json' (machine-readable, round-trippable).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Report,

        [Parameter(Mandatory)]
        [ValidateSet('markdown', 'json')]
        [string] $Format
    )

    switch ($Format) {
        'json' {
            # Depth 5 comfortably covers report -> groups -> secrets -> requiredBy.
            return ($Report | ConvertTo-Json -Depth 5)
        }
        'markdown' {
            $sb = [System.Text.StringBuilder]::new()
            [void]$sb.AppendLine("# Secret Rotation Report")
            [void]$sb.AppendLine()
            [void]$sb.AppendLine("Reference date: $($Report.referenceDate) | Warning window: $($Report.warningDays) day(s)")
            [void]$sb.AppendLine()
            # Summary line carries the per-urgency counts for at-a-glance triage.
            [void]$sb.AppendLine("Summary: Expired: $($Report.summary.expired) | Warning: $($Report.summary.warning) | OK: $($Report.summary.ok) | Total: $($Report.summary.total)")
            [void]$sb.AppendLine()

            if ($Report.summary.total -eq 0) {
                [void]$sb.AppendLine("_No secrets to report._")
                return $sb.ToString().TrimEnd()
            }

            # Table header.
            [void]$sb.AppendLine("| Secret | Urgency | Last Rotated | Due Date | Days Until Due | Required By |")
            [void]$sb.AppendLine("| ------ | ------- | ------------ | -------- | -------------- | ----------- |")
            foreach ($s in $Report.secrets) {
                $services = if ($s.requiredBy -and $s.requiredBy.Count -gt 0) { ($s.requiredBy -join ', ') } else { '-' }
                [void]$sb.AppendLine("| $($s.name) | $($s.urgency) | $($s.lastRotated) | $($s.dueDate) | $($s.daysUntilDue) | $services |")
            }
            return $sb.ToString().TrimEnd()
        }
    }
}

Export-ModuleMember -Function Get-SecretRotationStatus, Get-SecretRotationReport, Format-RotationReport, Import-SecretConfig
