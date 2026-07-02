<#
    .SYNOPSIS
    CLI entry point for the Secret Rotation Validator. Wraps the
    SecretRotationValidator module for use as a CI pipeline step.
#>
param(
    [string]$ConfigPath = "$PSScriptRoot/fixtures/sample-secrets.json",
    [int]$WarningDays = 7,
    [ValidateSet('Markdown', 'Json')] [string]$OutputFormat = 'Markdown',
    [switch]$FailOnExpired,
    # Defaults to today, but callers (including CI fixture runs) can pin an
    # explicit date so output is deterministic and reproducible.
    [datetime]$CurrentDate = (Get-Date)
)

Import-Module "$PSScriptRoot/src/SecretRotationValidator.psm1" -Force

try {
    $result = Invoke-SecretRotationValidator -ConfigPath $ConfigPath -WarningDays $WarningDays -OutputFormat $OutputFormat -CurrentDate $CurrentDate -FailOnExpired:$FailOnExpired
}
catch {
    Write-Error "Secret rotation validation failed: $($_.Exception.Message)"
    exit 1
}

Write-Output $result.Output
exit $result.ExitCode
