#requires -Version 7.0
<#
.SYNOPSIS
    Dependency License Checker — parse a dependency manifest, look up each
    dependency's license, classify it against an allow-list / deny-list and emit
    a compliance report.

.DESCRIPTION
    Supported manifest formats:
      * package.json     (npm — "dependencies" + "devDependencies")
      * requirements.txt (pip — "name==version" style lines)

    For every dependency the script looks up its license (Get-DependencyLicense,
    deliberately small so it is trivial to Mock in tests or swap for a real
    registry call) and classifies the result (Get-LicenseStatus):
      * approved — license appears on the allow-list
      * denied   — license appears on the deny-list (deny wins over allow)
      * unknown  — license could not be determined, or is on neither list

    The file is safe to dot-source (e.g. by Pester): the "main" entry point at the
    bottom only runs when the file is executed directly, not when dot-sourced.

.PARAMETER ManifestPath
    Path to the dependency manifest (package.json or requirements.txt).

.PARAMETER ConfigPath
    Path to a JSON config file containing "allowList" and "denyList" arrays.

.PARAMETER LicenseDbPath
    Path to a JSON file mapping dependency name -> license string. This stands in
    for a real license-lookup service and keeps the checker deterministic/offline.

.PARAMETER Format
    Output format: text (default), json, markdown, or summary.

.PARAMETER Label
    Optional label echoed on the machine-readable RESULT line. Useful when a CI
    matrix runs several fixtures so each line can be told apart.

.PARAMETER FailOnViolation
    When set, the script exits with code 1 if any dependency is denied. By default
    the script is report-only and exits 0 (so a CI job can report without failing).

