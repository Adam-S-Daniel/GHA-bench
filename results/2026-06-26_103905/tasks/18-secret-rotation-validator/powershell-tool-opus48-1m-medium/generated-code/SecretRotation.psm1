<#
.SYNOPSIS
    Secret Rotation Validator module.

.DESCRIPTION
    Given a set of secrets with rotation metadata (name, last-rotated date,
    rotation policy in days, and the services that require them), this module
    classifies each secret by urgency (expired / warning / ok), builds a
    grouped rotation report, and renders that report as either a markdown
    table or JSON.

    The module is intentionally side-effect free: all "now" values are passed
    in as -ReferenceDate so the behaviour is deterministic and testable.
#>

Set-StrictMode -Version Latest

function Get-SecretRotationStatus {
    <#
    .SYNOPSIS
        Classify a single secret as expired / warning / ok.

    .DESCRIPTION
        Computes the expiry date (lastRotated + rotationPolicyDays) and the
        number of whole days from the reference date until expiry, then maps
        that to an urgency status:
          - daysUntilExpiry  < 0                -> expired
          - 0 <= daysUntilExpiry <= WarningDays -> warning
          - daysUntilExpiry  > WarningDays      -> ok
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Secret,

        [Parameter(Mandatory)]
        [datetime]$ReferenceDate,

        [Parameter(Mandatory)]
        [int]$WarningDays
    )

    # --- Validate the policy window -------------------------------------------------
    $policyDays = $Secret.rotationPolicyDays
    if ($null -eq $policyDays -or [int]$policyDays -le 0) {
        throw "Secret '$($Secret.name)': rotationPolicyDays must be a positive integer (got '$policyDays')."
    }

    # --- Validate / parse the last-rotated date -------------------------------------
    $lastRotated = [datetime]::MinValue
    if (-not [datetime]::TryParse([string]$Secret.lastRotated, [ref]$lastRotated)) {
        throw "Secret '$($Secret.name)': lastRotated '$($Secret.lastRotated)' is not a valid date."
    }

    # --- Core calculation -----------------------------------------------------------
    $expiryDate = $lastRotated.AddDays([int]$policyDays)
    # Use whole-day granularity from the (date-only) reference point.
    $daysUntilExpiry = [int]([math]::Floor(($expiryDate.Date - $ReferenceDate.Date).TotalDays))

    if ($daysUntilExpiry -lt 0) {
        $status = 'expired'
    } elseif ($daysUntilExpiry -le $WarningDays) {
        $status = 'warning'
    } else {
        $status = 'ok'
    }

    # Normalise requiredBy to an array so downstream formatting is predictable.
    $requiredBy = @()
    if ($null -ne $Secret.requiredBy) {
        $requiredBy = @($Secret.requiredBy)
    }

    [pscustomobject]@{
        name            = $Secret.name
        lastRotated     = $lastRotated.ToString('yyyy-MM-dd')
        rotationPolicyDays = [int]$policyDays
        expiryDate      = $expiryDate.ToString('yyyy-MM-dd')
        daysUntilExpiry = $daysUntilExpiry
        status          = $status
        requiredBy      = $requiredBy
    }
}

function New-RotationReport {
    <#
    .SYNOPSIS
        Build a rotation report grouping secrets by urgency.

    .DESCRIPTION
        Classifies every secret with Get-SecretRotationStatus, groups the
        results into expired / warning / ok buckets, sorts each bucket so the
        most urgent items appear first, and attaches summary counts.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Secrets,

        [Parameter(Mandatory)]
        [datetime]$ReferenceDate,

        [Parameter(Mandatory)]
        [int]$WarningDays
    )

    if ($null -eq $Secrets -or $Secrets.Count -eq 0) {
        throw "Cannot build a rotation report: no secrets were provided."
    }

    # Classify every secret.
    $classified = foreach ($s in $Secrets) {
        Get-SecretRotationStatus -Secret $s -ReferenceDate $ReferenceDate -WarningDays $WarningDays
    }

    # Group by urgency. Sort each bucket by daysUntilExpiry ascending so the
    # most overdue (expired) / soonest-to-expire (warning) items lead.
    $expired = @($classified | Where-Object { $_.status -eq 'expired' } | Sort-Object daysUntilExpiry)
    $warning = @($classified | Where-Object { $_.status -eq 'warning' } | Sort-Object daysUntilExpiry)
    $ok      = @($classified | Where-Object { $_.status -eq 'ok' }      | Sort-Object daysUntilExpiry)

    [pscustomobject]@{
        generatedAt = $ReferenceDate.ToString('yyyy-MM-dd')
        warningDays = $WarningDays
        expired     = $expired
        warning     = $warning
        ok          = $ok
        summary     = [pscustomobject]@{
            total   = $classified.Count
            expired = $expired.Count
            warning = $warning.Count
            ok      = $ok.Count
        }
    }
}

