#requires -Version 7.0
<#
.SYNOPSIS
    Secret rotation validator.

.DESCRIPTION
    Reads a configuration of secrets (name, last-rotated date, rotation policy in
    days, and the services that require each secret), determines which secrets are
    expired or expiring within a configurable warning window, and emits a rotation
    report grouped by urgency (Expired / Warning / Ok) in either Markdown or JSON.

    The file is designed for testability:
      * Every unit of behaviour lives in its own function.
      * Functions take an explicit -ReferenceDate so "now" is injectable and tests
        stay deterministic.
      * The main entry point at the bottom only runs when the script is *invoked*
        (not when it is dot-sourced), so tests can dot-source it to get the
        functions without triggering execution.

.PARAMETER ConfigPath
    Path to the JSON secrets configuration file.

.PARAMETER WarningDays
    Size of the warning window in days. A secret whose expiry falls within this many
    days (inclusive) of the reference date is reported as a Warning.

.PARAMETER Format
    Output format: Markdown (default) or Json.

.PARAMETER ReferenceDate
    The date treated as "now". Defaults to the current date. Pinning this makes
    output deterministic for CI and tests.

.EXAMPLE
    ./SecretRotationValidator.ps1 -ConfigPath secrets.json -WarningDays 7 -Format Markdown
#>
[CmdletBinding()]
param(
    [string]$ConfigPath,
    [int]$WarningDays = 7,
    [ValidateSet('Markdown', 'Json')]
    [string]$Format = 'Markdown',
    [datetime]$ReferenceDate = (Get-Date)
)

Set-StrictMode -Version Latest

function ConvertFrom-SecretConfig {
    <#
    .SYNOPSIS
        Load and validate a JSON secrets configuration file.
    .DESCRIPTION
        Returns an array of normalised secret objects with the properties
        Name, LastRotated, RotationPolicyDays and RequiredBy. Throws a clear,
        actionable error if the file is missing, the JSON is malformed, or a
        required field is absent.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Secret configuration file not found: '$Path'"
    }

    $raw = Get-Content -LiteralPath $Path -Raw

    try {
        $config = $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Failed to parse JSON in '$Path': $($_.Exception.Message)"
    }

    # Accept either a top-level { "secrets": [...] } envelope or a bare array.
    $entries =
        if ($config.PSObject.Properties.Name -contains 'secrets') { $config.secrets }
        else { $config }

    if ($null -eq $entries) {
        throw "Configuration in '$Path' contains no 'secrets' array."
    }

    $required = 'name', 'lastRotated', 'rotationPolicyDays'
    $secrets = foreach ($entry in @($entries)) {
        foreach ($field in $required) {
            if (-not ($entry.PSObject.Properties.Name -contains $field)) {
                $who = if ($entry.PSObject.Properties.Name -contains 'name') { $entry.name } else { '<unnamed>' }
                throw "Secret '$who' in '$Path' is missing required field '$field'."
            }
        }

        [pscustomobject]@{
            Name               = [string]$entry.name
            LastRotated        = [string]$entry.lastRotated
            RotationPolicyDays = [int]$entry.rotationPolicyDays
            # requiredBy is optional; default to an empty list.
            RequiredBy         = if ($entry.PSObject.Properties.Name -contains 'requiredBy') { @($entry.requiredBy) } else { @() }
        }
    }

    return @($secrets)
}

function Get-SecretRotationStatus {
    <#
    .SYNOPSIS
        Compute the rotation status of each secret.
    .DESCRIPTION
        For every secret, derives the expiry date (last-rotated + policy days),
        the number of whole days until expiry relative to the reference date, and
        a Status of Expired (already past expiry), Warning (expiring within the
        warning window) or Ok. Validation errors name the offending secret.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Secrets,

        [int]$WarningDays = 7,

        [datetime]$ReferenceDate = (Get-Date)
    )

    foreach ($secret in $Secrets) {
        # Parse the last-rotated date, naming the secret on failure.
        [datetime]$lastRotated = [datetime]::MinValue
        if (-not [datetime]::TryParse([string]$secret.LastRotated, [ref]$lastRotated)) {
            throw "Secret '$($secret.Name)' has an invalid LastRotated value: '$($secret.LastRotated)'"
        }

        $policyDays = [int]$secret.RotationPolicyDays
        if ($policyDays -le 0) {
            throw "Secret '$($secret.Name)' has an invalid RotationPolicyDays value: '$policyDays' (must be a positive number)."
        }

        $expiryDate = $lastRotated.Date.AddDays($policyDays)
        # Whole-day difference so the status is independent of the time-of-day.
        $daysUntilExpiry = [int]($expiryDate - $ReferenceDate.Date).TotalDays

        $status =
            if ($daysUntilExpiry -lt 0) { 'Expired' }
            elseif ($daysUntilExpiry -le $WarningDays) { 'Warning' }
            else { 'Ok' }

        [pscustomobject]@{
            Name               = $secret.Name
            LastRotated        = $lastRotated.ToString('yyyy-MM-dd')
            RotationPolicyDays = $policyDays
            RequiredBy         = @($secret.RequiredBy)
            ExpiryDate         = $expiryDate
            DaysUntilExpiry    = $daysUntilExpiry
            Status             = $status
        }
    }
}

