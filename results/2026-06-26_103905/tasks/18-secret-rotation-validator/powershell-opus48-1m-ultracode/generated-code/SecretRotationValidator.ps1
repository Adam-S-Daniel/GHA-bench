#Requires -Version 7.0
<#
.SYNOPSIS
    Secret Rotation Validator — flags secrets that are expired or expiring soon
    and produces a rotation report grouped by urgency.

.DESCRIPTION
    Given a JSON configuration describing secrets (name, last-rotated date,
    rotation policy in days, and the services that require them), this script
    classifies every secret as one of:

        expired  - the rotation policy interval has already elapsed
        warning  - the secret will expire within the configurable warning window
        ok       - the secret is comfortably within policy

    It can emit the report as a Markdown table or as JSON, and (optionally) fail
    the calling process when any secret is expired — which makes it useful as a
    CI/CD guardrail.

    The file is intentionally dual-purpose:
      * Dot-source it (`. ./SecretRotationValidator.ps1`) to load the functions
        for unit testing — the CLI entry point at the bottom is NOT executed.
      * Run it directly (`./SecretRotationValidator.ps1 -ConfigPath ...`) to use
        it as a command-line tool.

.NOTES
    Written test-first with Pester (see SecretRotationValidator.Tests.ps1).
#>
[CmdletBinding()]
param(
    # Path to the JSON secrets configuration file.
    [string]$ConfigPath,

    # How many days before expiry a secret should be flagged as 'warning'.
    # Overrides any value supplied by the config file.
    [int]$WarningWindowDays,

    # The date to evaluate "now" against. Injectable so tests are deterministic.
    [datetime]$ReferenceDate,

    # Output format for the rendered report.
    [ValidateSet('markdown', 'json')]
    [string]$Format = 'markdown',

    # When set, the process exits non-zero if any secret is expired.
    [switch]$FailOnExpired
)

Set-StrictMode -Version Latest

# The three urgency buckets, most-urgent first. Centralised so the ordering is
# consistent everywhere (report groups, summary, markdown sections).
$script:UrgencyOrder = @('expired', 'warning', 'ok')

function Get-SecretRotationStatus {
    <#
    .SYNOPSIS
        Classifies a single secret as expired / warning / ok relative to a
        reference date.

    .PARAMETER Secret
        An object with at least: name, lastRotated, rotationPolicyDays. The
        optional requiredBy is carried through to the result for reporting.

    .PARAMETER ReferenceDate
        The "now" to evaluate against (date component only is used).

    .PARAMETER WarningWindowDays
        Secrets expiring within this many days (inclusive) are 'warning'.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Secret,
        [Parameter(Mandatory)] [datetime]$ReferenceDate,
        [Parameter(Mandatory)] [int]$WarningWindowDays
    )

    # Compare on whole days only — time-of-day should never affect a rotation
    # decision, and it keeps the arithmetic deterministic across time zones.
    $rotated   = ([datetime]$Secret.lastRotated).Date
    $reference = $ReferenceDate.Date
    $expiry    = $rotated.AddDays([int]$Secret.rotationPolicyDays)

    $daysSinceRotation = ($reference - $rotated).Days
    $daysUntilExpiry   = ($expiry - $reference).Days

    # Classification rules (boundary: expiring exactly today is 'warning', not
    # yet 'expired' — the policy interval has not strictly elapsed).
    if ($daysUntilExpiry -lt 0) {
        $status = 'expired'
    }
    elseif ($daysUntilExpiry -le $WarningWindowDays) {
        $status = 'warning'
    }
    else {
        $status = 'ok'
    }

    # requiredBy is optional metadata; access it StrictMode-safely.
    $requiredByRaw = Get-PropertyValue $Secret 'requiredBy'
    $requiredBy = if ($null -eq $requiredByRaw) { @() } else { @($requiredByRaw) }

    [pscustomobject]@{
        Name              = $Secret.name
        LastRotated       = $rotated
        RotationPolicyDays = [int]$Secret.rotationPolicyDays
        ExpiryDate        = $expiry
        DaysSinceRotation = $daysSinceRotation
        DaysUntilExpiry   = $daysUntilExpiry
        Status            = $status
        RequiredBy        = $requiredBy
    }
}

