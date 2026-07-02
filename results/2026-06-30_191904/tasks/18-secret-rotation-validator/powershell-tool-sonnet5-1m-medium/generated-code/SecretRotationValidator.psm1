# SecretRotationValidator.psm1
# Core logic for evaluating secret rotation status, building rotation
# reports, and rendering them in different output formats.

function Get-SecretRotationStatus {
    <#
    .SYNOPSIS
        Determines the rotation status of a single secret.
    .DESCRIPTION
        Given when a secret was last rotated and its rotation policy (in
        days), computes the due date and classifies the secret as Ok,
        Warning (due within the warning window) or Expired (due date has
        passed, including due today).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [datetime]$LastRotated,

        [Parameter(Mandatory)]
        [int]$RotationPolicyDays,

        [Parameter(Mandatory)]
        [int]$WarningDays,

        [datetime]$Now = (Get-Date)
    )

    if ($RotationPolicyDays -le 0) {
        throw "RotationPolicyDays must be a positive integer, got '$RotationPolicyDays'."
    }
    if ($WarningDays -lt 0) {
        throw "WarningDays must be zero or a positive integer, got '$WarningDays'."
    }

    $dueDate = $LastRotated.Date.AddDays($RotationPolicyDays)
    $daysUntilDue = [int]($dueDate - $Now.Date).TotalDays

    $status = if ($daysUntilDue -le 0) {
        'Expired'
    } elseif ($daysUntilDue -le $WarningDays) {
        'Warning'
    } else {
        'Ok'
    }

    [PSCustomObject]@{
        Status       = $status
        DueDate      = $dueDate
        DaysUntilDue = $daysUntilDue
    }
}

function New-SecretRotationReport {
    <#
    .SYNOPSIS
        Builds a full rotation report for a collection of secrets.
    .DESCRIPTION
        Evaluates each secret's rotation status and groups the results into
        Expired / Warning / Ok buckets, alongside summary counts. Each entry
        in a bucket carries the secret's name, due date, days until due, and
        the services that depend on it (RequiredBy) so notifications can be
        targeted at the right owners.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Secrets,

        [Parameter(Mandatory)]
        [int]$WarningDays,

        [datetime]$Now = (Get-Date)
    )

    if (-not $Secrets -or $Secrets.Count -eq 0) {
        throw "New-SecretRotationReport requires at least one secret; no secrets were supplied."
    }

    $expired = [System.Collections.Generic.List[object]]::new()
    $warning = [System.Collections.Generic.List[object]]::new()
    $ok      = [System.Collections.Generic.List[object]]::new()

    foreach ($secret in $Secrets) {
        if (-not $secret.Name) {
            throw "Every secret entry must have a Name property."
        }

        $lastRotated = [datetime]$secret.LastRotated
        $status = Get-SecretRotationStatus -LastRotated $lastRotated `
            -RotationPolicyDays $secret.RotationPolicyDays -WarningDays $WarningDays -Now $Now

        $entry = [PSCustomObject]@{
            Name         = $secret.Name
            LastRotated  = $lastRotated
            DueDate      = $status.DueDate
            DaysUntilDue = $status.DaysUntilDue
            Status       = $status.Status
            RequiredBy   = @($secret.RequiredBy)
        }

        switch ($status.Status) {
            'Expired' { $expired.Add($entry) }
            'Warning' { $warning.Add($entry) }
            'Ok'      { $ok.Add($entry) }
        }
    }

    [PSCustomObject]@{
        GeneratedAt = $Now
        WarningDays = $WarningDays
        Expired     = @($expired)
        Warning     = @($warning)
        Ok          = @($ok)
        Summary     = [PSCustomObject]@{
            TotalCount   = $Secrets.Count
            ExpiredCount = $expired.Count
            WarningCount = $warning.Count
            OkCount      = $ok.Count
        }
    }
}

function Format-SecretRotationReport {
    <#
    .SYNOPSIS
        Renders a rotation report in the requested output format.
    .DESCRIPTION
        Supports Markdown (a table grouped under per-urgency headers) and
        Json (the report object serialized as-is) so the report can be
        posted as a PR comment, a CI job summary, or consumed by another
        tool.
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
            return $Report | ConvertTo-Json -Depth 6
        }
        'Markdown' {
            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add("# Secret Rotation Report")
            $lines.Add("")
            $lines.Add("Generated: $($Report.GeneratedAt.ToString('yyyy-MM-dd'))  |  Warning window: $($Report.WarningDays) day(s)")
            $lines.Add("")
            $lines.Add("Total: $($Report.Summary.TotalCount)  |  Expired: $($Report.Summary.ExpiredCount)  |  Warning: $($Report.Summary.WarningCount)  |  Ok: $($Report.Summary.OkCount)")

            foreach ($bucket in @('Expired', 'Warning', 'Ok')) {
                $entries = $Report.$bucket
                $lines.Add("")
                $lines.Add("## $bucket")

                if (-not $entries -or $entries.Count -eq 0) {
                    $lines.Add("")
                    $lines.Add("_No secrets in this bucket._")
                    continue
                }

                $lines.Add("")
                $lines.Add("| Name | Status | Due Date | Days Until Due | Required By |")
                $lines.Add("|------|--------|----------|-----------------|-------------|")
                foreach ($entry in $entries) {
                    $requiredBy = ($entry.RequiredBy -join ', ')
                    $dueDate = $entry.DueDate.ToString('yyyy-MM-dd')
                    $lines.Add("| $($entry.Name) | $($entry.Status) | $dueDate | $($entry.DaysUntilDue) | $requiredBy |")
                }
            }

            return ($lines -join "`n")
        }
    }
}

function Import-SecretConfig {
    <#
    .SYNOPSIS
        Loads and validates a secret rotation configuration file.
    .DESCRIPTION
        Reads a JSON file describing the default warning window and the
        collection of secrets to evaluate. Validates that the file exists,
        parses as JSON, and that every secret entry has the fields required
        to compute a rotation status (name, lastRotated, rotationPolicyDays).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        throw "Secret config file not found at path '$Path'."
    }

    $raw = Get-Content -Path $Path -Raw

    try {
        $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Invalid JSON in secret config file '$Path': $($_.Exception.Message)"
    }

    if (-not $parsed.secrets -or $parsed.secrets.Count -eq 0) {
        throw "Secret config file '$Path' must contain a non-empty 'secrets' array."
    }

    $requiredFields = @('name', 'lastRotated', 'rotationPolicyDays')
    $secrets = foreach ($secret in $parsed.secrets) {
        foreach ($field in $requiredFields) {
            if ($null -eq $secret.$field -or $secret.$field -eq '') {
                throw "Secret entry '$($secret.name)' in '$Path' is missing required field '$field'."
            }
        }

        [PSCustomObject]@{
            Name               = $secret.name
            LastRotated        = $secret.lastRotated
            RotationPolicyDays = $secret.rotationPolicyDays
            RequiredBy         = @($secret.requiredBy)
        }
    }

    $warningDays = if ($null -ne $parsed.warningDays) { [int]$parsed.warningDays } else { 14 }

    [PSCustomObject]@{
        WarningDays = $warningDays
        Secrets     = @($secrets)
    }
}

Export-ModuleMember -Function Get-SecretRotationStatus, New-SecretRotationReport, Format-SecretRotationReport, Import-SecretConfig