function New-RotationReport {
    <#
    .SYNOPSIS
        Group status objects by urgency and attach summary counts/metadata.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Statuses,

        [datetime]$ReferenceDate = (Get-Date),

        [int]$WarningDays = 7
    )

    $expired = @($Statuses | Where-Object Status -EQ 'Expired')
    $warning = @($Statuses | Where-Object Status -EQ 'Warning')
    $ok      = @($Statuses | Where-Object Status -EQ 'Ok')

    [pscustomobject]@{
        ReferenceDate = $ReferenceDate.ToString('yyyy-MM-dd')
        WarningDays   = $WarningDays
        Summary       = [pscustomobject]@{
            Expired = $expired.Count
            Warning = $warning.Count
            Ok      = $ok.Count
            Total   = $Statuses.Count
        }
        Expired = $expired
        Warning = $warning
        Ok      = $ok
    }
}

function Format-RotationReport {
    <#
    .SYNOPSIS
        Render a rotation report as Markdown or JSON.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Report,

        [ValidateSet('Markdown', 'Json')]
        [string]$Format = 'Markdown'
    )

    switch ($Format) {
        'Json' {
            return ($Report | ConvertTo-Json -Depth 6)
        }
        'Markdown' {
            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add('# Secret Rotation Report')
            $lines.Add('')
            $lines.Add("Reference date: $($Report.ReferenceDate)")
            $lines.Add("Warning window: $($Report.WarningDays) days")
            $lines.Add('')
            $lines.Add('## Summary')
            $lines.Add('')
            $lines.Add("- Expired: $($Report.Summary.Expired)")
            $lines.Add("- Warning: $($Report.Summary.Warning)")
            $lines.Add("- Ok: $($Report.Summary.Ok)")
            $lines.Add("- Total: $($Report.Summary.Total)")
            $lines.Add('')

            foreach ($group in 'Expired', 'Warning', 'Ok') {
                $lines.Add("## $group")
                $lines.Add('')
                $rows = @($Report.$group)
                if ($rows.Count -eq 0) {
                    $lines.Add('_None._')
                    $lines.Add('')
                    continue
                }
                $lines.Add('| Name | Last Rotated | Policy (days) | Expiry Date | Days Until Expiry | Required By |')
                $lines.Add('|------|--------------|---------------|-------------|-------------------|-------------|')
                foreach ($row in $rows) {
                    $requiredBy = (@($row.RequiredBy) -join ', ')
                    $expiry = $row.ExpiryDate.ToString('yyyy-MM-dd')
                    $lines.Add("| $($row.Name) | $($row.LastRotated) | $($row.RotationPolicyDays) | $expiry | $($row.DaysUntilExpiry) | $requiredBy |")
                }
                $lines.Add('')
            }

            return ($lines -join [Environment]::NewLine)
        }
        default {
            throw "Unsupported output format: '$Format'. Supported formats are Markdown and Json."
        }
    }
}

function Invoke-SecretRotationValidator {
    <#
    .SYNOPSIS
        End-to-end pipeline: load config -> compute status -> build report -> render.
    .DESCRIPTION
        Returns the rendered report string. Returns a non-throwing result so the
        caller (the main block) controls process exit codes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConfigPath,
        [int]$WarningDays = 7,
        [ValidateSet('Markdown', 'Json')]
        [string]$Format = 'Markdown',
        [datetime]$ReferenceDate = (Get-Date)
    )

    $secrets  = ConvertFrom-SecretConfig -Path $ConfigPath
    $statuses = @(Get-SecretRotationStatus -Secrets $secrets -WarningDays $WarningDays -ReferenceDate $ReferenceDate)
    $report   = New-RotationReport -Statuses $statuses -ReferenceDate $ReferenceDate -WarningDays $WarningDays
    return (Format-RotationReport -Report $report -Format $Format)
}

# --- Main entry point -------------------------------------------------------
# Only execute when this file is run directly (e.g. ./SecretRotationValidator.ps1),
# not when it is dot-sourced by the test suite. $MyInvocation.InvocationName is '.'
# during dot-sourcing.
if ($MyInvocation.InvocationName -ne '.' -and $MyInvocation.Line -notmatch '^\s*\.\s') {
    if (-not $ConfigPath) {
        Write-Error 'A -ConfigPath is required when running the validator.'
        exit 2
    }

    try {
        $output = Invoke-SecretRotationValidator -ConfigPath $ConfigPath -WarningDays $WarningDays -Format $Format -ReferenceDate $ReferenceDate
        Write-Output $output
        exit 0
    }
    catch {
        Write-Error "Secret rotation validation failed: $($_.Exception.Message)"
        exit 1
    }
}