function Test-HasProperty {
    # StrictMode-safe property probe — `$obj.foo` would throw if 'foo' is absent.
    param($Object, [string]$Name)
    return $null -ne $Object.PSObject.Properties[$Name]
}

function Get-PropertyValue {
    # StrictMode-safe value accessor; returns $null when the property is absent.
    param($Object, [string]$Name)
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $null }
    return $prop.Value
}

function Import-SecretConfig {
    <#
    .SYNOPSIS
        Reads and validates a JSON secrets configuration file.

    .DESCRIPTION
        Fails fast with an actionable message for every foreseeable problem:
        missing file, malformed JSON, missing 'secrets' array, or any secret
        missing/holding an invalid required field. The offending secret is named
        (or indexed) so the operator can find it quickly.

    .OUTPUTS
        A normalised object: Secrets (array), ReferenceDate ([datetime] or $null),
        WarningWindowDays ([int] or $null).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Secret configuration file not found: '$Path'."
    }

    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    try {
        $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Invalid JSON in configuration file '$Path': $($_.Exception.Message)"
    }

    if (-not (Test-HasProperty $parsed 'secrets') -or $null -eq $parsed.secrets) {
        throw "Configuration file '$Path' must contain a 'secrets' array."
    }

    $secrets = @($parsed.secrets)

    # Validate every secret up front so the report stage can assume clean data.
    for ($i = 0; $i -lt $secrets.Count; $i++) {
        $s = $secrets[$i]
        # Prefer the secret's own name for messages; fall back to a 1-based index.
        $label = if ((Test-HasProperty $s 'name') -and -not [string]::IsNullOrWhiteSpace([string]$s.name)) {
            "'$($s.name)'"
        } else {
            "#$($i + 1)"
        }

        if (-not (Test-HasProperty $s 'name') -or [string]::IsNullOrWhiteSpace([string]$s.name)) {
            throw "Secret $label is missing a non-empty 'name'."
        }

        $rotatedRaw = Get-PropertyValue $s 'lastRotated'
        $parsedDate = [datetime]::MinValue
        if ($null -eq $rotatedRaw -or
            -not [datetime]::TryParse([string]$rotatedRaw,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::None, [ref]$parsedDate)) {
            throw "Secret $label has a missing or invalid 'lastRotated' date: '$rotatedRaw'. Expected an ISO date such as 2026-01-31."
        }

        $policyRaw = Get-PropertyValue $s 'rotationPolicyDays'
        $policyInt = 0
        if ($null -eq $policyRaw -or
            -not [int]::TryParse([string]$policyRaw, [ref]$policyInt) -or
            $policyInt -le 0) {
            throw "Secret $label has a missing or invalid 'rotationPolicyDays': '$policyRaw'. Expected a positive whole number of days."
        }
    }

    # Optional top-level overrides.
    $refDate = $null
    if ((Test-HasProperty $parsed 'referenceDate') -and -not [string]::IsNullOrWhiteSpace([string]$parsed.referenceDate)) {
        $tmp = [datetime]::MinValue
        if (-not [datetime]::TryParse([string]$parsed.referenceDate,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::None, [ref]$tmp)) {
            throw "Configuration file '$Path' has an invalid 'referenceDate': '$($parsed.referenceDate)'."
        }
        $refDate = $tmp
    }

    $warn = $null
    if ((Test-HasProperty $parsed 'warningWindowDays') -and $null -ne $parsed.warningWindowDays) {
        $w = 0
        if (-not [int]::TryParse([string]$parsed.warningWindowDays, [ref]$w) -or $w -lt 0) {
            throw "Configuration file '$Path' has an invalid 'warningWindowDays': '$($parsed.warningWindowDays)'. Expected a non-negative whole number."
        }
        $warn = $w
    }

    [pscustomobject]@{
        Secrets           = $secrets
        ReferenceDate     = $refDate
        WarningWindowDays = $warn
    }
}

