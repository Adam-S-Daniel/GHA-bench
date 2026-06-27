<#
.SYNOPSIS
    Secret Rotation Validator module.

.DESCRIPTION
    Provides functions to evaluate secret rotation metadata, classify each
    secret by urgency (expired / warning / ok), build a rotation report and
    render that report as a markdown table or JSON.

    The module is deliberately date-deterministic: callers always supply a
    reference date rather than reading the system clock, which keeps the
    classification logic pure and easy to test.
#>

Set-StrictMode -Version Latest

# Internal helper: parse a date string into a DateTime, normalised to midnight.
# Throws a clear, caller-facing error so date typos in config are easy to spot.
function ConvertTo-RotationDate {
    param(
        [Parameter(Mandatory)] [string] $Value,
        [Parameter(Mandatory)] [string] $FieldName
    )

    $parsed = [datetime]::MinValue
    # InvariantCulture + assume-universal keeps results stable across CI locales.
    $styles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor `
              [System.Globalization.DateTimeStyles]::AdjustToUniversal
    if (-not [datetime]::TryParse($Value, [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$parsed)) {
        throw "Invalid '$FieldName' date: '$Value'. Expected an ISO date such as 2026-01-31."
    }
    return $parsed.Date
}

function Get-SecretRotationStatus {
    <#
    .SYNOPSIS
        Classify a single secret as expired, warning or ok.

    .PARAMETER Secret
        An object with name, lastRotated, rotationPolicyDays and requiredBy.

    .PARAMETER ReferenceDate
        The "today" date used for the comparison (ISO string).

    .PARAMETER WarningWindowDays
        How many days ahead of the due date should be flagged as a warning.

    .OUTPUTS
        A status object describing the secret and its computed rotation state.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $Secret,
        [Parameter(Mandatory)] [string] $ReferenceDate,
        [Parameter(Mandatory)] [int]    $WarningWindowDays
    )

    if ($WarningWindowDays -lt 0) {
        throw "WarningWindowDays must be zero or positive, got '$WarningWindowDays'."
    }

    # Validate the policy before touching dates so the message is specific.
    $policy = $Secret.rotationPolicyDays
    if ($null -eq $policy -or [int]$policy -le 0) {
        throw "Secret '$($Secret.name)': rotationPolicyDays must be a positive integer, got '$policy'."
    }
    $policy = [int]$policy

    $lastRotated = ConvertTo-RotationDate -Value ([string]$Secret.lastRotated) -FieldName 'lastRotated'
    $reference   = ConvertTo-RotationDate -Value $ReferenceDate -FieldName 'ReferenceDate'

    # Due date = last rotation + policy window. daysUntilDue < 0 means overdue.
    $dueDate      = $lastRotated.AddDays($policy)
    $daysUntilDue = [int]($dueDate - $reference).TotalDays

    if ($daysUntilDue -lt 0) {
        $status = 'expired'
    }
    elseif ($daysUntilDue -le $WarningWindowDays) {
        $status = 'warning'
    }
    else {
        $status = 'ok'
    }

    # requiredBy may be absent; normalise to an array for stable downstream use.
    $requiredBy = @()
    if ($null -ne $Secret.PSObject.Properties['requiredBy'] -and $null -ne $Secret.requiredBy) {
        $requiredBy = @($Secret.requiredBy)
    }

    return [pscustomobject]@{
        name               = [string]$Secret.name
        status             = $status
        lastRotated        = $lastRotated.ToString('yyyy-MM-dd')
        rotationPolicyDays = $policy
        dueDate            = $dueDate.ToString('yyyy-MM-dd')
        daysUntilDue       = $daysUntilDue
        requiredBy         = $requiredBy
    }
}

function New-RotationReport {
    <#
    .SYNOPSIS
        Evaluate a collection of secrets and group them by urgency.

    .OUTPUTS
        A report object with expired/warning/ok arrays, a summary and the
        parameters used to produce it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Secrets,
        [Parameter(Mandatory)] [string] $ReferenceDate,
        [Parameter(Mandatory)] [int]    $WarningWindowDays
    )

    if ($null -eq $Secrets -or $Secrets.Count -eq 0) {
        throw 'No secrets provided to evaluate.'
    }

    $statuses = foreach ($s in $Secrets) {
        Get-SecretRotationStatus -Secret $s -ReferenceDate $ReferenceDate -WarningWindowDays $WarningWindowDays
    }

    # Most-urgent-first ordering within each bucket: expired by most overdue,
    # warning by soonest due. @(...) guarantees arrays even for single items.
    $expired = @($statuses | Where-Object status -eq 'expired' | Sort-Object daysUntilDue)
    $warning = @($statuses | Where-Object status -eq 'warning' | Sort-Object daysUntilDue)
    $ok      = @($statuses | Where-Object status -eq 'ok'      | Sort-Object daysUntilDue)

    return [pscustomobject]@{
        referenceDate     = $ReferenceDate
        warningWindowDays = $WarningWindowDays
        expired           = $expired
        warning           = $warning
        ok                = $ok
        summary           = [pscustomobject]@{
            expired = $expired.Count
            warning = $warning.Count
            ok      = $ok.Count
            total   = $statuses.Count
        }
    }
}

function Format-RotationReport {
    <#
    .SYNOPSIS
        Render a rotation report as JSON or as a markdown document.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $Report,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Format
    )

    switch ($Format.ToLowerInvariant()) {
        'json' {
            return ($Report | ConvertTo-Json -Depth 6)
        }
        'markdown' {
            return (Format-RotationReportMarkdown -Report $Report)
        }
        default {
            throw "Unsupported format '$Format'. Supported formats: markdown, json."
        }
    }
}

# Internal: build the markdown document. Kept separate so Format-RotationReport
# stays a thin dispatcher and the table rendering is independently testable.
function Format-RotationReportMarkdown {
    param([Parameter(Mandatory)] [object] $Report)

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('# Secret Rotation Report')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("Reference date: **$($Report.referenceDate)**  ")
    [void]$sb.AppendLine("Warning window: **$($Report.warningWindowDays)** days")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('## Summary')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("- **Expired:** $($Report.summary.expired)")
    [void]$sb.AppendLine("- **Warning:** $($Report.summary.warning)")
    [void]$sb.AppendLine("- **OK:** $($Report.summary.ok)")
    [void]$sb.AppendLine("- **Total:** $($Report.summary.total)")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('## Details')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('| Secret | Status | Last Rotated | Due Date | Days Until Due | Required By |')
    [void]$sb.AppendLine('| --- | --- | --- | --- | --- | --- |')

    # Render in urgency order so the most pressing rows surface at the top.
    foreach ($bucket in @($Report.expired, $Report.warning, $Report.ok)) {
        foreach ($row in $bucket) {
            $services = ($row.requiredBy -join ', ')
            [void]$sb.AppendLine("| $($row.name) | $($row.status) | $($row.lastRotated) | $($row.dueDate) | $($row.daysUntilDue) | $services |")
        }
    }

    return $sb.ToString().TrimEnd()
}

function Import-SecretConfig {
    <#
    .SYNOPSIS
        Load and validate a secrets config JSON file.

    .OUTPUTS
        The array of secret objects from the file's "secrets" property.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Config file not found: '$Path'."
    }

    $raw = Get-Content -LiteralPath $Path -Raw
    try {
        $config = $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Failed to parse config file '$Path' as JSON: $($_.Exception.Message)"
    }

    if ($null -eq $config.PSObject.Properties['secrets'] -or $null -eq $config.secrets) {
        throw "Config file '$Path' is missing a 'secrets' array."
    }

    return @($config.secrets)
}

Export-ModuleMember -Function Get-SecretRotationStatus, New-RotationReport, Format-RotationReport, Import-SecretConfig
