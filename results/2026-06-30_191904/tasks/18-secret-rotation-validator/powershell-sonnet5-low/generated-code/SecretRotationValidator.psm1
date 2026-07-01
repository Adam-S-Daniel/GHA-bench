<#
    SecretRotationValidator.psm1

    Evaluates mock secret metadata (name, last-rotated date, rotation policy,
    services that require it) against a rotation policy and produces a
    report grouped by urgency: Expired, Warning, Ok.
#>

function Get-SecretStatus {
    <#
        .SYNOPSIS
        Evaluates a single secret's rotation status.

        .DESCRIPTION
        Computes days remaining until a secret's rotation policy is exceeded
        (LastRotated + RotationPolicyDays) relative to -AsOf, and classifies
        it as Expired (past due), Warning (due within -WarningDays), or Ok.
    #>
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Secret,

        [Parameter(Mandatory)]
        [int]$WarningDays,

        [datetime]$AsOf = (Get-Date)
    )

    if (-not $Secret.Name) {
        throw "Secret is missing required 'Name' property."
    }
    if (-not $Secret.LastRotated) {
        throw "Secret '$($Secret.Name)' is missing required 'LastRotated' property."
    }
    if (-not $Secret.RotationPolicyDays) {
        throw "Secret '$($Secret.Name)' is missing required 'RotationPolicyDays' property."
    }

    $lastRotated = [datetime]$Secret.LastRotated
    $expiryDate = $lastRotated.AddDays([int]$Secret.RotationPolicyDays)
    $daysRemaining = [int]([math]::Floor(($expiryDate - $AsOf).TotalDays))

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
        ExpiryDate    = $expiryDate
        DaysRemaining = $daysRemaining
        RequiredBy    = $Secret.RequiredBy
        Status        = $status
    }
}

function Get-RotationReport {
    <#
        .SYNOPSIS
        Builds a rotation report for a collection of secrets, grouped by urgency.

        .DESCRIPTION
        Evaluates every secret with Get-SecretStatus and groups the results
        into Expired / Warning / Ok buckets, plus a Summary with counts.
    #>
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object[]]$Secrets,

        [Parameter(Mandatory)]
        [int]$WarningDays,

        [datetime]$AsOf = (Get-Date)
    )

    if ($null -eq $Secrets) {
        throw "Secrets parameter is required and cannot be null."
    }

    $evaluated = @($Secrets | ForEach-Object { Get-SecretStatus -Secret $_ -WarningDays $WarningDays -AsOf $AsOf })

    $expired = @($evaluated | Where-Object { $_.Status -eq 'Expired' })
    $warning = @($evaluated | Where-Object { $_.Status -eq 'Warning' })
    $ok      = @($evaluated | Where-Object { $_.Status -eq 'Ok' })

    [pscustomobject]@{
        Expired = $expired
        Warning = $warning
        Ok      = $ok
        Summary = [pscustomobject]@{
            ExpiredCount = $expired.Count
            WarningCount = $warning.Count
            OkCount      = $ok.Count
            TotalCount   = $evaluated.Count
        }
    }
}

function Format-RotationReport {
    <#
        .SYNOPSIS
        Renders a rotation report as Markdown or JSON.
    #>
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Report,

        [Parameter(Mandatory)]
        [ValidateSet('Markdown', 'Json')]
        [string]$Format
    )

    switch ($Format) {
        'Markdown' {
            $lines = @()
            $lines += '# Secret Rotation Report'
            $lines += ''
            $lines += "Expired: $($Report.Summary.ExpiredCount) | Warning: $($Report.Summary.WarningCount) | Ok: $($Report.Summary.OkCount) | Total: $($Report.Summary.TotalCount)"
            $lines += ''
            $lines += '| Name | Status | Days Remaining | Expiry Date | Required By |'
            $lines += '|------|--------|----------------|-------------|-------------|'

            foreach ($bucket in @('Expired', 'Warning', 'Ok')) {
                foreach ($secret in $Report.$bucket) {
                    $requiredBy = ($secret.RequiredBy -join ', ')
                    $expiry = $secret.ExpiryDate.ToString('yyyy-MM-dd')
                    $lines += "| $($secret.Name) | $($secret.Status) | $($secret.DaysRemaining) | $expiry | $requiredBy |"
                }
            }

            return ($lines -join "`n")
        }
        'Json' {
            return ($Report | ConvertTo-Json -Depth 6)
        }
        default {
            throw "Unsupported format '$Format'. Supported formats: Markdown, Json."
        }
    }
}

function Import-SecretConfig {
    <#
        .SYNOPSIS
        Loads a secret metadata configuration from a JSON file.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -Path $Path)) {
        throw "Secret config file not found: '$Path'."
    }

    $raw = Get-Content -Path $Path -Raw

    try {
        $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Failed to parse secret config file '$Path' as JSON: $($_.Exception.Message)"
    }

    return @($parsed)
}

Export-ModuleMember -Function Get-SecretStatus, Get-RotationReport, Format-RotationReport, Import-SecretConfig