function Get-RotationReport {
    <#
    .SYNOPSIS
        Classifies a collection of secrets and assembles a structured rotation
        report: per-secret statuses, urgency groups, and summary counts.

    .PARAMETER Secrets
        Raw secret objects (already validated, e.g. via Import-SecretConfig).

    .PARAMETER ReferenceDate
        The "now" to evaluate against.

    .PARAMETER WarningWindowDays
        Days-before-expiry threshold for the 'warning' bucket.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [array]$Secrets,
        [Parameter(Mandatory)] [datetime]$ReferenceDate,
        [Parameter(Mandatory)] [int]$WarningWindowDays
    )

    # Classify each secret.
    $statuses = @(
        foreach ($s in $Secrets) {
            Get-SecretRotationStatus -Secret $s -ReferenceDate $ReferenceDate -WarningWindowDays $WarningWindowDays
        }
    )

    # Group by urgency in a fixed, most-urgent-first order. Within a group, sort
    # by DaysUntilExpiry ascending so the most overdue / soonest-to-expire secret
    # leads — that is the one an operator should act on first.
    $groups = @(
        foreach ($urgency in $script:UrgencyOrder) {
            [pscustomobject]@{
                Status  = $urgency
                Secrets = @($statuses | Where-Object Status -eq $urgency | Sort-Object DaysUntilExpiry)
            }
        }
    )

    $summary = [pscustomobject]@{
        Expired = @($statuses | Where-Object Status -eq 'expired').Count
        Warning = @($statuses | Where-Object Status -eq 'warning').Count
        Ok      = @($statuses | Where-Object Status -eq 'ok').Count
        Total   = $statuses.Count
    }

    [pscustomobject]@{
        GeneratedAt       = (Get-Date).ToString('yyyy-MM-dd')
        ReferenceDate     = $ReferenceDate
        WarningWindowDays = $WarningWindowDays
        Secrets           = $statuses
        Groups            = $groups
        Summary           = $summary
    }
}

function Format-RotationReport {
    <#
    .SYNOPSIS
        Renders a rotation report as either a Markdown document (human-readable,
        grouped by urgency) or as a clean JSON document (machine-readable).

    .PARAMETER Report
        A report object produced by Get-RotationReport.

    .PARAMETER Format
        'markdown' (default) or 'json'.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Report,
        [ValidateSet('markdown', 'json')] [string]$Format = 'markdown'
    )

    # Friendly section titles for each urgency bucket.
    $titleMap = @{ expired = 'Expired'; warning = 'Warning'; ok = 'OK' }
    $s = $Report.Summary

    if ($Format -eq 'json') {
        # Build a deliberately clean, deterministic projection: dates become
        # ISO yyyy-MM-dd strings rather than serialised [datetime] objects.
        $secretProjection = foreach ($g in $Report.Groups) {
            foreach ($sec in $g.Secrets) {
                [ordered]@{
                    name              = $sec.Name
                    status            = $sec.Status
                    lastRotated       = $sec.LastRotated.ToString('yyyy-MM-dd')
                    expiryDate        = $sec.ExpiryDate.ToString('yyyy-MM-dd')
                    rotationPolicyDays = $sec.RotationPolicyDays
                    daysSinceRotation = $sec.DaysSinceRotation
                    daysUntilExpiry   = $sec.DaysUntilExpiry
                    requiredBy        = @($sec.RequiredBy)
                }
            }
        }

        $doc = [ordered]@{
            generatedAt       = $Report.GeneratedAt
            referenceDate     = $Report.ReferenceDate.ToString('yyyy-MM-dd')
            warningWindowDays = $Report.WarningWindowDays
            summary           = [ordered]@{
                expired = $s.Expired
                warning = $s.Warning
                ok      = $s.Ok
                total   = $s.Total
            }
            groups  = @(foreach ($g in $Report.Groups) {
                [ordered]@{ status = $g.Status; count = $g.Secrets.Count }
            })
            secrets = @($secretProjection)
        }

        return ($doc | ConvertTo-Json -Depth 6)
    }

    # --- Markdown ----------------------------------------------------------
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('# Secret Rotation Report')
    $lines.Add('')
    $lines.Add("- Reference date: $($Report.ReferenceDate.ToString('yyyy-MM-dd'))")
    $lines.Add("- Warning window: $($Report.WarningWindowDays) day(s)")
    $lines.Add("- Summary: $($s.Expired) expired, $($s.Warning) warning, $($s.Ok) ok ($($s.Total) total)")
    $lines.Add('')

    foreach ($g in $Report.Groups) {
        $lines.Add("## $($titleMap[$g.Status]) ($($g.Secrets.Count))")
        $lines.Add('')
        if ($g.Secrets.Count -eq 0) {
            $lines.Add('_None_')
            $lines.Add('')
            continue
        }
        $lines.Add('| Secret | Last Rotated | Expires | Days Until Expiry | Required By |')
        $lines.Add('| --- | --- | --- | --- | --- |')
        foreach ($sec in $g.Secrets) {
            $req = ($sec.RequiredBy -join ', ')
            $lines.Add("| $($sec.Name) | $($sec.LastRotated.ToString('yyyy-MM-dd')) | $($sec.ExpiryDate.ToString('yyyy-MM-dd')) | $($sec.DaysUntilExpiry) | $req |")
        }
        $lines.Add('')
    }

    return ($lines -join "`n")
}

