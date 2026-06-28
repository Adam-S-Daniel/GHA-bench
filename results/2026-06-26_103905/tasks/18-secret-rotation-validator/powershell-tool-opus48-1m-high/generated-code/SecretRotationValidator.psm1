<#
.SYNOPSIS
    Secret Rotation Validator - core library.

.DESCRIPTION
    Pure, side-effect-free functions for evaluating a configuration of secrets
    (with last-rotated date, rotation policy, and required-by services) against a
    reference date and a configurable warning window, then producing a rotation
    report grouped by urgency (expired / warning / ok) in markdown or JSON.

    The module deliberately keeps I/O (file reading) in a single thin function
    (Import-SecretConfig) so the classification/report logic stays pure and
    trivially unit-testable.
#>

Set-StrictMode -Version Latest

# A single shared date format keeps parsing and rendering symmetric and avoids
# culture-dependent surprises in CI containers.
$script:DateFormat = 'yyyy-MM-dd'

function ConvertTo-RotationDate {
    <#
    .SYNOPSIS
        Parse a yyyy-MM-dd string into a [datetime], with a meaningful error.
    .DESCRIPTION
        Centralises date parsing so every caller produces the same, helpful
        message when given malformed input. Uses InvariantCulture so behaviour is
        identical on a developer laptop and inside an act/Docker container.
    #>
    [CmdletBinding()]
    [OutputType([datetime])]
    param(
        [Parameter(Mandatory)] [string] $Value,
        [Parameter(Mandatory)] [string] $FieldName
    )

    [datetime] $parsed = [datetime]::MinValue
    $ok = [datetime]::TryParseExact(
        $Value,
        $script:DateFormat,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::None,
        [ref] $parsed)

    if (-not $ok) {
        throw "Invalid $FieldName '$Value'. Expected a date in $script:DateFormat format."
    }
    return $parsed
}

function Get-SecretRotationStatus {
    <#
    .SYNOPSIS
        Classify one secret as expired / warning / ok.
    .DESCRIPTION
        Computes the rotation deadline (lastRotated + rotationPolicyDays) and
        compares it to the reference date. A secret is:
          * expired  - deadline is in the past (DaysUntilExpiry < 0)
          * warning  - deadline is within the warning window (0 <= days <= WarningDays)
          * ok       - deadline is beyond the warning window
    .OUTPUTS
        A flat [pscustomobject] describing the secret and its computed status.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [psobject] $Secret,
        [Parameter(Mandatory)] $ReferenceDate,
        [Parameter(Mandatory)] [int] $WarningDays
    )

    # --- Validate the incoming record so bad data fails loudly and early. ---
    if (-not ($Secret.PSObject.Properties.Name -contains 'name') -or [string]::IsNullOrWhiteSpace([string]$Secret.name)) {
        throw "Each secret must have a non-empty 'name'."
    }
    $name = [string]$Secret.name

    foreach ($required in 'lastRotated', 'rotationPolicyDays') {
        if (-not ($Secret.PSObject.Properties.Name -contains $required)) {
            throw "Secret '$name' is missing required field '$required'."
        }
    }

    $policyDays = 0
    if (-not [int]::TryParse([string]$Secret.rotationPolicyDays, [ref] $policyDays) -or $policyDays -le 0) {
        throw "Secret '$name' has an invalid 'rotationPolicyDays' value '$($Secret.rotationPolicyDays)'. Expected a positive integer."
    }

    if ($WarningDays -lt 0) {
        throw "WarningDays must be zero or greater; got '$WarningDays'."
    }

    $lastRotated = ConvertTo-RotationDate -Value ([string]$Secret.lastRotated) -FieldName "lastRotated for secret '$name'"
    $reference = if ($ReferenceDate -is [datetime]) { $ReferenceDate } else { ConvertTo-RotationDate -Value ([string]$ReferenceDate) -FieldName 'ReferenceDate' }

    # Compare whole days only (ignore time-of-day) for stable, intuitive results.
    $expiry = $lastRotated.Date.AddDays($policyDays)
    $daysUntilExpiry = [int]($expiry.Date - $reference.Date).TotalDays

    $status =
        if ($daysUntilExpiry -lt 0) { 'expired' }
        elseif ($daysUntilExpiry -le $WarningDays) { 'warning' }
        else { 'ok' }

    # requiredBy is optional metadata; normalise to an array for predictable output.
    $requiredBy = @()
    if ($Secret.PSObject.Properties.Name -contains 'requiredBy' -and $null -ne $Secret.requiredBy) {
        $requiredBy = @($Secret.requiredBy)
    }

    return [pscustomobject]@{
        Name               = $name
        LastRotated        = $lastRotated.ToString($script:DateFormat)
        RotationPolicyDays = $policyDays
        ExpiryDate         = $expiry.ToString($script:DateFormat)
        DaysUntilExpiry    = $daysUntilExpiry
        Status             = $status
        RequiredBy         = $requiredBy
    }
}

