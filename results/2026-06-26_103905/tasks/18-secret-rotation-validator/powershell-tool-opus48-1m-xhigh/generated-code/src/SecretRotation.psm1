function Get-SecretStatus {
    <#
        .SYNOPSIS
            Classify a single secret as Expired, Warning, or Ok.
        .DESCRIPTION
            Pure date logic. A secret "expires" on (LastRotated + RotationPolicyDays).
            We compare that expiry date against a caller-supplied ReferenceDate so the
            result is fully deterministic and testable.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][datetime]$LastRotated,
        [Parameter(Mandatory)][int]$RotationPolicyDays,
        [Parameter(Mandatory)][datetime]$ReferenceDate,
        [int]$WarningDays = 14
    )

    $expiry          = $LastRotated.Date.AddDays($RotationPolicyDays)
    $daysUntilExpiry = ($expiry.Date - $ReferenceDate.Date).Days

    $status =
        if ($daysUntilExpiry -lt 0)            { 'Expired' }
        elseif ($daysUntilExpiry -le $WarningDays) { 'Warning' }
        else                                   { 'Ok' }

    [pscustomobject]@{
        Status          = $status
        ExpiryDate      = $expiry
        DaysUntilExpiry = $daysUntilExpiry
    }
}

function Import-SecretConfig {
    <#
        .SYNOPSIS
            Load and validate a secrets configuration JSON file.
        .DESCRIPTION
            Accepts either:
              { "secrets": [ ... ] }   (object with a 'secrets' array), or
              [ ... ]                   (a bare top-level array of secrets)
            Every secret is validated for the required fields (name, lastRotated,
            rotationPolicyDays, requiredBy). Any problem raises a clear, actionable
            error rather than letting a malformed entry slip through.
        .OUTPUTS
            A PSCustomObject with a .Secrets property (array of validated secrets).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Secret configuration file not found: '$Path'"
    }

    $raw = Get-Content -LiteralPath $Path -Raw

    try {
        $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Invalid JSON in configuration file '$Path': $($_.Exception.Message)"
    }

    # Normalise: support both the object-with-'secrets' and bare-array shapes.
    $secrets =
        if ($null -ne $parsed -and $parsed.PSObject.Properties.Name -contains 'secrets') {
            $parsed.secrets
        }
        else {
            $parsed
        }

    # ConvertFrom-Json yields a single object (not an array) when there is one element.
    $secrets = @($secrets)

    if ($secrets.Count -eq 0) {
        throw "Configuration file '$Path' contains no secrets."
    }

    # Validate each secret. Failing fast with the offending secret's name/index
    # makes misconfiguration easy to diagnose in CI logs.
    $index = 0
    foreach ($secret in $secrets) {
        $label = if ($secret.name) { "'$($secret.name)'" } else { "at index $index" }

        foreach ($field in 'name', 'lastRotated', 'rotationPolicyDays', 'requiredBy') {
            $hasField = $secret.PSObject.Properties.Name -contains $field
            if (-not $hasField -or $null -eq $secret.$field -or
                ($secret.$field -is [string] -and [string]::IsNullOrWhiteSpace($secret.$field))) {
                throw "Secret $label is missing required field '$field'."
            }
        }

        [datetime]$parsedDate = [datetime]::MinValue
        if (-not [datetime]::TryParse(
                [string]$secret.lastRotated, [cultureinfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::None, [ref]$parsedDate)) {
            throw "Secret $label has an invalid 'lastRotated' date: '$($secret.lastRotated)'."
        }

        [int]$policy = 0
        if (-not [int]::TryParse([string]$secret.rotationPolicyDays, [ref]$policy) -or $policy -le 0) {
            throw "Secret $label has an invalid 'rotationPolicyDays' (must be a positive integer): '$($secret.rotationPolicyDays)'."
        }

        $index++
    }

    [pscustomobject]@{
        Secrets = $secrets
    }
}

