<#
.SYNOPSIS
    Secret rotation validation module.

.DESCRIPTION
    Classifies secrets (mock metadata: name, last-rotated date, rotation
    policy in days, required-by services) as Expired / Warning / OK relative
    to an as-of date and a configurable warning window.

    Approach:
      - expiry date  = LastRotated + RotationPolicyDays
      - days left    = (expiry - asOf).Days
      - days < 0                    -> Expired
      - 0 <= days <= warning window -> Warning
      - days > warning window       -> OK

    All functions accept -AsOfDate so behavior is deterministic and testable.
#>

Set-StrictMode -Version Latest

function Get-SecretRotationStatus {
    <#
    .SYNOPSIS
        Classify a single secret's rotation status.
    .OUTPUTS
        PSCustomObject with Name, Status, DaysUntilExpiry, ExpiresOn,
        LastRotated, RotationPolicyDays, RequiredBy.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Secret,
        [Parameter(Mandatory)] [datetime] $AsOfDate,
        [ValidateRange(0, 3650)] [int] $WarningWindowDays = 14
    )

    # Validate the rotation policy before doing any date math.
    if ($Secret.RotationPolicyDays -isnot [int] -and -not ($Secret.RotationPolicyDays -as [int])) {
        throw "Secret '$($Secret.Name)': RotationPolicyDays must be a positive integer (got '$($Secret.RotationPolicyDays)')."
    }
    $policyDays = [int]$Secret.RotationPolicyDays
    if ($policyDays -le 0) {
        throw "Secret '$($Secret.Name)': RotationPolicyDays must be a positive integer (got $policyDays)."
    }

    # Parse the last-rotated date strictly as an ISO yyyy-MM-dd string.
    $lastRotated = [datetime]::MinValue
    if (-not [datetime]::TryParseExact([string]$Secret.LastRotated, 'yyyy-MM-dd',
            [cultureinfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::None,
            [ref]$lastRotated)) {
        throw "Secret '$($Secret.Name)': invalid LastRotated date '$($Secret.LastRotated)' (expected yyyy-MM-dd)."
    }

    $expiresOn = $lastRotated.AddDays($policyDays)
    $daysUntilExpiry = ($expiresOn.Date - $AsOfDate.Date).Days

    $status = if ($daysUntilExpiry -lt 0) { 'Expired' }
              elseif ($daysUntilExpiry -le $WarningWindowDays) { 'Warning' }
              else { 'OK' }

    [pscustomobject]@{
        Name               = [string]$Secret.Name
        Status             = $status
        DaysUntilExpiry    = $daysUntilExpiry
        ExpiresOn          = $expiresOn.ToString('yyyy-MM-dd')
        LastRotated        = $lastRotated.ToString('yyyy-MM-dd')
        RotationPolicyDays = $policyDays
        RequiredBy         = @($Secret.RequiredBy)
    }
}

function Import-SecretConfig {
    <#
    .SYNOPSIS
        Load and validate the secrets configuration JSON file.
    .DESCRIPTION
        Validates file existence, JSON syntax, and per-secret required fields,
        then normalizes camelCase JSON keys to the PascalCase objects the rest
        of the module consumes. Fails fast with actionable error messages.
    .OUTPUTS
        PSCustomObject with WarningWindowDays and Secrets.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Config file not found: '$Path'. Provide a JSON file with a 'secrets' array."
    }

    try {
        $raw = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $Path -Raw) -ErrorAction Stop
    }
    catch {
        throw "Config file '$Path' is not valid JSON: $($_.Exception.Message)"
    }

    $hasSecrets = $raw.PSObject.Properties.Name -contains 'secrets' -and $null -ne $raw.secrets -and @($raw.secrets).Count -gt 0
    if (-not $hasSecrets) {
        throw "Config file '$Path' must contain a non-empty 'secrets' array."
    }

    $secrets = foreach ($entry in @($raw.secrets)) {
        $name = if ($entry.PSObject.Properties.Name -contains 'name') { [string]$entry.name } else { '<unnamed>' }
        foreach ($field in 'name', 'lastRotated', 'rotationPolicyDays') {
            if ($entry.PSObject.Properties.Name -notcontains $field -or [string]::IsNullOrWhiteSpace([string]$entry.$field)) {
                throw "Secret '$name' in '$Path' is missing required field '$field'."
            }
        }
        $requiredBy = if ($entry.PSObject.Properties.Name -contains 'requiredBy') { @($entry.requiredBy) } else { @() }
        [pscustomobject]@{
            Name               = [string]$entry.name
            LastRotated        = [string]$entry.lastRotated
            RotationPolicyDays = $entry.rotationPolicyDays
            RequiredBy         = $requiredBy
        }
    }

    $window = 14  # sensible default when the config omits warningWindowDays
    if ($raw.PSObject.Properties.Name -contains 'warningWindowDays' -and $null -ne $raw.warningWindowDays) {
        $window = [int]$raw.warningWindowDays
    }

    [pscustomobject]@{
        WarningWindowDays = $window
        Secrets           = @($secrets)
    }
}