.EXAMPLE
    ./DependencyLicenseChecker.ps1 -ManifestPath package.json `
        -ConfigPath license-config.json -LicenseDbPath license-db.json -Format summary
#>
[CmdletBinding()]
param(
    [string] $ManifestPath,
    [string] $ConfigPath,
    [string] $LicenseDbPath,
    [ValidateSet('text', 'json', 'markdown', 'summary')]
    [string] $Format = 'text',
    [string] $Label = '',
    [switch] $FailOnViolation
)

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# Get-LicenseStatus
#   Classify a single license string against the allow/deny lists.
#   Precedence: unknown-license -> deny -> allow -> unknown-classification.
#   Deny intentionally wins over allow so an accidentally double-listed license
#   still fails closed.
# ---------------------------------------------------------------------------
function Get-LicenseStatus {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string] $License,

        [string[]] $AllowList = @(),

        [string[]] $DenyList = @()
    )

    # No license could be determined -> we simply do not know.
    if ([string]::IsNullOrWhiteSpace($License)) {
        return 'unknown'
    }

    # Deny wins over allow (fail closed).
    if ($DenyList -contains $License) {
        return 'denied'
    }

    if ($AllowList -contains $License) {
        return 'approved'
    }

    # Known license but classified by neither list.
    return 'unknown'
}

# ---------------------------------------------------------------------------
# Read-DependencyManifest
#   Detect the manifest type by file name and dispatch to the right parser.
#   Returns an array of [pscustomobject]@{ Name; Version }.
# ---------------------------------------------------------------------------
function Read-DependencyManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Manifest file not found: $Path"
    }

    $leaf = Split-Path -Leaf $Path

    if ($leaf -ieq 'package.json' -or $leaf -like '*.json') {
        return Read-PackageJson -Path $Path
    }
    elseif ($leaf -ieq 'requirements.txt' -or $leaf -like '*.txt') {
        return Read-RequirementsTxt -Path $Path
    }
    else {
        throw "Unsupported manifest type: '$leaf' (expected package.json or requirements.txt)"
    }
}

# ---------------------------------------------------------------------------
# Read-PackageJson
#   Parse an npm package.json, merging "dependencies" then "devDependencies".
#   PSCustomObject is used (not -AsHashtable) so JSON declaration order is kept.
# ---------------------------------------------------------------------------
function Read-PackageJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    try {
        $json = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    }
    catch {
        throw "Failed to parse package.json '$Path': $($_.Exception.Message)"
    }

    $deps = [System.Collections.Generic.List[object]]::new()

    if ($null -ne $json) {
        foreach ($section in @('dependencies', 'devDependencies')) {
            $prop = $json.PSObject.Properties[$section]
            if ($prop -and $null -ne $prop.Value) {
                foreach ($entry in $prop.Value.PSObject.Properties) {
                    $deps.Add([pscustomobject]@{
                        Name    = [string]$entry.Name
                        Version = [string]$entry.Value
                    })
                }
            }
        }
    }

    return $deps.ToArray()
}

# ---------------------------------------------------------------------------
# Read-RequirementsTxt
#   Parse a pip requirements.txt. Skips comments, blank lines and pip options
#   (-r / -e / --hash …); strips inline comments and environment markers.
# ---------------------------------------------------------------------------
function Read-RequirementsTxt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    $deps  = [System.Collections.Generic.List[object]]::new()
    $lines = @(Get-Content -LiteralPath $Path)

    foreach ($raw in $lines) {
        $line = $raw.Trim()
        if ($line -eq '' -or $line.StartsWith('#') -or $line.StartsWith('-')) {
            continue
        }

        # Strip inline comments (" # ...") and environment markers ("; marker").
        $line = ($line -split '\s+#', 2)[0].Trim()
        $line = ($line -split ';', 2)[0].Trim()
        if ($line -eq '') { continue }

        # name[extras] (op version)?  — operator/version are optional.
        if ($line -match '^([A-Za-z0-9_.\-]+)\s*(?:\[[^\]]*\])?\s*(?:(===|==|~=|!=|>=|<=|>|<)\s*([^\s,]+))?') {
            $version = if ($matches.ContainsKey(3)) { $matches[3] } else { '' }
            $deps.Add([pscustomobject]@{
                Name    = $matches[1]
                Version = $version
            })
        }
    }

    return $deps.ToArray()
}

# ---------------------------------------------------------------------------
# Read-LicenseConfig
#   Load allow-list / deny-list from a JSON config file. Missing keys default to
#   empty arrays so a partial config is still usable.
# ---------------------------------------------------------------------------
function Read-LicenseConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "License config file not found: $Path"
    }

    try {
        $h = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
    }
    catch {
        throw "Failed to parse license config '$Path': $($_.Exception.Message)"
    }
    if ($null -eq $h) { $h = @{} }

    $allow = if ($h.ContainsKey('allowList')) { [string[]]@($h['allowList']) } else { [string[]]@() }
    $deny  = if ($h.ContainsKey('denyList'))  { [string[]]@($h['denyList'])  } else { [string[]]@() }

    return [pscustomobject]@{
        AllowList = $allow
        DenyList  = $deny
    }
}

# ---------------------------------------------------------------------------
# Read-LicenseDatabase
#   Load the (mock) name -> license map from JSON into a hashtable. A null value
#   in the JSON is preserved and treated by Get-DependencyLicense as "unknown".
# ---------------------------------------------------------------------------
function Read-LicenseDatabase {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "License database file not found: $Path"
    }

    try {
        $h = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
    }
    catch {
        throw "Failed to parse license database '$Path': $($_.Exception.Message)"
    }

    if ($null -eq $h) { return @{} }
    return $h
}

# ---------------------------------------------------------------------------
# Get-DependencyLicense
#   The "license lookup". Kept intentionally tiny and side-effect free so tests
#   can Mock it, or so it can later be replaced by a real registry/API call.
#   Returns the license string, or $null when the license is unknown.
# ---------------------------------------------------------------------------
function Get-DependencyLicense {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [hashtable] $Database = @{}
    )

    if ($Database.ContainsKey($Name)) {
        $lic = $Database[$Name]
        if ([string]::IsNullOrWhiteSpace([string]$lic)) {
            return $null
        }
        return [string]$lic
    }

    return $null
}

# ---------------------------------------------------------------------------
# New-ComplianceReport
#   Tie the pieces together: for each dependency look up its license and classify
#   it, then summarise. Returns a report object with Dependencies, Summary and a
#   Compliant flag (Compliant = no denied dependencies).
# ---------------------------------------------------------------------------
function New-ComplianceReport {
    [CmdletBinding()]
    param(
        [object[]] $Dependencies = @(),

        [hashtable] $Database = @{},

        [string[]] $AllowList = @(),

        [string[]] $DenyList = @()
    )

    $deps  = @($Dependencies)
    $items = @(
        foreach ($d in $deps) {
            $license = Get-DependencyLicense -Name $d.Name -Database $Database
            $status  = Get-LicenseStatus -License $license -AllowList $AllowList -DenyList $DenyList
            [pscustomobject]@{
                Name    = $d.Name
                Version = $d.Version
                License = $license
                Status  = $status
            }
        }
    )

    $summary = [pscustomobject]@{
        Total    = $items.Count
        Approved = @($items | Where-Object { $_.Status -eq 'approved' }).Count
        Denied   = @($items | Where-Object { $_.Status -eq 'denied' }).Count
        Unknown  = @($items | Where-Object { $_.Status -eq 'unknown' }).Count
    }

    return [pscustomobject]@{
        Dependencies = $items
        Summary      = $summary
        Compliant    = ($summary.Denied -eq 0)
    }
}

# ---------------------------------------------------------------------------
# Format-ComplianceReport
#   Render a report object as text / json / markdown / summary. Every non-json
#   format ends with a stable, machine-parseable RESULT line so CI can assert on
#   exact values regardless of the human-facing format chosen.
# ---------------------------------------------------------------------------
function Format-ComplianceReport {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        $Report,

        [ValidateSet('text', 'json', 'markdown', 'summary')]
        [string] $Format = 'text',

        [string] $Label = ''
    )

    $s          = $Report.Summary
    $compliant  = if ($Report.Compliant) { 'true' } else { 'false' }
    $resultLine = "RESULT label=$Label total=$($s.Total) approved=$($s.Approved) denied=$($s.Denied) unknown=$($s.Unknown) compliant=$compliant"

    switch ($Format) {
        'summary' {
            return $resultLine
        }
        'json' {
            return ($Report | ConvertTo-Json -Depth 6)
        }
        'markdown' {
            $sb = [System.Text.StringBuilder]::new()
            [void]$sb.AppendLine('# Dependency License Compliance Report')
            [void]$sb.AppendLine('')
            [void]$sb.AppendLine('| Dependency | Version | License | Status |')
            [void]$sb.AppendLine('| --- | --- | --- | --- |')
            foreach ($d in $Report.Dependencies) {
                $lic = if ($d.License) { $d.License } else { '(unknown)' }
                [void]$sb.AppendLine("| $($d.Name) | $($d.Version) | $lic | $($d.Status) |")
            }
            [void]$sb.AppendLine('')
            [void]$sb.AppendLine("**Total:** $($s.Total) &nbsp; **Approved:** $($s.Approved) &nbsp; **Denied:** $($s.Denied) &nbsp; **Unknown:** $($s.Unknown)")
            [void]$sb.AppendLine('')
            [void]$sb.AppendLine($resultLine)
            return $sb.ToString().TrimEnd()
        }
        default {
            # text
            $sb = [System.Text.StringBuilder]::new()
            [void]$sb.AppendLine('Dependency License Compliance Report')
            [void]$sb.AppendLine('====================================')
            foreach ($d in $Report.Dependencies) {
                $lic = if ($d.License) { $d.License } else { '(unknown)' }
                [void]$sb.AppendLine(('{0,-22} {1,-12} {2,-16} {3}' -f $d.Name, $d.Version, $lic, $d.Status))
            }
            [void]$sb.AppendLine('------------------------------------')
            [void]$sb.AppendLine("Total: $($s.Total)  Approved: $($s.Approved)  Denied: $($s.Denied)  Unknown: $($s.Unknown)")
            [void]$sb.AppendLine($resultLine)
            return $sb.ToString().TrimEnd()
        }
    }
}

# ---------------------------------------------------------------------------
# Invoke-LicenseCheck
#   High-level orchestration used by the main entry point. Reads all inputs,
#   builds and renders the report, and returns a structured result so callers
#   (and tests) can inspect Output / ExitCode / Report without dealing with
#   process exit. Errors are caught and reported with a meaningful message.
# ---------------------------------------------------------------------------
function Invoke-LicenseCheck {
    [CmdletBinding()]
    param(
        [string] $ManifestPath,
        [string] $ConfigPath,
        [string] $LicenseDbPath,
        [string] $Format = 'text',
        [string] $Label = '',
        [switch] $FailOnViolation
    )

    try {
        if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
            throw 'ManifestPath is required.'
        }

        $deps = Read-DependencyManifest -Path $ManifestPath

        $config = if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
            Read-LicenseConfig -Path $ConfigPath
        }
        else {
            [pscustomobject]@{ AllowList = [string[]]@(); DenyList = [string[]]@() }
        }

        $db = if (-not [string]::IsNullOrWhiteSpace($LicenseDbPath)) {
            Read-LicenseDatabase -Path $LicenseDbPath
        }
        else {
            @{}
        }

        $report = New-ComplianceReport -Dependencies $deps -Database $db `
            -AllowList $config.AllowList -DenyList $config.DenyList

        $output = Format-ComplianceReport -Report $report -Format $Format -Label $Label

        $exitCode = if ($FailOnViolation -and -not $report.Compliant) { 1 } else { 0 }

        return [pscustomobject]@{
            Output   = $output
            ExitCode = $exitCode
            Report   = $report
            IsError  = $false
        }
    }
    catch {
        return [pscustomobject]@{
            Output   = "ERROR: $($_.Exception.Message)"
            ExitCode = 2
            Report   = $null
            IsError  = $true
        }
    }
}

# ---------------------------------------------------------------------------
# Main entry point — runs only when the script is executed directly, NOT when
# it is dot-sourced (InvocationName is '.' for a dot-source).
# ---------------------------------------------------------------------------
if ($MyInvocation.InvocationName -ne '.') {
    $result = Invoke-LicenseCheck -ManifestPath $ManifestPath -ConfigPath $ConfigPath `
        -LicenseDbPath $LicenseDbPath -Format $Format -Label $Label -FailOnViolation:$FailOnViolation

    if ($result.IsError) {
        Write-Error $result.Output
    }
    else {
        Write-Output $result.Output
    }

    exit $result.ExitCode
}
