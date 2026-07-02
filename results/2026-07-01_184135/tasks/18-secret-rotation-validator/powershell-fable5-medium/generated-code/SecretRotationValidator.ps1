<#
.SYNOPSIS
    Secret rotation validator: flags secrets that are expired or expiring soon.

.DESCRIPTION
    Reads a JSON configuration of secrets (name, lastRotated date, rotationDays
    policy, requiredBy services), computes each secret's expiry date
    (lastRotated + rotationDays), and classifies it:

      expired : expiry date is on or before the reference date
      warning : expiry date falls within the warning window
      ok      : expiry date is beyond the warning window

    The report is emitted as a markdown table or JSON, grouped by urgency with
    the most urgent secrets first.

    Dot-source the script with no arguments to load just the functions (used
    by the Pester tests); pass -ConfigPath to run it as a CLI.

.PARAMETER ConfigPath
    Path to the JSON secrets configuration file.

.PARAMETER WarningWindowDays
    Secrets expiring within this many days are classified as 'warning'. Default 14.

.PARAMETER Format
    Output format: 'markdown' or 'json'. Default 'markdown'.

.PARAMETER ReferenceDate
    "Today" for all date math (ISO date string). Defaults to the current date.
    Injectable so tests and CI runs are deterministic.

.PARAMETER FailOnExpired
    Exit with code 2 if any secret is expired (useful as a CI gate).

.EXAMPLE
    ./SecretRotationValidator.ps1 -ConfigPath fixtures/secrets.json -Format markdown
#>
[CmdletBinding()]
param(
    [string]$ConfigPath,
    [int]$WarningWindowDays = 14,
    [ValidateSet('markdown', 'json')]
    [string]$Format = 'markdown',
    [string]$ReferenceDate,
    [switch]$FailOnExpired
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-SecretRotationStatus {
    <#
    .SYNOPSIS
        Computes expiry date, days remaining, and urgency for one secret.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object]$Secret,
        [Parameter(Mandatory)] [datetime]$ReferenceDate,
        [Parameter(Mandatory)] [int]$WarningWindowDays
    )

    $name = $Secret.name

    # Validate the rotation policy before doing any date math.
    if (-not ($Secret.rotationDays -is [int] -or $Secret.rotationDays -is [long]) -or $Secret.rotationDays -le 0) {
        throw "Secret '$name': rotationDays must be a positive integer (got '$($Secret.rotationDays)')."
    }

    $lastRotated = [datetime]::MinValue
    if (-not [datetime]::TryParse($Secret.lastRotated, [ref]$lastRotated)) {
        throw "Secret '$name': invalid lastRotated date '$($Secret.lastRotated)'. Expected an ISO date like 2026-01-31."
    }

    $expiry = $lastRotated.Date.AddDays($Secret.rotationDays)
    $daysRemaining = ($expiry - $ReferenceDate.Date).Days

    # Classification: expired at/after the deadline, warning inside the window
    # (inclusive at the window edge), ok otherwise.
    $urgency = if ($daysRemaining -le 0) { 'expired' }
               elseif ($daysRemaining -le $WarningWindowDays) { 'warning' }
               else { 'ok' }

    [pscustomobject]@{
        Name          = $name
        LastRotated   = $lastRotated.Date
        RotationDays  = [int]$Secret.rotationDays
        ExpiryDate    = $expiry
        DaysRemaining = $daysRemaining
        Urgency       = $urgency
        RequiredBy    = @($Secret.requiredBy)
    }
}

function Import-SecretConfig {
    <#
    .SYNOPSIS
        Loads and validates the secrets JSON configuration file.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string]$Path)

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        throw "Config file not found: $Path"
    }

    try {
        $config = Get-Content -Path $Path -Raw | ConvertFrom-Json
    }
    catch {
        throw "Config file '$Path' is not valid JSON: $($_.Exception.Message)"
    }

    if (-not ($config.PSObject.Properties.Name -contains 'secrets') -or $null -eq $config.secrets) {
        throw "Config file '$Path' must contain a 'secrets' array."
    }

    # Ensure every entry has the fields the validator needs; fail fast with
    # the secret's name so the config author knows exactly what to fix.
    $secrets = @($config.secrets)
    foreach ($secret in $secrets) {
        $props = $secret.PSObject.Properties.Name
        $label = if ($props -contains 'name') { $secret.name } else { '<unnamed>' }
        foreach ($field in 'name', 'lastRotated', 'rotationDays') {
            if ($props -notcontains $field) {
                throw "Secret '$label' is missing required field '$field'."
            }
        }
        # requiredBy is optional; default it to an empty list.
        if ($props -notcontains 'requiredBy') {
            $secret | Add-Member -NotePropertyName requiredBy -NotePropertyValue @()
        }
    }

    return $secrets
}

