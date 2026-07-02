# SecretRotationValidator.psm1
#
# Core module for the Secret Rotation Validator.
#
# Given mock secret metadata (name, last-rotated date, rotation policy in
# days, and the services that require the secret), this module determines
# whether each secret is Expired, in a Warning window, or Ok, then builds a
# rotation report grouped by urgency and renders it as Markdown or JSON.

function Get-SecretRotationStatus {
    <#
    .SYNOPSIS
        Computes the rotation status of a single secret.
    .DESCRIPTION
        A secret is due for rotation on (LastRotated + RotationPolicyDays).
        Relative to -Now, the secret is:
          - Expired  : the due date has already passed
          - Warning  : the due date falls within the next -WarningDays days
          - Ok       : otherwise
    #>
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Secret,

        [Parameter(Mandatory)]
        [int]$WarningDays,

        [Parameter(Mandatory)]
        [datetime]$Now
    )

    $dueDate = ([datetime]$Secret.LastRotated).AddDays($Secret.RotationPolicyDays)
    $daysUntilDue = [math]::Ceiling(($dueDate - $Now).TotalDays)

    if ($daysUntilDue -lt 0) {
        $status = 'Expired'
    }
    elseif ($daysUntilDue -le $WarningDays) {
        $status = 'Warning'
    }
    else {
        $status = 'Ok'
    }

    [PSCustomObject]@{
        Name               = $Secret.Name
        LastRotated        = [datetime]$Secret.LastRotated
        RotationPolicyDays = $Secret.RotationPolicyDays
        DueDate            = $dueDate
        DaysUntilDue       = $daysUntilDue
        RequiredBy         = $Secret.RequiredBy
        Status             = $status
    }
}

function Import-SecretConfig {
    <#
    .SYNOPSIS
        Loads and validates a JSON secret configuration file.
    .DESCRIPTION
        Each entry must define Name, LastRotated, RotationPolicyDays and
        RequiredBy. Errors raised here are meant to be read directly by
        whoever runs the pipeline, so they name the offending file/secret/field.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Secret configuration file not found: '$Path'"
    }

    $rawContent = Get-Content -LiteralPath $Path -Raw

    try {
        $parsed = $rawContent | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Secret configuration file '$Path' is not valid JSON: $($_.Exception.Message)"
    }

    $requiredFields = @('Name', 'LastRotated', 'RotationPolicyDays', 'RequiredBy')
    $secrets = @($parsed)

    foreach ($secret in $secrets) {
        $secretLabel = if ($secret.Name) { $secret.Name } else { '<unnamed secret>' }
        foreach ($field in $requiredFields) {
            if (-not (Get-Member -InputObject $secret -Name $field -MemberType NoteProperty)) {
                throw "Secret configuration entry '$secretLabel' in '$Path' is missing required field '$field'"
            }
        }
    }

    return $secrets
}

function New-RotationReport {
    <#
    .SYNOPSIS
        Builds a rotation report grouping secrets by urgency.
    .DESCRIPTION
        Runs every secret through Get-SecretRotationStatus and buckets the
        results into Expired / Warning / Ok, alongside summary counts.
    #>
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Secrets,

        [Parameter(Mandatory)]
        [int]$WarningDays,

        [Parameter(Mandatory)]
        [datetime]$Now
    )

    $statuses = @($Secrets | ForEach-Object {
        Get-SecretRotationStatus -Secret $_ -WarningDays $WarningDays -Now $Now
    })

    $expired = @($statuses | Where-Object { $_.Status -eq 'Expired' })
    $warning = @($statuses | Where-Object { $_.Status -eq 'Warning' })
    $ok = @($statuses | Where-Object { $_.Status -eq 'Ok' })

    [PSCustomObject]@{
        GeneratedAt = $Now
        WarningDays = $WarningDays
        Expired     = $expired
        Warning     = $warning
        Ok          = $ok
        Summary     = [PSCustomObject]@{
            Total        = $statuses.Count
            ExpiredCount = $expired.Count
            WarningCount = $warning.Count
            OkCount      = $ok.Count
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
        [PSCustomObject]$Report,

        [Parameter(Mandatory)]
        [ValidateSet('Markdown', 'Json')]
        [string]$Format
    )

    switch ($Format) {
        'Json' {
            return $Report | ConvertTo-Json -Depth 6
        }
        'Markdown' {
            $lines = New-Object System.Collections.Generic.List[string]
            $lines.Add('# Secret Rotation Report')
            $lines.Add('')
            $lines.Add("Generated: $($Report.GeneratedAt.ToString('yyyy-MM-dd'))  ")
            $lines.Add("Warning window: $($Report.WarningDays) day(s)")
            $lines.Add('')
            $lines.Add('## Summary')
            $lines.Add('')
            $lines.Add("- Expired: $($Report.Summary.ExpiredCount)")
            $lines.Add("- Warning: $($Report.Summary.WarningCount)")
            $lines.Add("- Ok: $($Report.Summary.OkCount)")

            foreach ($group in @(
                    @{ Title = 'Expired'; Items = $Report.Expired }
                    @{ Title = 'Warning'; Items = $Report.Warning }
                    @{ Title = 'Ok'; Items = $Report.Ok }
                )) {
                $lines.Add('')
                $lines.Add("## $($group.Title)")
                $lines.Add('')
                if (-not $group.Items -or $group.Items.Count -eq 0) {
                    $lines.Add('_None_')
                    continue
                }
                $lines.Add('| Name | Last Rotated | Due Date | Days Until Due | Required By |')
                $lines.Add('|------|---------------|----------|-----------------|-------------|')
                foreach ($item in $group.Items) {
                    $requiredBy = ($item.RequiredBy -join ', ')
                    $lastRotated = $item.LastRotated.ToString('yyyy-MM-dd')
                    $dueDate = $item.DueDate.ToString('yyyy-MM-dd')
                    $lines.Add("| $($item.Name) | $lastRotated | $dueDate | $($item.DaysUntilDue) | $requiredBy |")
                }
            }

            return ($lines -join [Environment]::NewLine)
        }
    }
}

function Invoke-SecretRotationCheck {
    <#
    .SYNOPSIS
        End-to-end entry point: load config, build the report, render it.
    .DESCRIPTION
        This is the function the CI script calls. It wires together
        Import-SecretConfig, New-RotationReport and Format-RotationReport,
        and optionally fails (throws) when expired secrets are found so a
        pipeline can turn that into a non-zero exit code via -FailOnExpired.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ConfigPath,

        [int]$WarningDays = 14,

        [ValidateSet('Markdown', 'Json')]
        [string]$OutputFormat = 'Markdown',

        [datetime]$Now = (Get-Date),

        [switch]$FailOnExpired
    )

    $secrets = Import-SecretConfig -Path $ConfigPath
    $report = New-RotationReport -Secrets $secrets -WarningDays $WarningDays -Now $Now
    $formatted = Format-RotationReport -Report $report -Format $OutputFormat

    if ($FailOnExpired -and $report.Summary.ExpiredCount -gt 0) {
        throw "Secret rotation check failed: $($report.Summary.ExpiredCount) secret(s) have expired rotation policies."
    }

    return $formatted
}

Export-ModuleMember -Function Get-SecretRotationStatus, Import-SecretConfig, New-RotationReport, Format-RotationReport, Invoke-SecretRotationCheck
