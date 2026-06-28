<#
.SYNOPSIS
    Secret Rotation Validator - core library.

.DESCRIPTION
    Pure, side-effect-free functions for evaluating a set of secrets against
    their rotation policies. The design deliberately keeps all I/O at the edges
    (Import-SecretConfig reads, the CLI writes) so the evaluation logic stays
    trivially unit-testable with a fixed reference date.

    Pipeline of responsibilities:
        Import-SecretConfig        -> reads + validates a JSON config file
        Get-SecretRotationStatus   -> classifies ONE secret (Expired/Warning/Ok)
        Get-SecretRotationReport   -> classifies ALL secrets + summary + groups
        Format-SecretRotationReport-> renders a report as Markdown / Json / Summary
        Invoke-SecretRotationValidator -> ties it together for the CLI / workflow

    Status rules (let daysUntilExpiry = rotationPolicyDays - daysSinceRotation):
        Expired : daysUntilExpiry <= 0                  (due now or overdue)
        Warning : 0 < daysUntilExpiry <= WarningDays    (inside the warning window)
        Ok      : daysUntilExpiry > WarningDays
#>

Set-StrictMode -Version Latest

# Canonical date format for all dates in configs and output. Using ParseExact with
# the invariant culture makes parsing locale-independent (important inside CI).
$script:DateFormat = 'yyyy-MM-dd'

# Numeric priority used to order/group statuses by urgency (lower = more urgent).
$script:StatusPriority = @{ Expired = 0; Warning = 1; Ok = 2 }

function ConvertTo-RotationDate {
    <#
    .SYNOPSIS
        Coerce a value to a [datetime], accepting either an existing [datetime]
        or a yyyy-MM-dd string. Throws a caller-supplied, meaningful message.
    #>
    [CmdletBinding()]
    [OutputType([datetime])]
    param(
        [Parameter(Mandatory)] [AllowNull()] $Value,
        [Parameter(Mandatory)] [string] $ErrorContext
    )

    if ($null -eq $Value) {
        throw "$ErrorContext is missing (expected a $script:DateFormat date)."
    }
    if ($Value -is [datetime]) { return $Value }

    $parsed = [datetime]::MinValue
    $ok = [datetime]::TryParseExact(
        [string]$Value, $script:DateFormat,
        [cultureinfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::None,
        [ref]$parsed)

    if (-not $ok) {
        throw "$ErrorContext '$Value' is not a valid $script:DateFormat date."
    }
    return $parsed
}

function Get-SecretRotationStatus {
    <#
    .SYNOPSIS
        Evaluate a single secret against its rotation policy.

    .PARAMETER Secret
        An object with: name, lastRotated (yyyy-MM-dd), rotationPolicyDays (int),
        and optionally requiredBy (string[]).

    .PARAMETER ReferenceDate
        The "today" to measure against (string yyyy-MM-dd or [datetime]).

    .PARAMETER WarningDays
        How many days before expiry a secret should be flagged as Warning.

    .OUTPUTS
        A PSCustomObject with the evaluated fields, including DaysSinceRotation,
        DaysUntilExpiry and Status.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [psobject] $Secret,
        [Parameter(Mandatory)] $ReferenceDate,
        [Parameter(Mandatory)] [int] $WarningDays
    )

    if ($WarningDays -lt 0) {
        throw "WarningDays must be zero or greater (got $WarningDays)."
    }

    # A name is required to produce useful error messages and report rows.
    $name = if ($Secret.PSObject.Properties['name']) { [string]$Secret.name } else { $null }
    if ([string]::IsNullOrWhiteSpace($name)) {
        throw "Each secret must have a non-empty 'name' property."
    }

    if (-not $Secret.PSObject.Properties['rotationPolicyDays']) {
        throw "Secret '$name' is missing required property 'rotationPolicyDays'."
    }
    $policyDays = 0
    if (-not [int]::TryParse([string]$Secret.rotationPolicyDays, [ref]$policyDays) -or $policyDays -le 0) {
        throw "Secret '$name': rotationPolicyDays must be a positive integer (got '$($Secret.rotationPolicyDays)')."
    }

    $rotatedRaw = if ($Secret.PSObject.Properties['lastRotated']) { $Secret.lastRotated } else { $null }
    $rotated = ConvertTo-RotationDate -Value $rotatedRaw -ErrorContext "Secret '$name': lastRotated"
    $reference = ConvertTo-RotationDate -Value $ReferenceDate -ErrorContext "ReferenceDate"

    # requiredBy is optional; normalise to a string array.
    $requiredBy = @()
    if ($Secret.PSObject.Properties['requiredBy'] -and $null -ne $Secret.requiredBy) {
        $requiredBy = @($Secret.requiredBy | ForEach-Object { [string]$_ })
    }

    $daysSince = [int][math]::Floor(($reference.Date - $rotated.Date).TotalDays)
    $daysUntil = $policyDays - $daysSince

    $status =
        if ($daysUntil -le 0)            { 'Expired' }
        elseif ($daysUntil -le $WarningDays) { 'Warning' }
        else                             { 'Ok' }

    [pscustomobject]@{
        Name               = $name
        LastRotated        = $rotated.ToString($script:DateFormat, [cultureinfo]::InvariantCulture)
        RotationPolicyDays = $policyDays
        RequiredBy         = $requiredBy
        DaysSinceRotation  = $daysSince
        DaysUntilExpiry    = $daysUntil
        Status             = $status
    }
}

