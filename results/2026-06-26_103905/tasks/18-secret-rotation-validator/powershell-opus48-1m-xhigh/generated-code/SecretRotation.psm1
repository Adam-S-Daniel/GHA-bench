<#
.SYNOPSIS
    Secret Rotation Validator core library.

.DESCRIPTION
    Given a configuration of secrets with metadata (name, last-rotated date,
    rotation policy in days, required-by services), this module classifies each
    secret by urgency relative to a reference "as-of" date and a configurable
    warning window, builds a rotation report, and renders that report as either
    a markdown table or JSON.

    Classification rule (relative to the as-of date):
        daysUntilExpiry  = (lastRotated + rotationPolicyDays) - asOf   (in days)
        daysUntilExpiry < 0                       -> 'expired'
        0 <= daysUntilExpiry <= warningWindowDays -> 'warning'
        daysUntilExpiry > warningWindowDays       -> 'ok'

    A deadline that falls exactly on the as-of date (0 days remaining) is a
    'warning', not 'expired' -- the secret expires today but has not yet lapsed.

    The "as-of" date is always an explicit input so behaviour is deterministic
    and never depends on the wall clock. The CLI defaults it to the current day.

    No real secret material is ever read; the module operates purely on metadata.
#>

Set-StrictMode -Version Latest

# Canonical urgency buckets, ordered most-urgent first. Used for grouping and
# for stable iteration order in reports.
$script:UrgencyOrder = @('expired', 'warning', 'ok')

function ConvertTo-Date {
    <#
    .SYNOPSIS
        Parse an ISO-style (yyyy-MM-dd) date string into a [datetime], failing
        with a clear message rather than a cryptic format exception.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowNull()] $Value,
        [Parameter(Mandatory)] [string] $FieldName
    )

    if ($null -eq $Value -or "$Value".Trim() -eq '') {
        throw "Missing required date field '$FieldName'."
    }

    # Accept a real datetime (e.g. when callers pass [datetime]) as-is.
    if ($Value -is [datetime]) { return $Value }

    [datetime]$parsed = [datetime]::MinValue
    $styles = [System.Globalization.DateTimeStyles]::None
    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    # Restrict to the unambiguous yyyy-MM-dd form so '01/02/2025' style strings
    # cannot be silently misinterpreted across locales.
    if (-not [datetime]::TryParseExact("$Value", 'yyyy-MM-dd', $culture, $styles, [ref]$parsed)) {
        throw "Invalid date for field '$FieldName': '$Value'. Expected format yyyy-MM-dd."
    }
    return $parsed
}

