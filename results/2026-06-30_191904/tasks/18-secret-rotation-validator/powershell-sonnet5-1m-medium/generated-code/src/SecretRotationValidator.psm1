# SecretRotationValidator.psm1
# Core logic for evaluating mock secret metadata against rotation policies
# and producing grouped, formatted rotation reports.

function Get-SecretRotationStatus {
    <#
        Evaluates a single secret's rotation status against its policy.
        Status is Expired (past due), Warning (due within WarningDays), or Ok.
    #>
    param(
        [Parameter(Mandatory)] [pscustomobject]$Secret,
        [Parameter(Mandatory)] [datetime]$CurrentDate,
        [Parameter(Mandatory)] [int]$WarningDays
    )

    $lastRotated = [datetime]$Secret.LastRotated
    $daysSinceRotation = ($CurrentDate - $lastRotated).Days
    $daysRemaining = $Secret.RotationDays - $daysSinceRotation

    if ($daysRemaining -lt 0) {
        $status = 'Expired'
    }
    elseif ($daysRemaining -le $WarningDays) {
        $status = 'Warning'
    }
    else {
        $status = 'Ok'
    }

    [pscustomobject]@{
        Name          = $Secret.Name
        LastRotated   = $lastRotated
        RotationDays  = $Secret.RotationDays
        RequiredBy    = $Secret.RequiredBy
        DaysRemaining = $daysRemaining
        Status        = $status
    }
}

function Import-SecretConfig {
    <#
        Loads secret metadata from a JSON configuration file.
        The file is expected to contain a top-level "secrets" array.
    #>
    param(
        [Parameter(Mandatory)] [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Secret configuration file not found: $Path"
    }

    $raw = Get-Content -LiteralPath $Path -Raw
    try {
        $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Secret configuration file '$Path' contains invalid JSON: $($_.Exception.Message)"
    }

    if (-not $parsed.secrets) {
        throw "Secret configuration file '$Path' is missing a top-level 'secrets' array."
    }

    return @($parsed.secrets)
}

function New-RotationReport {
    <#
        Evaluates every secret and groups the results into Expired, Warning,
        and Ok buckets, producing a single report object.
    #>
    param(
        [Parameter(Mandatory)] [array]$Secrets,
        [Parameter(Mandatory)] [datetime]$CurrentDate,
        [Parameter(Mandatory)] [int]$WarningDays
    )

    $evaluated = foreach ($secret in $Secrets) {
        Get-SecretRotationStatus -Secret $secret -CurrentDate $CurrentDate -WarningDays $WarningDays
    }

    [pscustomobject]@{
        GeneratedAt = $CurrentDate
        WarningDays = $WarningDays
        Expired     = @($evaluated | Where-Object { $_.Status -eq 'Expired' })
        Warning     = @($evaluated | Where-Object { $_.Status -eq 'Warning' })
        Ok          = @($evaluated | Where-Object { $_.Status -eq 'Ok' })
    }
}

function Format-RotationReport {
    <#
        Renders a rotation report as either a Markdown document (with
        per-urgency sections and tables) or a JSON document.
    #>
    param(
        [Parameter(Mandatory)] [pscustomobject]$Report,
        [Parameter(Mandatory)] [ValidateSet('Markdown', 'Json')] [string]$Format
    )

    if ($Format -eq 'Json') {
        return $Report | ConvertTo-Json -Depth 6
    }

    function Format-SectionTable {
        param([array]$Items)

        if ($Items.Count -eq 0) {
            return "_None_`n"
        }

        $lines = @('| Name | Last Rotated | Rotation Days | Days Remaining | Required By |', '| --- | --- | --- | --- | --- |')
        foreach ($item in $Items) {
            $requiredBy = ($item.RequiredBy -join ', ')
            $lastRotated = $item.LastRotated.ToString('yyyy-MM-dd')
            $lines += "| $($item.Name) | $lastRotated | $($item.RotationDays) | $($item.DaysRemaining) | $requiredBy |"
        }
        return ($lines -join "`n")
    }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("# Secret Rotation Report")
    [void]$sb.AppendLine("Generated: $($Report.GeneratedAt.ToString('yyyy-MM-dd')) | Warning window: $($Report.WarningDays) days")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## Expired')
    [void]$sb.AppendLine((Format-SectionTable -Items $Report.Expired))
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## Warning')
    [void]$sb.AppendLine((Format-SectionTable -Items $Report.Warning))
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## Ok')
    [void]$sb.AppendLine((Format-SectionTable -Items $Report.Ok))

    return $sb.ToString()
}

function Invoke-SecretRotationValidator {
    <#
        End-to-end entry point: loads the config, builds the report, formats
        it, and returns an object with the rendered output and an exit code
        suitable for use in a CI pipeline.
    #>
    param(
        [Parameter(Mandatory)] [string]$ConfigPath,
        [int]$WarningDays = 7,
        [ValidateSet('Markdown', 'Json')] [string]$OutputFormat = 'Markdown',
        [datetime]$CurrentDate = (Get-Date),
        [switch]$FailOnExpired
    )

    $secrets = Import-SecretConfig -Path $ConfigPath
    $report = New-RotationReport -Secrets $secrets -CurrentDate $CurrentDate -WarningDays $WarningDays
    $output = Format-RotationReport -Report $report -Format $OutputFormat

    $exitCode = 0
    if ($FailOnExpired -and $report.Expired.Count -gt 0) {
        $exitCode = 1
    }

    [pscustomobject]@{
        Report   = $report
        Output   = $output
        ExitCode = $exitCode
    }
}

Export-ModuleMember -Function Get-SecretRotationStatus, Import-SecretConfig, New-RotationReport, Format-RotationReport, Invoke-SecretRotationValidator