function Format-RotationReport {
    <#
    .SYNOPSIS
        Render a rotation report as markdown or JSON.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Report,

        [Parameter(Mandatory)]
        [ValidateSet('markdown', 'json')]
        [string]$Format
    )

    switch ($Format) {
        'json' {
            return ($Report | ConvertTo-Json -Depth 6)
        }
        'markdown' {
            return (Format-RotationReportMarkdown -Report $Report)
        }
        default {
            # ValidateSet normally prevents this, but keep an explicit guard.
            throw "Unsupported output format: '$Format'. Supported formats are: markdown, json."
        }
    }
}

function Format-RotationReportMarkdown {
    <#
    .SYNOPSIS
        Internal helper: build the markdown table representation.
    #>
    param([object]$Report)

    $sb = [System.Text.StringBuilder]::new()

    [void]$sb.AppendLine("# Secret Rotation Report")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("Generated: $($Report.generatedAt) (warning window: $($Report.warningDays) days)")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("Summary: $($Report.summary.expired) expired, $($Report.summary.warning) warning, $($Report.summary.ok) ok ($($Report.summary.total) total)")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("| Secret | Status | Days Until Expiry | Required By |")
    [void]$sb.AppendLine("| --- | --- | --- | --- |")

    # Emit rows in urgency order so the most important secrets are at the top.
    foreach ($bucket in @($Report.expired, $Report.warning, $Report.ok)) {
        foreach ($item in $bucket) {
            $required = ($item.requiredBy -join ', ')
            [void]$sb.AppendLine("| $($item.name) | $($item.status) | $($item.daysUntilExpiry) | $required |")
        }
    }

    return $sb.ToString().TrimEnd()
}

function Import-SecretConfig {
    <#
    .SYNOPSIS
        Load secrets from a JSON config file.

    .DESCRIPTION
        Reads a JSON file of the shape { "secrets": [ { name, lastRotated,
        rotationPolicyDays, requiredBy }, ... ] } and returns the secrets
        array. Errors (missing file, malformed JSON) are surfaced with
        meaningful messages.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Secret config file not found: '$Path'."
    }

    $raw = Get-Content -LiteralPath $Path -Raw

    try {
        $config = $raw | ConvertFrom-Json
    } catch {
        throw "Failed to parse secret config '$Path' as JSON: $($_.Exception.Message)"
    }

    if ($null -eq $config.secrets) {
        throw "Secret config '$Path' is missing a top-level 'secrets' array."
    }

    return @($config.secrets)
}

function Invoke-SecretRotationValidator {
    <#
    .SYNOPSIS
        End-to-end convenience entry point: load config, build report, format.

    .DESCRIPTION
        Combines Import-SecretConfig, New-RotationReport and
        Format-RotationReport. Returns the formatted report string.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConfigPath,

        [int]$WarningDays = 14,

        [ValidateSet('markdown', 'json')]
        [string]$Format = 'markdown',

        [datetime]$ReferenceDate = [datetime]::Today
    )

    $secrets = Import-SecretConfig -Path $ConfigPath
    $report  = New-RotationReport -Secrets $secrets -ReferenceDate $ReferenceDate -WarningDays $WarningDays
    return (Format-RotationReport -Report $report -Format $Format)
}

Export-ModuleMember -Function Get-SecretRotationStatus, New-RotationReport,
    Format-RotationReport, Import-SecretConfig, Invoke-SecretRotationValidator
