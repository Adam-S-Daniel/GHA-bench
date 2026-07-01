# SecretRotationValidator.psm1
#
# Core logic for the Secret Rotation Validator: load a secrets config,
# compute each secret's rotation status, group into a report, and format
# that report as Markdown or JSON. Kept separate from the CLI entry point
# (SecretRotationValidator.ps1) so the logic can be unit tested directly
# with Pester.

Set-StrictMode -Version Latest

function Import-SecretConfig {
    <#
    .SYNOPSIS
        Loads and validates a secret rotation configuration file.
    .DESCRIPTION
        Reads a JSON file describing secrets (name, last-rotated date,
        rotation policy in days, and the services that require it) and
        returns a normalized PSCustomObject:
            WarningWindowDays : [int]  (optional top-level default, may be $null)
            Secrets           : [PSCustomObject[]] with Name/LastRotated/RotationPolicyDays/RequiredBy
        Throws a terminating error with a clear message for any malformed input.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Configuration file not found: '$Path'"
    }

    $rawContent = Get-Content -LiteralPath $Path -Raw

    try {
        $json = $rawContent | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Invalid JSON in configuration file '$Path': $($_.Exception.Message)"
    }

    if (-not (Get-Member -InputObject $json -Name 'secrets' -MemberType NoteProperty)) {
        throw "Configuration file '$Path' is missing the required 'secrets' array"
    }

    $secrets = @()
    $index = 0
    foreach ($rawSecret in @($json.secrets)) {
        $index++
        $label = "secret at index $index"

        if (-not (Get-Member -InputObject $rawSecret -Name 'name' -MemberType NoteProperty) -or
            [string]::IsNullOrWhiteSpace($rawSecret.name)) {
            throw "Configuration file '$Path' has a $label with a missing or empty 'name' field"
        }
        $label = "secret '$($rawSecret.name)'"

        if (-not (Get-Member -InputObject $rawSecret -Name 'lastRotated' -MemberType NoteProperty) -or
            [string]::IsNullOrWhiteSpace($rawSecret.lastRotated)) {
            throw "Configuration file '$Path' has $label with a missing 'lastRotated' date"
        }

        $lastRotated = [datetime]::MinValue
        if (-not [datetime]::TryParse(
                $rawSecret.lastRotated,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::None,
                [ref]$lastRotated)) {
            throw "Configuration file '$Path' has $label with an invalid lastRotated date: '$($rawSecret.lastRotated)'"
        }

        if (-not (Get-Member -InputObject $rawSecret -Name 'rotationPolicyDays' -MemberType NoteProperty)) {
            throw "Configuration file '$Path' has $label with a missing 'rotationPolicyDays' field"
        }

        $rotationPolicyDays = 0
        if (-not [int]::TryParse("$($rawSecret.rotationPolicyDays)", [ref]$rotationPolicyDays) -or $rotationPolicyDays -le 0) {
            throw "Configuration file '$Path' has $label with an invalid rotationPolicyDays (must be a positive integer): '$($rawSecret.rotationPolicyDays)'"
        }

        $requiredBy = @()
        if (Get-Member -InputObject $rawSecret -Name 'requiredBy' -MemberType NoteProperty) {
            $requiredBy = @($rawSecret.requiredBy)
        }

        $secrets += [PSCustomObject]@{
            Name               = $rawSecret.name
            LastRotated        = $lastRotated
            RotationPolicyDays = $rotationPolicyDays
            RequiredBy         = $requiredBy
        }
    }

    $warningWindowDays = $null
    if (Get-Member -InputObject $json -Name 'warningWindowDays' -MemberType NoteProperty) {
        $warningWindowDays = [int]$json.warningWindowDays
    }

    [PSCustomObject]@{
        WarningWindowDays = $warningWindowDays
        Secrets           = $secrets
    }
}

