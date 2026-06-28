#requires -Version 7.0
<#
    .SYNOPSIS
        Secret Rotation Validator - CLI entry point.

    .DESCRIPTION
        Loads a secrets configuration (name, last-rotated date, rotation policy in
        days, and the services that require each secret), classifies every secret as
        Expired / Warning / Ok relative to a (configurable) warning window, and emits:

          1. A single machine-parseable SUMMARY line.
          2. One NOTIFY line per secret, grouped by urgency (expired -> warning -> ok).
          3. The full rotation report in the requested format (Markdown or JSON),
             wrapped in <<<REPORT ...>>> / <<<END REPORT>>> delimiters so callers
             (and the CI pipeline) can extract it reliably.

        All date logic is anchored to -ReferenceDate (default: today) so behaviour is
        deterministic and testable. The script never touches real secret material; it
        only reasons about rotation metadata.

    .PARAMETER ConfigPath
        Path to the JSON secrets configuration file.

    .PARAMETER WarningDays
        Size of the warning window in days. Secrets expiring within this many days
        (but not yet expired) are flagged as Warning. Default: 14.

    .PARAMETER ReferenceDate
        The "now" used for all comparisons. Default: the current date.

    .PARAMETER Format
        Report output format: 'markdown' (default) or 'json'.

    .PARAMETER OutFile
        Optional path. When supplied, the formatted report is also written there.

    .PARAMETER FailOnExpired
        When set, the script exits with code 2 if any secret is expired. This lets a
        real CI pipeline gate on rotation hygiene. Off by default (reporting mode).

    .OUTPUTS
        Exit codes: 0 = success, 1 = error (bad/missing config), 2 = expired secrets
        found while -FailOnExpired was set.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ConfigPath,
    [int]$WarningDays = 14,
    [datetime]$ReferenceDate = (Get-Date),
    [ValidateSet('markdown', 'json')][string]$Format = 'markdown',
    [string]$OutFile,
    [switch]$FailOnExpired
)

# Stop on the first unhandled error so failures surface clearly in CI logs.
$ErrorActionPreference = 'Stop'

# Import the module that holds all the logic (resolved relative to this script so
# it works regardless of the caller's current directory).
$modulePath = Join-Path $PSScriptRoot 'src' 'SecretRotation.psm1'
Import-Module $modulePath -Force

try {
    # 1. Load + validate the configuration (throws a clear error on any problem).
    $config = Import-SecretConfig -Path $ConfigPath

    # 2. Build the structured report.
    $report = Get-RotationReport -Secrets $config.Secrets `
        -ReferenceDate $ReferenceDate -WarningDays $WarningDays
}
catch {
    # Surface a meaningful message and fail with a distinct non-zero code.
    Write-Error $_.Exception.Message
    exit 1
}

# 3. Machine-parseable summary line (stable token order for easy grepping).
$summary = $report.Summary
Write-Output ("SUMMARY expired={0} warning={1} ok={2} total={3}" -f `
    $summary.Expired, $summary.Warning, $summary.Ok, $summary.Total)

# 4. Notifications grouped by urgency.
foreach ($line in (Get-RotationNotification -Report $report)) {
    Write-Output $line
}

# 5. Formatted report, wrapped in delimiters for reliable extraction.
$moduleFormat = if ($Format -eq 'json') { 'Json' } else { 'Markdown' }
$rendered = Format-RotationReport -Report $report -Format $moduleFormat

Write-Output "<<<REPORT FORMAT=$Format>>>"
Write-Output $rendered
Write-Output "<<<END REPORT>>>"

# Optionally persist the rendered report to disk.
if ($OutFile) {
    $rendered | Set-Content -Path $OutFile -Encoding utf8
    Write-Output "Report written to $OutFile"
}

# If running inside GitHub Actions, attach the markdown report to the job summary.
if ($env:GITHUB_STEP_SUMMARY) {
    $forSummary = if ($moduleFormat -eq 'Markdown') {
        $rendered
    } else {
        Format-RotationReport -Report $report -Format 'Markdown'
    }
    Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value $forSummary
}

# 6. Decide the exit code. Default is "report only" (0). With -FailOnExpired, a
#    non-empty Expired bucket gates the build with code 2.
if ($FailOnExpired -and $summary.Expired -gt 0) {
    Write-Output "FAIL: $($summary.Expired) expired secret(s) found (-FailOnExpired)."
    exit 2
}

exit 0
