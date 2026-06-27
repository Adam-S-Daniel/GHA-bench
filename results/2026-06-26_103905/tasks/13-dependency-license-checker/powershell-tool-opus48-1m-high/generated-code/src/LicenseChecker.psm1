#Requires -Version 7.0
<#
.SYNOPSIS
    LicenseChecker - parse a dependency manifest, look up each dependency's
    license (mockable), and classify it against allow/deny license lists.

.DESCRIPTION
    This module was built test-first (TDD). It is intentionally split into small,
    independently testable functions:

      ConvertFrom-DependencyManifest : parse package.json / requirements.txt
      Get-DependencyLicense          : mockable license lookup (local DB file)
      Get-LicenseStatus              : classify a license as approved/denied/unknown
      New-ComplianceReport           : combine the above into a report object array
      Format-ComplianceReport        : render the report to deterministic text

    The license lookup is deliberately backed by a local JSON "database" so it is
    fully deterministic and offline-friendly. In tests it is mocked; in CI a
    fixture database file stands in for a real registry.
#>

Set-StrictMode -Version Latest

function ConvertFrom-DependencyManifest {
    <#
    .SYNOPSIS
        Parse a dependency manifest into a list of { Name, Version } objects.
    .DESCRIPTION
        Supports two manifest formats, selected by file name:
          * package.json     - reads "dependencies" + "devDependencies"
          * requirements.txt  - reads "name==version" style lines
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Manifest file not found: '$Path'"
    }

    $fileName = Split-Path -Path $Path -Leaf
    $raw = Get-Content -LiteralPath $Path -Raw

    switch -Wildcard ($fileName) {
        'package.json' {
            try {
                $manifest = $raw | ConvertFrom-Json -ErrorAction Stop
            } catch {
                throw "Failed to parse package.json '$Path': $($_.Exception.Message)"
            }

            $deps = [System.Collections.Generic.List[object]]::new()
            foreach ($section in 'dependencies', 'devDependencies') {
                if ($manifest.PSObject.Properties.Name -contains $section -and $manifest.$section) {
                    foreach ($prop in $manifest.$section.PSObject.Properties) {
                        $deps.Add([PSCustomObject]@{
                            Name    = $prop.Name
                            Version = [string]$prop.Value
                        })
                    }
                }
            }
            return $deps.ToArray()
        }
        'requirements.txt' {
            $deps = [System.Collections.Generic.List[object]]::new()
            foreach ($line in ($raw -split "`r?`n")) {
                $trimmed = $line.Trim()
                # Skip blank lines and comments.
                if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#')) {
                    continue
                }
                # Match name followed by an optional version specifier (==, >=, etc).
                if ($trimmed -match '^([A-Za-z0-9_.\-]+)\s*(==|>=|<=|~=|!=|>|<)?\s*([A-Za-z0-9_.\-]+)?') {
                    $name = $Matches[1]
                    $version = if ($Matches[3]) { ($Matches[2] + $Matches[3]) } else { '' }
                    $deps.Add([PSCustomObject]@{
                        Name    = $name
                        Version = $version
                    })
                }
            }
            return $deps.ToArray()
        }
        default {
            throw "Unsupported manifest type '$fileName'. Supported: package.json, requirements.txt"
        }
    }
}

function Get-DependencyLicense {
    <#
    .SYNOPSIS
        Look up the license for a dependency. This is the "mockable" boundary.
    .DESCRIPTION
        A real implementation would query a package registry. To keep the tool
        deterministic and offline-testable, the lookup is backed by a local JSON
        database mapping package name -> license id. In unit tests this whole
        function is replaced with a Pester mock; in CI a fixture DB is supplied.
        Returns $null when the package is unknown.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$DatabasePath
    )

    if (-not (Test-Path -LiteralPath $DatabasePath)) {
        throw "License database not found: '$DatabasePath'"
    }

    try {
        $db = Get-Content -LiteralPath $DatabasePath -Raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Failed to parse license database '$DatabasePath': $($_.Exception.Message)"
    }

    if ($db.PSObject.Properties.Name -contains $Name) {
        $license = [string]$db.$Name
        if ([string]::IsNullOrWhiteSpace($license)) { return $null }
        return $license
    }
    return $null
}

function Get-LicenseStatus {
    <#
    .SYNOPSIS
        Classify a license id as 'approved', 'denied', or 'unknown'.
    .DESCRIPTION
        Comparison is case-insensitive. A $null/empty license (no license info
        found) is treated as 'unknown'. Deny takes precedence over allow only in
        the sense that a license appearing on both lists would be denied; in
        practice the lists should be disjoint.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$License,

        [Parameter(Mandatory)]
        [object]$Config
    )

    if ([string]::IsNullOrWhiteSpace($License)) {
        return 'unknown'
    }

    $deny  = @($Config.deny)  | ForEach-Object { "$_".ToLowerInvariant() }
    $allow = @($Config.allow) | ForEach-Object { "$_".ToLowerInvariant() }
    $key   = $License.ToLowerInvariant()

    if ($deny  -contains $key) { return 'denied' }
    if ($allow -contains $key) { return 'approved' }
    return 'unknown'
}

function New-ComplianceReport {
    <#
    .SYNOPSIS
        Build a compliance report: one row per dependency with its resolved
        license and compliance status.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Dependencies,

        [Parameter(Mandatory)]
        [object]$Config,

        [Parameter(Mandatory)]
        [string]$DatabasePath
    )

    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($dep in $Dependencies) {
        $license = Get-DependencyLicense -Name $dep.Name -DatabasePath $DatabasePath
        $status  = Get-LicenseStatus -License $license -Config $Config
        $rows.Add([PSCustomObject]@{
            Name    = $dep.Name
            Version = $dep.Version
            # Normalise a missing license to the literal 'UNKNOWN' for display.
            License = if ([string]::IsNullOrWhiteSpace($license)) { 'UNKNOWN' } else { $license }
            Status  = $status
        })
    }
    return $rows.ToArray()
}

function Format-ComplianceReport {
    <#
    .SYNOPSIS
        Render a compliance report to deterministic, machine-parseable text.
    .DESCRIPTION
        Emits one line per dependency in the form:
            [STATUS] name@version -> LICENSE
        followed by a SUMMARY line with exact counts and a RESULT verdict.
        The output is stable (no timestamps) so CI can assert on exact values.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Report
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    $approved = 0; $denied = 0; $unknown = 0

    foreach ($row in $Report) {
        switch ($row.Status) {
            'approved' { $approved++ }
            'denied'   { $denied++ }
            default    { $unknown++ }
        }
        $lines.Add("[$($row.Status.ToUpperInvariant())] $($row.Name)@$($row.Version) -> $($row.License)")
    }

    $total = $Report.Count
    $lines.Add("SUMMARY: total=$total approved=$approved denied=$denied unknown=$unknown")

    # Treat any denied dependency as non-compliant. Unknowns are surfaced but do
    # not, by themselves, fail compliance (they warrant manual review).
    $verdict = if ($denied -gt 0) { 'NON-COMPLIANT' } else { 'COMPLIANT' }
    $lines.Add("RESULT: $verdict")

    return ($lines -join [Environment]::NewLine)
}

Export-ModuleMember -Function `
    ConvertFrom-DependencyManifest, `
    Get-DependencyLicense, `
    Get-LicenseStatus, `
    New-ComplianceReport, `
    Format-ComplianceReport