function Import-SecretConfig {
    <#
    .SYNOPSIS
        Read and validate a JSON secret-rotation configuration file.

    .DESCRIPTION
        Expected schema:
            {
              "referenceDate": "yyyy-MM-dd",   // optional
              "warningDays": <int>,            // optional
              "secrets": [
                { "name", "lastRotated", "rotationPolicyDays", "requiredBy"[] }
              ]
            }
        referenceDate / warningDays are optional here so the CLI can override or
        default them; the structural integrity of 'secrets' is validated strictly.

    .OUTPUTS
        PSCustomObject { ReferenceDate; WarningDays; Secrets }
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Secret configuration file not found: '$Path'."
    }

    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "Secret configuration file '$Path' is empty."
    }

    try {
        $config = $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Failed to parse JSON in '$Path': $($_.Exception.Message)"
    }

    if (-not $config.PSObject.Properties['secrets'] -or $null -eq $config.secrets) {
        throw "Configuration '$Path' must contain a 'secrets' array."
    }

    # Normalise to an array so a single-secret config still iterates correctly.
    $secrets = @($config.secrets)
    if ($secrets.Count -eq 0) {
        throw "Configuration '$Path' contains no secrets."
    }

    $referenceDate = $null
    if ($config.PSObject.Properties['referenceDate'] -and -not [string]::IsNullOrWhiteSpace([string]$config.referenceDate)) {
        $referenceDate = [string]$config.referenceDate
    }

    $warningDays = $null
    if ($config.PSObject.Properties['warningDays'] -and $null -ne $config.warningDays) {
        $parsedWarn = 0
        if (-not [int]::TryParse([string]$config.warningDays, [ref]$parsedWarn)) {
            throw "Configuration '$Path': warningDays must be an integer (got '$($config.warningDays)')."
        }
        $warningDays = $parsedWarn
    }

    [pscustomobject]@{
        ReferenceDate = $referenceDate
        WarningDays   = $warningDays
        Secrets       = $secrets
    }
}