function Get-RotationReport {
    <#
    .SYNOPSIS
        Builds the full rotation report: statuses grouped by urgency plus summary counts.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object[]]$Secrets,
        [Parameter(Mandatory)] [datetime]$ReferenceDate,
        [Parameter(Mandatory)] [int]$WarningWindowDays
    )

    $statuses = foreach ($secret in $Secrets) {
        Get-SecretRotationStatus -Secret $secret -ReferenceDate $ReferenceDate -WarningWindowDays $WarningWindowDays
    }

    # Most urgent first within each group.
    $sorted = @($statuses | Sort-Object DaysRemaining)
    $expired = @($sorted | Where-Object Urgency -eq 'expired')
    $warning = @($sorted | Where-Object Urgency -eq 'warning')
    $ok      = @($sorted | Where-Object Urgency -eq 'ok')

    [pscustomobject]@{
        ReferenceDate     = $ReferenceDate.Date
        WarningWindowDays = $WarningWindowDays
        Expired           = $expired
        Warning           = $warning
        Ok                = $ok
        Summary           = [pscustomobject]@{
            Total   = $sorted.Count
            Expired = $expired.Count
            Warning = $warning.Count
            Ok      = $ok.Count
        }
    }
}

function ConvertTo-MarkdownReport {
    <#
    .SYNOPSIS
        Renders the report as a markdown table grouped by urgency.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [object]$Report)

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('# Secret Rotation Report')
    $lines.Add('')
    $lines.Add("Reference date: $($Report.ReferenceDate.ToString('yyyy-MM-dd')) | Warning window: $($Report.WarningWindowDays) days")
    $lines.Add('')
    $lines.Add('| Secret | Urgency | Expiry Date | Days Remaining | Required By |')
    $lines.Add('| --- | --- | --- | --- | --- |')

    # Emit expired first, then warning, then ok — already sorted within groups.
    foreach ($status in @($Report.Expired) + @($Report.Warning) + @($Report.Ok)) {
        $services = ($status.RequiredBy -join ', ')
        $lines.Add("| $($status.Name) | $($status.Urgency.ToUpper()) | $($status.ExpiryDate.ToString('yyyy-MM-dd')) | $($status.DaysRemaining) | $services |")
    }

    $s = $Report.Summary
    $lines.Add('')
    $lines.Add("**Summary:** $($s.Expired) expired, $($s.Warning) warning, $($s.Ok) ok ($($s.Total) total)")

    return ($lines -join [Environment]::NewLine)
}

function ConvertTo-JsonReport {
    <#
    .SYNOPSIS
        Renders the report as JSON grouped by urgency.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [object]$Report)

    # Project the internal status objects into a stable, camelCase JSON shape.
    $toJsonShape = {
        param($status)
        [ordered]@{
            name          = $status.Name
            lastRotated   = $status.LastRotated.ToString('yyyy-MM-dd')
            rotationDays  = $status.RotationDays
            expiryDate    = $status.ExpiryDate.ToString('yyyy-MM-dd')
            daysRemaining = $status.DaysRemaining
            requiredBy    = @($status.RequiredBy)
        }
    }

    $payload = [ordered]@{
        referenceDate     = $Report.ReferenceDate.ToString('yyyy-MM-dd')
        warningWindowDays = $Report.WarningWindowDays
        expired           = @($Report.Expired | ForEach-Object { & $toJsonShape $_ })
        warning           = @($Report.Warning | ForEach-Object { & $toJsonShape $_ })
        ok                = @($Report.Ok | ForEach-Object { & $toJsonShape $_ })
        summary           = [ordered]@{
            total   = $Report.Summary.Total
            expired = $Report.Summary.Expired
            warning = $Report.Summary.Warning
            ok      = $Report.Summary.Ok
        }
    }

    return ($payload | ConvertTo-Json -Depth 6)
}

# --- CLI entry point ---------------------------------------------------------
# Only runs when the script is invoked with -ConfigPath; dot-sourcing with no
# arguments just loads the functions above (how the tests consume this file).
if ($ConfigPath) {
    try {
        $refDate = if ($ReferenceDate) {
            $parsed = [datetime]::MinValue
            if (-not [datetime]::TryParse($ReferenceDate, [ref]$parsed)) {
                throw "Invalid -ReferenceDate '$ReferenceDate'. Expected an ISO date like 2026-07-01."
            }
            $parsed
        }
        else {
            (Get-Date).Date
        }

        $secrets = Import-SecretConfig -Path $ConfigPath
        $report = Get-RotationReport -Secrets $secrets -ReferenceDate $refDate -WarningWindowDays $WarningWindowDays

        switch ($Format) {
            'markdown' { ConvertTo-MarkdownReport -Report $report }
            'json'     { ConvertTo-JsonReport -Report $report }
        }

        # No 'exit 0' on success: when the script is invoked in-process from a
        # workflow step (shell: pwsh), an explicit exit would terminate the
        # whole step shell. Falling through yields exit code 0 naturally.
        if ($FailOnExpired -and $report.Summary.Expired -gt 0) {
            Write-Error -Message "$($report.Summary.Expired) secret(s) are expired and must be rotated." -ErrorAction Continue
            exit 2
        }
    }
    catch {
        Write-Error -Message "Secret rotation validation failed: $($_.Exception.Message)" -ErrorAction Continue
        exit 1
    }
}
