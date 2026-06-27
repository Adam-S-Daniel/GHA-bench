# SecretRotation.ps1
#
# Library of pure functions for the Secret Rotation Validator.
#
# Loading this file (via dot-sourcing) has NO side effects: it only defines
# functions. That keeps it safe to import from the Pester tests and from the
# thin CLI wrapper (Validate-SecretRotation.ps1).
#
# Domain model
# ------------
# A "secret" is mock metadata describing a credential we are tracking:
#   name               - human identifier
#   lastRotated        - ISO date (yyyy-MM-dd) it was last rotated
#   rotationPolicyDays - how many days a rotation is valid for
#   requiredBy         - list of services that depend on the secret
#
# For each secret we compute a due date (lastRotated + policy) and classify it:
#   expired  - already past due (daysUntilDue < 0)
#   warning  - due within the warning window (0 <= daysUntilDue <= window)
#   ok       - not due for a while (daysUntilDue > window)

Set-StrictMode -Version Latest

# Parse and validate a JSON config file, returning an array of secret objects.
# Throws descriptive errors so the CLI/CI can surface exactly what is wrong.
function Read-SecretConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Config file not found: '$Path'"
    }

    $raw = Get-Content -LiteralPath $Path -Raw

    try {
        $config = $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Config file '$Path' is not valid JSON: $($_.Exception.Message)"
    }

    if ($null -eq $config.PSObject.Properties['secrets']) {
        throw "Config file '$Path' is missing the top-level 'secrets' array"
    }

    # Normalise to an array even when there is a single object.
    $secrets = @($config.secrets)

    if ($secrets.Count -eq 0) {
        throw "Config file '$Path' contains no secrets"
    }

    $required = 'name', 'lastRotated', 'rotationPolicyDays'
    foreach ($s in $secrets) {
        foreach ($field in $required) {
            if ($null -eq $s.PSObject.Properties[$field] -or
                [string]::IsNullOrWhiteSpace([string]$s.$field)) {
                $who = if ($s.PSObject.Properties['name']) { $s.name } else { '<unnamed>' }
                throw "Secret '$who' is missing required field '$field'"
            }
        }

        # lastRotated must be a parseable date.
        [datetime]$parsed = [datetime]::MinValue
        if (-not [datetime]::TryParse([string]$s.lastRotated, [ref]$parsed)) {
            throw "Secret '$($s.name)' has an invalid lastRotated date: '$($s.lastRotated)'"
        }

        # rotationPolicyDays must be a positive integer.
        [int]$policy = 0
        if (-not [int]::TryParse([string]$s.rotationPolicyDays, [ref]$policy) -or $policy -le 0) {
            throw "Secret '$($s.name)' rotationPolicyDays must be a positive integer (got '$($s.rotationPolicyDays)')"
        }

        # Default requiredBy to an empty list when absent.
        if ($null -eq $s.PSObject.Properties['requiredBy']) {
            $s | Add-Member -NotePropertyName requiredBy -NotePropertyValue @() -Force
        }
    }

    return $secrets
}

# Enrich a single secret with computed rotation status.
function Get-RotationStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object]   $Secret,
        [Parameter(Mandatory)] [datetime] $AsOf,
        [Parameter(Mandatory)] [int]      $WarningWindowDays
    )

    $lastRotated = [datetime]::Parse([string]$Secret.lastRotated).Date
    $dueDate     = $lastRotated.AddDays([int]$Secret.rotationPolicyDays)
    # Whole-day difference between the due date and "now".
    $daysUntilDue = [int]([math]::Floor(($dueDate - $AsOf.Date).TotalDays))

    $status =
        if     ($daysUntilDue -lt 0)                  { 'expired' }
        elseif ($daysUntilDue -le $WarningWindowDays) { 'warning' }
        else                                          { 'ok' }

    [pscustomobject]@{
        name               = [string]$Secret.name
        lastRotated        = $lastRotated.ToString('yyyy-MM-dd')
        rotationPolicyDays = [int]$Secret.rotationPolicyDays
        dueDate            = $dueDate.ToString('yyyy-MM-dd')
        daysUntilDue       = $daysUntilDue
        status             = $status
        requiredBy         = @($Secret.requiredBy)
    }
}