function Invoke-SecretRotationValidator {
    <#
    .SYNOPSIS
        End-to-end orchestrator: import config -> resolve parameters -> build
        report -> render -> (optionally) persist, returning a structured result.

    .DESCRIPTION
        Parameter precedence for the warning window and reference date is:
            explicit parameter  >  value in the config file  >  built-in default
        (default window = 14 days, default reference date = today).

        Exit-code policy makes the validator a drop-in CI guardrail: it returns
        ExitCode 0 by default (report-only), but ExitCode 1 when -FailOnExpired
        is set AND at least one secret is expired. The caller (CLI entry point)
        translates ExitCode into the process exit status.

    .OUTPUTS
        A result object: Report, Output (rendered string), ReferenceDate,
        WarningWindowDays, Format, HasExpired, ExitCode.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$ConfigPath,
        [int]$WarningWindowDays,
        [datetime]$ReferenceDate,
        [ValidateSet('markdown', 'json')] [string]$Format = 'markdown',
        [string]$OutputPath,
        [switch]$FailOnExpired
    )

    $config = Import-SecretConfig -Path $ConfigPath

    # Resolve the warning window: parameter > config > default(14).
    $resolvedWindow =
        if ($PSBoundParameters.ContainsKey('WarningWindowDays')) { $WarningWindowDays }
        elseif ($null -ne $config.WarningWindowDays) { $config.WarningWindowDays }
        else { 14 }

    # Resolve the reference date: parameter > config > today.
    $resolvedRef =
        if ($PSBoundParameters.ContainsKey('ReferenceDate')) { $ReferenceDate }
        elseif ($null -ne $config.ReferenceDate) { $config.ReferenceDate }
        else { (Get-Date) }

    $report = Get-RotationReport -Secrets $config.Secrets -ReferenceDate $resolvedRef -WarningWindowDays $resolvedWindow
    $output = Format-RotationReport -Report $report -Format $Format

    if ($PSBoundParameters.ContainsKey('OutputPath') -and -not [string]::IsNullOrWhiteSpace($OutputPath)) {
        Set-Content -LiteralPath $OutputPath -Value $output -Encoding utf8
    }

    $hasExpired = $report.Summary.Expired -gt 0

    [pscustomobject]@{
        Report            = $report
        Output            = $output
        ReferenceDate     = $resolvedRef
        WarningWindowDays = $resolvedWindow
        Format            = $Format
        HasExpired        = $hasExpired
        ExitCode          = if ($FailOnExpired -and $hasExpired) { 1 } else { 0 }
    }
}