function Import-SecretConfig {
    <#
    .SYNOPSIS
        Read and parse a secrets configuration JSON file.
    .DESCRIPTION
        The only I/O boundary in the module. Validates the file exists, contains
        valid JSON, and has a 'secrets' array. Optional top-level fields
        'referenceDate' and 'warningDays' supply per-config defaults so a fixture
        can be fully self-contained and deterministic.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Secret configuration file not found: '$Path'."
    }

    try {
        $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    } catch {
        throw "Unable to read configuration file '$Path': $($_.Exception.Message)"
    }

    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "Configuration file '$Path' is empty."
    }

    try {
        $config = $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Configuration file '$Path' contains invalid JSON: $($_.Exception.Message)"
    }

    if (-not ($config.PSObject.Properties.Name -contains 'secrets') -or $null -eq $config.secrets) {
        throw "Configuration file '$Path' must contain a 'secrets' array."
    }

    return $config
}

function New-RotationReport {
    <#
    .SYNOPSIS
        Evaluate every secret in a config and group the results by urgency.
    .DESCRIPTION
        Reference date and warning window are resolved with the precedence:
        explicit parameter > config field > built-in default (today / 14 days).
    .OUTPUTS
        A report object with ReferenceDate, WarningDays, Counts, and the
        Expired/Warning/Ok/All collections.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [psobject] $Config,
        $ReferenceDate,
        [Nullable[int]] $WarningDays
    )

    # --- Resolve the reference date (parameter > config > today). ---
    $reference =
        if ($null -ne $ReferenceDate -and -not ($ReferenceDate -is [string] -and [string]::IsNullOrWhiteSpace($ReferenceDate))) {
            if ($ReferenceDate -is [datetime]) { $ReferenceDate } else { ConvertTo-RotationDate -Value ([string]$ReferenceDate) -FieldName 'ReferenceDate' }
        } elseif ($Config.PSObject.Properties.Name -contains 'referenceDate' -and -not [string]::IsNullOrWhiteSpace([string]$Config.referenceDate)) {
            ConvertTo-RotationDate -Value ([string]$Config.referenceDate) -FieldName 'referenceDate'
        } else {
            (Get-Date).Date
        }

    # --- Resolve the warning window (parameter > config > default 14). ---
    $warn =
        if ($null -ne $WarningDays) {
            [int]$WarningDays
        } elseif ($Config.PSObject.Properties.Name -contains 'warningDays' -and $null -ne $Config.warningDays) {
            [int]$Config.warningDays
        } else {
            14
        }

    if ($warn -lt 0) {
        throw "WarningDays must be zero or greater; got '$warn'."
    }

    # Evaluate each secret. @() guards against a single-element collection
    # collapsing into a scalar.
    $evaluated = @(
        foreach ($secret in $Config.secrets) {
            Get-SecretRotationStatus -Secret $secret -ReferenceDate $reference -WarningDays $warn
        }
    )

    # Sort within each urgency bucket by soonest deadline so the most urgent
    # items surface first in reports.
    $expired = @($evaluated | Where-Object { $_.Status -eq 'expired' } | Sort-Object DaysUntilExpiry)
    $warning = @($evaluated | Where-Object { $_.Status -eq 'warning' } | Sort-Object DaysUntilExpiry)
    $ok      = @($evaluated | Where-Object { $_.Status -eq 'ok' } | Sort-Object DaysUntilExpiry)

    return [pscustomobject]@{
        ReferenceDate = $reference.ToString($script:DateFormat)
        WarningDays   = $warn
        Counts        = [pscustomobject]@{
            Expired = $expired.Count
            Warning = $warning.Count
            Ok      = $ok.Count
            Total   = $evaluated.Count
        }
        Expired = $expired
        Warning = $warning
        Ok      = $ok
        All     = $evaluated
    }
}