function Get-RotationReport {
    <#
    .SYNOPSIS
        Evaluate all secrets in a config file and group results by urgency.
    .DESCRIPTION
        Loads the config, classifies every secret against -AsOfDate, and
        returns Expired / Warning / Ok buckets (each sorted by soonest expiry)
        plus summary counts. -WarningWindowDays overrides the config value.
    .OUTPUTS
        PSCustomObject with AsOfDate, WarningWindowDays, Expired, Warning,
        Ok, and Summary.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $ConfigPath,
        [datetime] $AsOfDate = (Get-Date),
        # -1 = "not specified, use the config file's value (or its default)"
        [ValidateRange(-1, 3650)] [int] $WarningWindowDays = -1
    )

    $config = Import-SecretConfig -Path $ConfigPath
    $window = if ($WarningWindowDays -ge 0) { $WarningWindowDays } else { $config.WarningWindowDays }

    $statuses = @($config.Secrets | ForEach-Object {
        Get-SecretRotationStatus -Secret $_ -AsOfDate $AsOfDate -WarningWindowDays $window
    }) | Sort-Object DaysUntilExpiry, Name  # most urgent first, stable tiebreak

    $expired = @($statuses | Where-Object Status -EQ 'Expired')
    $warning = @($statuses | Where-Object Status -EQ 'Warning')
    $ok      = @($statuses | Where-Object Status -EQ 'OK')

    [pscustomobject]@{
        AsOfDate          = $AsOfDate.ToString('yyyy-MM-dd')
        WarningWindowDays = $window
        Expired           = $expired
        Warning           = $warning
        Ok                = $ok
        Summary           = [pscustomobject]@{
            Total   = $statuses.Count
            Expired = $expired.Count
            Warning = $warning.Count
            Ok      = $ok.Count
        }
    }
}

function Format-RotationReport {
    <#
    .SYNOPSIS
        Render a rotation report as a markdown table or JSON.
    .DESCRIPTION
        Markdown: human-readable notification with one section per urgency
        group (EXPIRED, WARNING, OK), most urgent secrets first.
        Json: machine-readable payload with camelCase keys for downstream
        tooling (chat webhooks, dashboards, etc.).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Report,
        [Parameter(Mandatory)] [ValidateSet('Markdown', 'Json')] [string] $Format
    )

    switch ($Format) {
        'Json' {
            # camelCase keys so the payload looks idiomatic to JSON consumers.
            $toCamel = {
                param($s)
                [pscustomobject]@{
                    name               = $s.Name
                    status             = $s.Status
                    daysUntilExpiry    = $s.DaysUntilExpiry
                    expiresOn          = $s.ExpiresOn
                    lastRotated        = $s.LastRotated
                    rotationPolicyDays = $s.RotationPolicyDays
                    requiredBy         = @($s.RequiredBy)
                }
            }
            return [pscustomobject]@{
                asOfDate          = $Report.AsOfDate
                warningWindowDays = $Report.WarningWindowDays
                summary           = [pscustomobject]@{
                    total   = $Report.Summary.Total
                    expired = $Report.Summary.Expired
                    warning = $Report.Summary.Warning
                    ok      = $Report.Summary.Ok
                }
                expired           = @($Report.Expired | ForEach-Object { & $toCamel $_ })
                warning           = @($Report.Warning | ForEach-Object { & $toCamel $_ })
                ok                = @($Report.Ok      | ForEach-Object { & $toCamel $_ })
            } | ConvertTo-Json -Depth 5
        }
        'Markdown' {
            # Local helper: one markdown table (or a placeholder) per group.
            function Format-GroupSection {
                param([string] $Title, [object[]] $Secrets)
                $lines = @("## $Title", '')
                if ($Secrets.Count -eq 0) {
                    $lines += '_No secrets in this group._'
                }
                else {
                    $lines += '| Secret | Expires On | Days Until Expiry | Last Rotated | Policy (days) | Required By |'
                    $lines += '| --- | --- | --- | --- | --- | --- |'
                    foreach ($s in $Secrets) {
                        $requiredBy = if (@($s.RequiredBy).Count -gt 0) { @($s.RequiredBy) -join ', ' } else { '-' }
                        $lines += "| $($s.Name) | $($s.ExpiresOn) | $($s.DaysUntilExpiry) | $($s.LastRotated) | $($s.RotationPolicyDays) | $requiredBy |"
                    }
                }
                $lines + ''
            }

            $sum = $Report.Summary
            $out = @(
                '# Secret Rotation Report'
                ''
                "**As of:** $($Report.AsOfDate) | **Warning window:** $($Report.WarningWindowDays) days"
                ''
                "**Totals:** $($sum.Total) secrets — $($sum.Expired) expired, $($sum.Warning) warning, $($sum.Ok) ok"
                ''
            )
            $out += Format-GroupSection -Title "EXPIRED ($($sum.Expired)) — rotate immediately" -Secrets @($Report.Expired)
            $out += Format-GroupSection -Title "WARNING ($($sum.Warning)) — rotate soon"        -Secrets @($Report.Warning)
            $out += Format-GroupSection -Title "OK ($($sum.Ok))"                                -Secrets @($Report.Ok)
            return ($out -join [Environment]::NewLine)
        }
    }
}

Export-ModuleMember -Function Get-SecretRotationStatus, Import-SecretConfig, Get-RotationReport, Format-RotationReport