function Get-RotationSummaryMarkers {
    <#
    .SYNOPSIS
        Produces stable, single-line, machine-readable markers describing a
        report — intended for CI logs to grep/assert against.

    .DESCRIPTION
        Emits one ROTATION_SUMMARY line plus one GROUP <URGENCY>: line per
        urgency bucket (comma-separated secret names, most-urgent first).
        Deliberately StrictMode-safe: an empty group yields an empty membership
        list rather than throwing on a missing '.Name' property.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Report
    )

    $s = $Report.Summary
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add(("ROTATION_SUMMARY expired={0} warning={1} ok={2} total={3}" -f `
        $s.Expired, $s.Warning, $s.Ok, $s.Total))

    foreach ($g in $Report.Groups) {
        # Pipe rather than `$g.Secrets.Name` so an empty group is safe under StrictMode.
        $names = @($g.Secrets | ForEach-Object { $_.Name }) -join ','
        $lines.Add(("GROUP {0}: {1}" -f $g.Status.ToUpper(), $names))
    }

    return ($lines -join "`n")
}

# ---------------------------------------------------------------------------
# CLI entry point. Only runs when the script is invoked directly (not when it
# is dot-sourced for testing). `$MyInvocation.InvocationName -eq '.'` is true
# precisely when the file was dot-sourced.
#
# For convenience in CI, every parameter also has an environment-variable
# fallback so the workflow can drive the script with plain `env:` blocks.
# ---------------------------------------------------------------------------
if ($MyInvocation.InvocationName -ne '.') {
    try {
        # Config path: -ConfigPath, else $env:SECRET_ROTATION_CONFIG.
        $cfg = if ($ConfigPath) { $ConfigPath }
               elseif ($env:SECRET_ROTATION_CONFIG) { $env:SECRET_ROTATION_CONFIG }
               else { $null }
        if (-not $cfg) {
            throw "No configuration supplied. Pass -ConfigPath <file> or set the SECRET_ROTATION_CONFIG environment variable."
        }

        $invokeArgs = @{ ConfigPath = $cfg }

        # Format: -Format, else $env:SECRET_ROTATION_FORMAT, else default.
        $invokeArgs['Format'] =
            if ($PSBoundParameters.ContainsKey('Format')) { $Format }
            elseif ($env:SECRET_ROTATION_FORMAT) { $env:SECRET_ROTATION_FORMAT }
            else { $Format }

        if ($PSBoundParameters.ContainsKey('WarningWindowDays')) {
            $invokeArgs['WarningWindowDays'] = $WarningWindowDays
        }
        elseif (-not [string]::IsNullOrWhiteSpace($env:SECRET_ROTATION_WARNING_DAYS)) {
            $invokeArgs['WarningWindowDays'] = [int]$env:SECRET_ROTATION_WARNING_DAYS
        }

        if ($PSBoundParameters.ContainsKey('ReferenceDate')) {
            $invokeArgs['ReferenceDate'] = $ReferenceDate
        }
        elseif (-not [string]::IsNullOrWhiteSpace($env:SECRET_ROTATION_REFERENCE_DATE)) {
            $invokeArgs['ReferenceDate'] = [datetime]$env:SECRET_ROTATION_REFERENCE_DATE
        }

        if ($FailOnExpired -or $env:SECRET_ROTATION_FAIL_ON_EXPIRED -eq 'true') {
            $invokeArgs['FailOnExpired'] = $true
        }

        $result = Invoke-SecretRotationValidator @invokeArgs
        Write-Output $result.Output
        exit $result.ExitCode
    }
    catch {
        # Graceful failure with an actionable message and a distinct exit code.
        Write-Error $_.Exception.Message
        exit 2
    }
}