function Get-RotationReport {
    <#
        .SYNOPSIS
            Turn a list of secrets into a structured rotation report.
        .DESCRIPTION
            For each secret it computes the rotation status (via Get-SecretStatus),
            then groups the enriched entries into Expired / Warning / Ok buckets and
            attaches a summary of counts. The returned object is the single source of
            truth consumed by the formatters and notifier.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Secrets,
        [Parameter(Mandatory)][datetime]$ReferenceDate,
        [int]$WarningDays = 14
    )

    $entries = foreach ($secret in $Secrets) {
        $status = Get-SecretStatus -LastRotated ([datetime]$secret.lastRotated) `
            -RotationPolicyDays ([int]$secret.rotationPolicyDays) `
            -ReferenceDate $ReferenceDate -WarningDays $WarningDays

        [pscustomobject]@{
            Name               = $secret.name
            LastRotated        = [datetime]$secret.lastRotated
            RotationPolicyDays = [int]$secret.rotationPolicyDays
            RequiredBy         = @($secret.requiredBy)
            Status             = $status.Status
            ExpiryDate         = $status.ExpiryDate
            DaysUntilExpiry    = $status.DaysUntilExpiry
        }
    }

    # @(...) guarantees real arrays (so empty buckets stay arrays, not $null).
    $expired = @($entries | Where-Object Status -eq 'Expired')
    $warning = @($entries | Where-Object Status -eq 'Warning')
    $ok      = @($entries | Where-Object Status -eq 'Ok')

    [pscustomobject]@{
        ReferenceDate = $ReferenceDate
        WarningDays   = $WarningDays
        Summary       = [pscustomobject]@{
            Expired = $expired.Count
            Warning = $warning.Count
            Ok      = $ok.Count
            Total   = @($entries).Count
        }
        Groups        = [pscustomobject]@{
            Expired = $expired
            Warning = $warning
            Ok      = $ok
        }
    }
}

function Format-RotationReport {
    <#
        .SYNOPSIS
            Render a rotation report as a Markdown table document or as JSON.
        .PARAMETER Format
            'Markdown' (human-friendly tables) or 'Json' (machine-readable).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$Report,
        [Parameter(Mandatory)][ValidateSet('Markdown', 'Json')][string]$Format
    )

    $refStr = $Report.ReferenceDate.ToString('yyyy-MM-dd')

    switch ($Format) {
        'Markdown' { return (Format-AsMarkdown -Report $Report -RefStr $refStr) }
        'Json'     { return (Format-AsJson     -Report $Report -RefStr $refStr) }
        default    { throw "Unsupported output format: '$Format'." }
    }
}