function Get-SecretRotationReport {
    <#
    .SYNOPSIS
        Evaluate every secret and assemble a full report (summary + urgency groups).

    .OUTPUTS
        PSCustomObject {
            ReferenceDate; WarningDays;
            Secrets;                         # all, sorted by urgency then name
            Summary  { Expired; Warning; Ok; Total };
            Groups   { Expired[]; Warning[]; Ok[] }
        }
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [psobject[]] $Secrets,
        [Parameter(Mandatory)] $ReferenceDate,
        [Parameter(Mandatory)] [int] $WarningDays
    )

    # Normalise the reference date once so every row and the report header agree.
    $reference = ConvertTo-RotationDate -Value $ReferenceDate -ErrorContext "ReferenceDate"
    $refString = $reference.ToString($script:DateFormat, [cultureinfo]::InvariantCulture)

    $evaluated = foreach ($secret in $Secrets) {
        Get-SecretRotationStatus -Secret $secret -ReferenceDate $reference -WarningDays $WarningDays
    }

    # Sort by urgency (Expired first), then most-overdue first, then name for
    # stable, deterministic output regardless of input order.
    $sorted = @($evaluated | Sort-Object `
        @{ Expression = { $script:StatusPriority[$_.Status] } },
        @{ Expression = { $_.DaysUntilExpiry } },
        @{ Expression = { $_.Name } })

    $groups = [pscustomobject]@{
        Expired = @($sorted | Where-Object Status -EQ 'Expired')
        Warning = @($sorted | Where-Object Status -EQ 'Warning')
        Ok      = @($sorted | Where-Object Status -EQ 'Ok')
    }

    $summary = [pscustomobject]@{
        Expired = $groups.Expired.Count
        Warning = $groups.Warning.Count
        Ok      = $groups.Ok.Count
        Total   = $sorted.Count
    }

    [pscustomobject]@{
        ReferenceDate = $refString
        WarningDays   = $WarningDays
        Secrets       = $sorted
        Summary       = $summary
        Groups        = $groups
    }
}

function Format-SecretRotationReport {
    <#
    .SYNOPSIS
        Render a report object produced by Get-SecretRotationReport.

    .PARAMETER Format
        Markdown : human-friendly report with one table per urgency group.
        Json     : machine-readable structured report (camelCase keys).
        Summary  : grep-friendly one-line summary + one line per secret. Used by
                   the CI pipeline for exact-value assertions.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [psobject] $Report,
        [Parameter(Mandatory)] [ValidateSet('Markdown', 'Json', 'Summary')] [string] $Format
    )

    switch ($Format) {
        'Json'     { return (ConvertTo-RotationJson    -Report $Report) }
        'Summary'  { return (ConvertTo-RotationSummary -Report $Report) }
        'Markdown' { return (ConvertTo-RotationMarkdown -Report $Report) }
    }
}

function ConvertTo-RotationMarkdown {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [psobject] $Report)

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('# Secret Rotation Report')
    $lines.Add('')
    $lines.Add("- **Reference date:** $($Report.ReferenceDate)")
    $lines.Add("- **Warning window:** $($Report.WarningDays) day(s)")
    $lines.Add("- **Total secrets:** $($Report.Summary.Total)")
    $lines.Add("- **Expired:** $($Report.Summary.Expired)")
    $lines.Add("- **Warning:** $($Report.Summary.Warning)")
    $lines.Add("- **OK:** $($Report.Summary.Ok)")
    $lines.Add('')

    # One section per urgency group; empty groups render an explicit placeholder
    # so a reader can tell "no expired secrets" from "section forgotten".
    $sections = @(
        @{ Title = 'Expired'; Items = $Report.Groups.Expired }
        @{ Title = 'Warning'; Items = $Report.Groups.Warning }
        @{ Title = 'OK';      Items = $Report.Groups.Ok }
    )

    foreach ($section in $sections) {
        $items = @($section.Items)
        $lines.Add("## $($section.Title) ($($items.Count))")
        $lines.Add('')
        if ($items.Count -eq 0) {
            $lines.Add('_None_')
            $lines.Add('')
            continue
        }
        $lines.Add('| Name | Last Rotated | Policy (days) | Days Until Expiry | Required By |')
        $lines.Add('| --- | --- | --- | --- | --- |')
        foreach ($s in $items) {
            $req = if (@($s.RequiredBy).Count -gt 0) { ($s.RequiredBy -join ', ') } else { '(none)' }
            $lines.Add("| $($s.Name) | $($s.LastRotated) | $($s.RotationPolicyDays) | $($s.DaysUntilExpiry) | $req |")
        }
        $lines.Add('')
    }

    return ($lines -join [Environment]::NewLine).TrimEnd()
}

function ConvertTo-RotationSummary {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [psobject] $Report)

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add(("ROTATION-SUMMARY expired={0} warning={1} ok={2} total={3}" -f `
        $Report.Summary.Expired, $Report.Summary.Warning, $Report.Summary.Ok, $Report.Summary.Total))

    foreach ($s in $Report.Secrets) {
        $req = (@($s.RequiredBy) -join ',')
        $lines.Add(("SECRET name={0} status={1} daysSinceRotation={2} daysUntilExpiry={3} requiredBy={4}" -f `
            $s.Name, $s.Status, $s.DaysSinceRotation, $s.DaysUntilExpiry, $req))
    }

    return ($lines -join [Environment]::NewLine)
}

function ConvertTo-RotationJson {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [psobject] $Report)

    # Project to an ordered, camelCase shape that mirrors the input config so the
    # JSON output is a clean, stable contract for downstream consumers.
    $project = {
        param($s)
        [ordered]@{
            name               = $s.Name
            lastRotated        = $s.LastRotated
            rotationPolicyDays = $s.RotationPolicyDays
            requiredBy         = @($s.RequiredBy)
            daysSinceRotation  = $s.DaysSinceRotation
            daysUntilExpiry    = $s.DaysUntilExpiry
            status             = $s.Status
        }
    }

    $payload = [ordered]@{
        referenceDate = $Report.ReferenceDate
        warningDays   = $Report.WarningDays
        summary       = [ordered]@{
            expired = $Report.Summary.Expired
            warning = $Report.Summary.Warning
            ok      = $Report.Summary.Ok
            total   = $Report.Summary.Total
        }
        groups        = [ordered]@{
            expired = @($Report.Groups.Expired | ForEach-Object { & $project $_ })
            warning = @($Report.Groups.Warning | ForEach-Object { & $project $_ })
            ok      = @($Report.Groups.Ok      | ForEach-Object { & $project $_ })
        }
    }

    return ($payload | ConvertTo-Json -Depth 6)
}

function Invoke-SecretRotationValidator {
    <#
    .SYNOPSIS
        End-to-end entry point: load a config, build a report, render it.

    .DESCRIPTION
        Resolution precedence for reference date and warning window:
            explicit parameter  >  value in config file  >  built-in default
        The built-in reference-date default is the current date; the built-in
        warning-window default is 14 days.

    .PARAMETER ConfigPath
        Path to the JSON configuration file.

    .PARAMETER Format
        Output format: Markdown (default), Json, or Summary.

    .PARAMETER WarningDays
        Optional override for the warning window (in days).

    .PARAMETER ReferenceDate
        Optional override for "today" (yyyy-MM-dd). Mainly for deterministic tests.

    .OUTPUTS
        [string] the rendered report.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $ConfigPath,
        [ValidateSet('Markdown', 'Json', 'Summary')] [string] $Format = 'Markdown',
        [int] $WarningDays,
        [string] $ReferenceDate
    )

    $config = Import-SecretConfig -Path $ConfigPath

    # Resolve warning window: param > config > default(14).
    $effectiveWarning =
        if ($PSBoundParameters.ContainsKey('WarningDays')) { $WarningDays }
        elseif ($null -ne $config.WarningDays)             { $config.WarningDays }
        else                                               { 14 }

    # Resolve reference date: param > config > today.
    $effectiveReference =
        if ($PSBoundParameters.ContainsKey('ReferenceDate') -and -not [string]::IsNullOrWhiteSpace($ReferenceDate)) {
            $ReferenceDate
        }
        elseif ($null -ne $config.ReferenceDate) {
            $config.ReferenceDate
        }
        else {
            (Get-Date).ToString($script:DateFormat, [cultureinfo]::InvariantCulture)
        }

    $report = Get-SecretRotationReport -Secrets $config.Secrets `
        -ReferenceDate $effectiveReference -WarningDays $effectiveWarning

    return (Format-SecretRotationReport -Report $report -Format $Format)
}

Export-ModuleMember -Function `
    Get-SecretRotationStatus,
    Import-SecretConfig,
    Get-SecretRotationReport,
    Format-SecretRotationReport,
    Invoke-SecretRotationValidator