# Build the full grouped report object from a list of raw secrets.
function New-RotationReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object[]] $Secrets,
        [Parameter(Mandatory)] [datetime] $AsOf,
        [Parameter(Mandatory)] [int]      $WarningWindowDays
    )

    $evaluated = foreach ($s in $Secrets) {
        Get-RotationStatus -Secret $s -AsOf $AsOf -WarningWindowDays $WarningWindowDays
    }
    $evaluated = @($evaluated)

    # Group, sorting each bucket by urgency (soonest due first).
    $expired = @($evaluated | Where-Object status -eq 'expired' | Sort-Object daysUntilDue)
    $warning = @($evaluated | Where-Object status -eq 'warning' | Sort-Object daysUntilDue)
    $ok      = @($evaluated | Where-Object status -eq 'ok'      | Sort-Object daysUntilDue)

    [pscustomobject]@{
        generatedAt       = $AsOf.ToString('yyyy-MM-dd')
        warningWindowDays = $WarningWindowDays
        summary           = [pscustomobject]@{
            expired = $expired.Count
            warning = $warning.Count
            ok      = $ok.Count
            total   = $evaluated.Count
        }
        groups            = [pscustomobject]@{
            expired = $expired
            warning = $warning
            ok      = $ok
        }
    }
}

# Render the report as pretty JSON.
function Format-RotationReportJson {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [object] $Report)

    # Depth 6 comfortably covers report -> groups -> array -> secret -> requiredBy.
    return ($Report | ConvertTo-Json -Depth 6)
}

# Render the report as a markdown document with one table per urgency group.
function Format-RotationReportMarkdown {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [object] $Report)

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('# Secret Rotation Report')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("_Generated: $($Report.generatedAt) | Warning window: $($Report.warningWindowDays) day(s)_")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("**Summary:** $($Report.summary.expired) expired, " +
        "$($Report.summary.warning) warning, $($Report.summary.ok) ok " +
        "($($Report.summary.total) total)")
    [void]$sb.AppendLine()

    # Section metadata: group key + display label + emoji-free status tag.
    $sections = @(
        @{ Key = 'expired'; Title = 'Expired';  Tag = 'EXPIRED' }
        @{ Key = 'warning'; Title = 'Warning';  Tag = 'WARNING' }
        @{ Key = 'ok';      Title = 'OK';       Tag = 'OK' }
    )

    foreach ($section in $sections) {
        $rows = @($Report.groups.$($section.Key))
        [void]$sb.AppendLine("## $($section.Title) ($($rows.Count))")
        [void]$sb.AppendLine()

        if ($rows.Count -eq 0) {
            [void]$sb.AppendLine('_None_')
            [void]$sb.AppendLine()
            continue
        }

        [void]$sb.AppendLine('| Secret | Status | Last Rotated | Due Date | Days Until Due | Required By |')
        [void]$sb.AppendLine('| --- | --- | --- | --- | ---: | --- |')
        foreach ($r in $rows) {
            $req = (@($r.requiredBy) -join ', ')
            [void]$sb.AppendLine("| $($r.name) | $($section.Tag) | $($r.lastRotated) | $($r.dueDate) | $($r.daysUntilDue) | $req |")
        }
        [void]$sb.AppendLine()
    }

    return $sb.ToString().TrimEnd()
}

# End-to-end orchestration: read config -> build report -> format.
function Invoke-SecretRotationValidator {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]   $Path,
        [Parameter(Mandatory)] [datetime] $AsOf,
        [Parameter(Mandatory)] [int]      $WarningWindowDays,
        [ValidateNotNullOrEmpty()] [string] $Format = 'markdown'
    )

    $secrets = Read-SecretConfig -Path $Path
    $report  = New-RotationReport -Secrets $secrets -AsOf $AsOf -WarningWindowDays $WarningWindowDays

    switch ($Format.ToLowerInvariant()) {
        'markdown' { return Format-RotationReportMarkdown -Report $report }
        'json'     { return Format-RotationReportJson -Report $report }
        default    { throw "Unsupported format: '$Format' (expected 'markdown' or 'json')" }
    }
}