function Format-AsMarkdown {
    # Internal helper: build the Markdown document.
    [CmdletBinding()]
    param([pscustomobject]$Report, [string]$RefStr)

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('# Secret Rotation Report')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("- Reference date: $RefStr")
    [void]$sb.AppendLine("- Warning window: $($Report.WarningDays) day(s)")
    [void]$sb.AppendLine("- Total secrets: $($Report.Summary.Total)")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## Summary')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('| Urgency | Count |')
    [void]$sb.AppendLine('| --- | --- |')
    [void]$sb.AppendLine("| Expired | $($Report.Summary.Expired) |")
    [void]$sb.AppendLine("| Warning | $($Report.Summary.Warning) |")
    [void]$sb.AppendLine("| OK | $($Report.Summary.Ok) |")

    # Each urgency section uses a header tuned to whether it counts up or down.
    $sections = @(
        @{ Title = 'Expired'; Items = @($Report.Groups.Expired); DaysHeader = 'Days Overdue' }
        @{ Title = 'Warning'; Items = @($Report.Groups.Warning); DaysHeader = 'Days Until Expiry' }
        @{ Title = 'OK';      Items = @($Report.Groups.Ok);      DaysHeader = 'Days Until Expiry' }
    )

    foreach ($section in $sections) {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine("## $($section.Title) ($($section.Items.Count))")
        [void]$sb.AppendLine('')

        if ($section.Items.Count -eq 0) {
            [void]$sb.AppendLine('_None_')
            continue
        }

        [void]$sb.AppendLine("| Secret | Last Rotated | Policy (days) | Expiry Date | $($section.DaysHeader) | Required By |")
        [void]$sb.AppendLine('| --- | --- | --- | --- | --- | --- |')
        foreach ($item in $section.Items) {
            # Expired rows show positive "overdue" days; others show days remaining.
            $days = if ($section.Title -eq 'Expired') { -$item.DaysUntilExpiry } else { $item.DaysUntilExpiry }
            $services = ($item.RequiredBy -join ', ')
            [void]$sb.AppendLine(("| {0} | {1} | {2} | {3} | {4} | {5} |" -f `
                $item.Name,
                $item.LastRotated.ToString('yyyy-MM-dd'),
                $item.RotationPolicyDays,
                $item.ExpiryDate.ToString('yyyy-MM-dd'),
                $days,
                $services))
        }
    }

    $sb.ToString().TrimEnd()
}

function Format-AsJson {
    # Internal helper: build the JSON document with stable, formatted fields.
    [CmdletBinding()]
    param([pscustomobject]$Report, [string]$RefStr)

    # Project each entry into a JSON-friendly shape (dates as yyyy-MM-dd strings).
    $project = {
        param($item)
        [pscustomobject]@{
            name               = $item.Name
            lastRotated        = $item.LastRotated.ToString('yyyy-MM-dd')
            rotationPolicyDays = $item.RotationPolicyDays
            expiryDate         = $item.ExpiryDate.ToString('yyyy-MM-dd')
            daysUntilExpiry    = $item.DaysUntilExpiry
            status             = $item.Status
            requiredBy         = @($item.RequiredBy)
        }
    }

    $payload = [pscustomobject]@{
        generatedAt      = $RefStr
        referenceDate    = $RefStr
        warningWindowDays = $Report.WarningDays
        summary          = [pscustomobject]@{
            expired = $Report.Summary.Expired
            warning = $Report.Summary.Warning
            ok      = $Report.Summary.Ok
            total   = $Report.Summary.Total
        }
        groups           = [pscustomobject]@{
            expired = @(@($Report.Groups.Expired) | ForEach-Object { & $project $_ })
            warning = @(@($Report.Groups.Warning) | ForEach-Object { & $project $_ })
            ok      = @(@($Report.Groups.Ok)      | ForEach-Object { & $project $_ })
        }
    }

    # Depth 6 comfortably covers report -> groups -> entries -> requiredBy.
    $payload | ConvertTo-Json -Depth 6
}

function Get-RotationNotification {
    <#
        .SYNOPSIS
            Produce one notification line per secret, grouped by urgency.
        .DESCRIPTION
            Lines are ordered Expired -> Warning -> Ok so the most urgent items lead.
            Expired lines report how many days overdue; Warning/Ok report days remaining.
            The format is intentionally simple and stable so CI logs can be grepped.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$Report
    )

    $emit = {
        param($item, $label)
        $services = ($item.RequiredBy -join ',')
        if ($label -eq 'EXPIRED') {
            "NOTIFY EXPIRED $($item.Name) overdue=$(-$item.DaysUntilExpiry) requiredBy=$services"
        }
        else {
            "NOTIFY $label $($item.Name) days=$($item.DaysUntilExpiry) requiredBy=$services"
        }
    }

    foreach ($item in @($Report.Groups.Expired)) { & $emit $item 'EXPIRED' }
    foreach ($item in @($Report.Groups.Warning)) { & $emit $item 'WARNING' }
    foreach ($item in @($Report.Groups.Ok))      { & $emit $item 'OK' }
}

Export-ModuleMember -Function Get-SecretStatus, Import-SecretConfig, Get-RotationReport,
    Format-RotationReport, Get-RotationNotification