function Get-SecretStatus {
    <#
    .SYNOPSIS
        Classify a single secret's rotation urgency relative to a reference date.

    .PARAMETER Secret
        An object with: name, lastRotated (yyyy-MM-dd), rotationPolicyDays (int),
        requiredBy (string[]).

    .PARAMETER AsOf
        Reference date (yyyy-MM-dd string or [datetime]) the calculation is made
        against.

    .PARAMETER WarningWindowDays
        Number of days before expiry within which a secret is flagged 'warning'.

    .OUTPUTS
        A [pscustomobject] with name, lastRotated, rotationPolicyDays, requiredBy,
        expiresOn (yyyy-MM-dd), daysUntilExpiry (int), and status.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $Secret,
        [Parameter(Mandatory)] $AsOf,
        [Parameter(Mandatory)] [int] $WarningWindowDays
    )

    if ($WarningWindowDays -lt 0) {
        throw "WarningWindowDays must be zero or positive (got $WarningWindowDays)."
    }

    # --- validate and normalise the secret's fields -----------------------
    if (-not ($Secret.PSObject.Properties.Name -contains 'name') -or [string]::IsNullOrWhiteSpace($Secret.name)) {
        throw "Secret is missing a non-empty 'name'."
    }
    $name = [string]$Secret.name

    if (-not ($Secret.PSObject.Properties.Name -contains 'rotationPolicyDays')) {
        throw "Secret '$name' is missing 'rotationPolicyDays'."
    }
    $policyDays = 0
    if (-not [int]::TryParse("$($Secret.rotationPolicyDays)", [ref]$policyDays)) {
        throw "Secret '$name' has a non-integer 'rotationPolicyDays': '$($Secret.rotationPolicyDays)'."
    }
    if ($policyDays -le 0) {
        throw "Secret '$name' has a non-positive 'rotationPolicyDays': $policyDays."
    }

    $lastRotated = ConvertTo-Date -Value $Secret.lastRotated -FieldName "lastRotated (secret '$name')"
    $asOfDate    = ConvertTo-Date -Value $AsOf -FieldName 'AsOf'

    # requiredBy is optional; normalise to a string array.
    $requiredBy = @()
    if (($Secret.PSObject.Properties.Name -contains 'requiredBy') -and $null -ne $Secret.requiredBy) {
        $requiredBy = @($Secret.requiredBy | ForEach-Object { [string]$_ })
    }

    # --- compute deadline and urgency -------------------------------------
    $expiresOn = $lastRotated.AddDays($policyDays)
    # Compare whole calendar days so the result is independent of clock time.
    $daysUntilExpiry = [int][math]::Floor(($expiresOn.Date - $asOfDate.Date).TotalDays)

    $status =
        if     ($daysUntilExpiry -lt 0)                  { 'expired' }
        elseif ($daysUntilExpiry -le $WarningWindowDays) { 'warning' }
        else                                             { 'ok' }

    return [pscustomobject]@{
        name               = $name
        lastRotated        = $lastRotated.ToString('yyyy-MM-dd')
        rotationPolicyDays = $policyDays
        requiredBy         = $requiredBy
        expiresOn          = $expiresOn.ToString('yyyy-MM-dd')
        daysUntilExpiry    = $daysUntilExpiry
        status             = $status
    }
}

function Import-SecretConfig {
    <#
    .SYNOPSIS
        Read and validate a secrets configuration JSON file.

    .DESCRIPTION
        The config is a JSON object with:
          - secrets            (required) array of secret metadata objects
          - warningWindowDays  (optional) default warning window
          - asOf               (optional) default reference date (yyyy-MM-dd)

        Returns a [pscustomobject] mirroring the file. Each malformed-input case
        throws a specific, actionable error.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Config file not found: '$Path'."
    }

    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "Config file '$Path' is empty."
    }

    try {
        $config = $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Failed to parse JSON in '$Path': $($_.Exception.Message)"
    }

    if ($null -eq $config -or -not ($config.PSObject.Properties.Name -contains 'secrets')) {
        throw "Config '$Path' must contain a 'secrets' array."
    }
    if ($null -eq $config.secrets) {
        throw "Config '$Path' has a null 'secrets' value; expected an array."
    }

    return $config
}