function Get-SecretStatus {
    <#
    .SYNOPSIS
        Computes the rotation status of a single secret.
    .DESCRIPTION
        Given a secret (Name/LastRotated/RotationPolicyDays/RequiredBy) and a
        warning window in days, computes ExpiryDate and DaysUntilExpiry
        relative to -AsOf (defaults to the current date), and classifies the
        secret as one of:
            Expired : DaysUntilExpiry < 0            (past its rotation policy)
            Warning : 0 <= DaysUntilExpiry <= window  (expiring soon, inclusive)
            Ok      : DaysUntilExpiry > window
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Secret,

        [Parameter(Mandatory)]
        [int]$WarningWindowDays,

        [datetime]$AsOf = (Get-Date)
    )

    $expiryDate = $Secret.LastRotated.AddDays($Secret.RotationPolicyDays)
    $daysUntilExpiry = [int]($expiryDate.Date - $AsOf.Date).TotalDays

    $status = if ($daysUntilExpiry -lt 0) {
        'Expired'
    } elseif ($daysUntilExpiry -le $WarningWindowDays) {
        'Warning'
    } else {
        'Ok'
    }

    [PSCustomObject]@{
        Name               = $Secret.Name
        LastRotated        = $Secret.LastRotated
        RotationPolicyDays = $Secret.RotationPolicyDays
        RequiredBy         = $Secret.RequiredBy
        ExpiryDate         = $expiryDate
        DaysUntilExpiry    = $daysUntilExpiry
        Status             = $status
    }
}

function New-SecretRotationReport {
    <#
    .SYNOPSIS
        Builds a rotation report for a set of secrets, grouped by urgency.
    .DESCRIPTION
        Runs Get-SecretStatus over every secret and groups the results into
        Expired / Warning / Ok buckets, each sorted by DaysUntilExpiry
        ascending (most urgent first). Also returns a Summary with counts.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [PSCustomObject[]]$Secrets,

        [Parameter(Mandatory)]
        [int]$WarningWindowDays,

        [datetime]$AsOf = (Get-Date)
    )

    $statuses = @($Secrets | ForEach-Object {
        Get-SecretStatus -Secret $_ -WarningWindowDays $WarningWindowDays -AsOf $AsOf
    })

    $expired = @($statuses | Where-Object Status -eq 'Expired' | Sort-Object DaysUntilExpiry)
    $warning = @($statuses | Where-Object Status -eq 'Warning' | Sort-Object DaysUntilExpiry)
    $ok = @($statuses | Where-Object Status -eq 'Ok' | Sort-Object DaysUntilExpiry)

    [PSCustomObject]@{
        AsOf              = $AsOf
        WarningWindowDays = $WarningWindowDays
        Expired           = $expired
        Warning           = $warning
        Ok                = $ok
        Summary           = [PSCustomObject]@{
            Total        = $statuses.Count
            ExpiredCount = $expired.Count
            WarningCount = $warning.Count
            OkCount      = $ok.Count
        }
    }
}

function Format-MarkdownSection {
    param([string]$Title, [PSCustomObject[]]$Items)

    $lines = @("## $Title", '')
    if ($Items.Count -eq 0) {
        $lines += '_No secrets in this category._'
    } else {
        $lines += '| Name | Status | Last Rotated | Expires | Days Until Expiry | Required By |'
        $lines += '|------|--------|---------------|---------|--------------------|-------------|'
        foreach ($item in $Items) {
            $requiredBy = ($item.RequiredBy -join ', ')
            $lines += "| $($item.Name) | $($item.Status) | $($item.LastRotated.ToString('yyyy-MM-dd')) | $($item.ExpiryDate.ToString('yyyy-MM-dd')) | $($item.DaysUntilExpiry) | $requiredBy |"
        }
    }
    $lines += ''
    return $lines -join "`n"
}

function Format-SecretRotationReport {
    <#
    .SYNOPSIS
        Renders a secret rotation report as Markdown or JSON.
    .DESCRIPTION
        Markdown: a titled report with a summary line and one table per
        urgency bucket (Expired, Warning, Ok), most urgent secrets first.
        Json: the report object serialized with ConvertTo-Json.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Report,

        [Parameter(Mandatory)]
        [ValidateSet('Markdown', 'Json')]
        [string]$Format
    )

    switch ($Format) {
        'Json' {
            return $Report | ConvertTo-Json -Depth 10
        }
        'Markdown' {
            $lines = @(
                '# Secret Rotation Report',
                '',
                "Generated as of $($Report.AsOf.ToString('yyyy-MM-dd')) with a $($Report.WarningWindowDays)-day warning window.",
                '',
                "**Summary:** Total: $($Report.Summary.Total) | Expired: $($Report.Summary.ExpiredCount) | Warning: $($Report.Summary.WarningCount) | Ok: $($Report.Summary.OkCount)",
                ''
            )
            $lines += Format-MarkdownSection -Title 'Expired' -Items $Report.Expired
            $lines += Format-MarkdownSection -Title 'Warning' -Items $Report.Warning
            $lines += Format-MarkdownSection -Title 'Ok' -Items $Report.Ok
            return $lines -join "`n"
        }
    }
}

Export-ModuleMember -Function Import-SecretConfig, Get-SecretStatus, New-SecretRotationReport, Format-SecretRotationReport