function Format-RotationReport {
    <#
    .SYNOPSIS
        Render a rotation report as a markdown document or JSON string.
    .DESCRIPTION
        markdown -> a human-readable report with a summary line and one table per
                    non-empty urgency group.
        json     -> a stable, machine-readable structure (ideal for piping into
                    other tooling or asserting on in CI).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [psobject] $Report,
        [ValidateSet('markdown', 'json')] [string] $Format = 'markdown'
    )

    switch ($Format) {
        'json' {
            # Re-shape into an explicit, ordered structure so the JSON contract is
            # stable regardless of internal field ordering.
            $shape = [ordered]@{
                referenceDate = $Report.ReferenceDate
                warningDays   = $Report.WarningDays
                counts        = [ordered]@{
                    expired = $Report.Counts.Expired
                    warning = $Report.Counts.Warning
                    ok      = $Report.Counts.Ok
                    total   = $Report.Counts.Total
                }
                groups        = [ordered]@{
                    expired = @($Report.Expired | ForEach-Object { ConvertTo-ReportRecord $_ })
                    warning = @($Report.Warning | ForEach-Object { ConvertTo-ReportRecord $_ })
                    ok      = @($Report.Ok | ForEach-Object { ConvertTo-ReportRecord $_ })
                }
            }
            return ($shape | ConvertTo-Json -Depth 6)
        }

        'markdown' {
            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add('# Secret Rotation Report')
            $lines.Add('')
            $lines.Add("- Reference date: $($Report.ReferenceDate)")
            $lines.Add("- Warning window: $($Report.WarningDays) day(s)")
            $lines.Add("- Summary: $($Report.Counts.Expired) expired, $($Report.Counts.Warning) warning, $($Report.Counts.Ok) ok ($($Report.Counts.Total) total)")
            $lines.Add('')

            $groups = @(
                @{ Title = 'Expired'; Items = $Report.Expired }
                @{ Title = 'Warning'; Items = $Report.Warning }
                @{ Title = 'OK';      Items = $Report.Ok }
            )

            foreach ($group in $groups) {
                $lines.Add("## $($group.Title) ($($group.Items.Count))")
                $lines.Add('')
                if ($group.Items.Count -eq 0) {
                    $lines.Add('_None._')
                    $lines.Add('')
                    continue
                }
                $lines.Add('| Secret | Last Rotated | Policy (days) | Expiry | Days Left | Required By |')
                $lines.Add('| --- | --- | --- | --- | --- | --- |')
                foreach ($item in $group.Items) {
                    $required = if ($item.RequiredBy.Count -gt 0) { ($item.RequiredBy -join ', ') } else { '-' }
                    $lines.Add("| $($item.Name) | $($item.LastRotated) | $($item.RotationPolicyDays) | $($item.ExpiryDate) | $($item.DaysUntilExpiry) | $required |")
                }
                $lines.Add('')
            }

            return ($lines -join "`n").TrimEnd()
        }
    }
}

function ConvertTo-ReportRecord {
    <#
    .SYNOPSIS
        Project an evaluated secret into the camelCase shape used in JSON output.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [psobject] $Item)

    return [ordered]@{
        name               = $Item.Name
        lastRotated        = $Item.LastRotated
        rotationPolicyDays = $Item.RotationPolicyDays
        expiryDate         = $Item.ExpiryDate
        daysUntilExpiry    = $Item.DaysUntilExpiry
        status             = $Item.Status
        requiredBy         = @($Item.RequiredBy)
    }
}

Export-ModuleMember -Function Get-SecretRotationStatus, Import-SecretConfig, New-RotationReport, Format-RotationReport, ConvertTo-RotationDate