function Get-RotationReport {
    <#
    .SYNOPSIS
        Build a structured rotation report from a config object.

    .PARAMETER Config
        A config object exposing .secrets (array) and optionally .warningWindowDays
        and .asOf. Typically produced by Import-SecretConfig.

    .PARAMETER WarningWindowDays
        Overrides the config's warning window. Falls back to the config value,
        then to a 30-day default.

    .PARAMETER AsOf
        Overrides the config's reference date. Falls back to the config value,
        then to today's date.

    .PARAMETER Label
        Optional free-text label (e.g. a fixture name) recorded on the report and
        useful for downstream identification.

    .OUTPUTS
        A [pscustomobject] with asOf, warningWindowDays, label, generatedAt,
        summary (expired/warning/ok/total), groups (by urgency), and secrets
        (flat, sorted most-urgent first).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $Config,
        [int] $WarningWindowDays,
        $AsOf,
        [string] $Label = ''
    )

    if ($null -eq $Config -or -not ($Config.PSObject.Properties.Name -contains 'secrets')) {
        throw "Config object must expose a 'secrets' collection."
    }

    # --- resolve effective settings: parameter > config > default ---------
    $effectiveWindow =
        if ($PSBoundParameters.ContainsKey('WarningWindowDays')) { $WarningWindowDays }
        elseif (($Config.PSObject.Properties.Name -contains 'warningWindowDays') -and $null -ne $Config.warningWindowDays) { [int]$Config.warningWindowDays }
        else { 30 }

    $effectiveAsOf =
        if ($PSBoundParameters.ContainsKey('AsOf') -and $null -ne $AsOf) { $AsOf }
        elseif (($Config.PSObject.Properties.Name -contains 'asOf') -and $null -ne $Config.asOf -and "$($Config.asOf)".Trim() -ne '') { $Config.asOf }
        else { (Get-Date).ToString('yyyy-MM-dd') }

    $asOfDate = ConvertTo-Date -Value $effectiveAsOf -FieldName 'AsOf'

    # --- classify every secret --------------------------------------------
    $statuses = foreach ($secret in @($Config.secrets)) {
        Get-SecretStatus -Secret $secret -AsOf $asOfDate -WarningWindowDays $effectiveWindow
    }
    $statuses = @($statuses)

    # --- group + sort (most urgent first within each bucket) --------------
    $groups = [ordered]@{}
    foreach ($bucket in $script:UrgencyOrder) {
        $groups[$bucket] = @(
            $statuses |
                Where-Object { $_.status -eq $bucket } |
                Sort-Object -Property daysUntilExpiry, name
        )
    }

    $summary = [pscustomobject]@{
        expired = @($groups['expired']).Count
        warning = @($groups['warning']).Count
        ok      = @($groups['ok']).Count
        total   = $statuses.Count
    }

    # Flat list ordered expired -> warning -> ok, each bucket most-urgent first.
    $orderedSecrets = @()
    foreach ($bucket in $script:UrgencyOrder) { $orderedSecrets += $groups[$bucket] }

    return [pscustomobject]@{
        label             = $Label
        asOf              = $asOfDate.ToString('yyyy-MM-dd')
        warningWindowDays = $effectiveWindow
        summary           = $summary
        groups            = [pscustomobject]$groups
        secrets           = @($orderedSecrets)
    }
}

function Format-RotationReport {
    <#
    .SYNOPSIS
        Render a rotation report as either a markdown table or JSON.

    .PARAMETER Report
        A report object produced by Get-RotationReport.

    .PARAMETER Format
        'markdown' (default) or 'json'.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $Report,
        [string] $Format = 'markdown'
    )

    switch ($Format.ToLowerInvariant()) {
        'json' {
            # Depth 6 comfortably covers report -> groups -> secret -> requiredBy.
            return ($Report | ConvertTo-Json -Depth 6)
        }
        'markdown' {
            return (Format-MarkdownReport -Report $Report)
        }
        default {
            throw "Unsupported output format '$Format'. Use 'markdown' or 'json'."
        }
    }
}

function Format-MarkdownReport {
    <#
    .SYNOPSIS
        Internal helper: produce the markdown rendering of a report.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [object] $Report)

    # Emoji-free status badges keep output portable across terminals/logs.
    $badge = @{ expired = 'EXPIRED'; warning = 'WARNING'; ok = 'OK' }

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('# Secret Rotation Report')
    [void]$sb.AppendLine('')
    $labelPart = if ($Report.label) { " (`"$($Report.label)`")" } else { '' }
    [void]$sb.AppendLine("As of **$($Report.asOf)** with a **$($Report.warningWindowDays)-day** warning window$labelPart.")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("- Expired: **$($Report.summary.expired)**")
    [void]$sb.AppendLine("- Warning: **$($Report.summary.warning)**")
    [void]$sb.AppendLine("- OK: **$($Report.summary.ok)**")
    [void]$sb.AppendLine("- Total: **$($Report.summary.total)**")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('| Secret | Status | Last Rotated | Policy (days) | Expires On | Days Left | Required By |')
    [void]$sb.AppendLine('| --- | --- | --- | --- | --- | ---: | --- |')

    foreach ($s in @($Report.secrets)) {
        $required = if (@($s.requiredBy).Count -gt 0) { ($s.requiredBy -join ', ') } else { '-' }
        $statusText = $badge[$s.status]
        [void]$sb.AppendLine("| $($s.name) | $statusText | $($s.lastRotated) | $($s.rotationPolicyDays) | $($s.expiresOn) | $($s.daysUntilExpiry) | $required |")
    }

    return $sb.ToString().TrimEnd()
}

Export-ModuleMember -Function Get-SecretStatus, ConvertTo-Date, Import-SecretConfig, Get-RotationReport, Format-RotationReport
