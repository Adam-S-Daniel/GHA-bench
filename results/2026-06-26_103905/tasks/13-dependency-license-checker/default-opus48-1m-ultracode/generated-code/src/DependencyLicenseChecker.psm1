<#
.SYNOPSIS
    DependencyLicenseChecker - parse a dependency manifest, look up each
    dependency's license, and classify it against an allow/deny license policy.

    This module is built test-first (red/green TDD). Functions are added one at a
    time, each driven by a failing Pester test in
    tests/DependencyLicenseChecker.Tests.ps1.
#>

# ---------------------------------------------------------------------------
# Internal helper: normalize a raw version spec to a bare version string.
# Strips range operators (^ ~ >= <= == ~= ! < >) by extracting the first
# dotted-numeric token. Falls back to the trimmed raw value (e.g. "*", "latest")
# when no numeric version is present.
# ---------------------------------------------------------------------------
function ConvertTo-NormalizedVersion {
    param([string] $Raw)

    if ([string]::IsNullOrWhiteSpace($Raw)) { return '' }
    if ($Raw -match '\d+(\.\d+)*') { return $Matches[0] }
    return $Raw.Trim()
}

<#
.SYNOPSIS
    Parse a dependency manifest and return a sorted list of dependencies.
.DESCRIPTION
    Supports npm-style package.json (.json) today. The manifest type is detected
    from the file extension. Each result is a [pscustomobject] with Name and
    Version properties. Names are lower-cased to a canonical form and results are
    sorted by name so downstream output is deterministic.
.PARAMETER Path
    Path to the manifest file.
#>
function Read-DependencyManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Manifest file not found: '$Path'"
    }

    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    $deps = [System.Collections.Generic.List[object]]::new()

    switch ($extension) {
        '.json' {
            # npm package.json: merge dependencies + devDependencies.
            $raw = Get-Content -LiteralPath $Path -Raw
            try {
                $json = $raw | ConvertFrom-Json
            } catch {
                throw "Failed to parse JSON manifest '$Path': $($_.Exception.Message)"
            }

            foreach ($section in 'dependencies', 'devDependencies') {
                $block = $json.$section
                if ($null -eq $block) { continue }
                foreach ($prop in $block.PSObject.Properties) {
                    $deps.Add([pscustomobject]@{
                        Name    = $prop.Name.ToLowerInvariant()
                        Version = ConvertTo-NormalizedVersion $prop.Value
                    })
                }
            }
        }
        { $_ -in '.txt', '.in' } {
            # pip requirements.txt: one requirement per line.
            $lines = Get-Content -LiteralPath $Path
            foreach ($line in $lines) {
                # Drop inline comments and environment markers, then trim.
                $clean = ($line -split '#', 2)[0]
                $clean = ($clean -split ';', 2)[0]
                $clean = $clean.Trim()

                if ([string]::IsNullOrWhiteSpace($clean)) { continue }
                # Skip pip options / includes (-r other.txt, --hash, -e ...).
                if ($clean.StartsWith('-')) { continue }

                # name, optional [extras], then the version spec (operator+value).
                if ($clean -match '^(?<name>[A-Za-z0-9._-]+)\s*(?:\[[^\]]*\])?\s*(?<spec>.*)$') {
                    $deps.Add([pscustomobject]@{
                        Name    = $Matches['name'].ToLowerInvariant()
                        Version = ConvertTo-NormalizedVersion $Matches['spec']
                    })
                }
            }
        }
        default {
            throw "Unsupported manifest type '$extension' for '$Path'. Supported: .json, .txt"
        }
    }

    # Deterministic ordering for stable reports/assertions.
    return $deps | Sort-Object Name
}

<#
.SYNOPSIS
    Classify a license string against an allow/deny policy.
.DESCRIPTION
    Returns one of: 'approved', 'denied', 'unknown'.
      * 'denied'   - license is on the deny list (deny takes precedence).
      * 'approved' - license is on the allow list.
      * 'unknown'  - license is missing, or on neither list.
    Matching is case-insensitive so 'mit' and 'MIT' are equivalent.
.PARAMETER License
    The license identifier (e.g. 'MIT'). May be null/empty if unknown.
.PARAMETER Policy
    Object with .Allow and .Deny string arrays.
#>
function Get-LicenseStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $License,

        [Parameter(Mandatory)]
        [object] $Policy
    )

    if ([string]::IsNullOrWhiteSpace($License)) { return 'unknown' }

    $needle = $License.Trim()
    $deny  = @($Policy.Deny)  | Where-Object { $_ }
    $allow = @($Policy.Allow) | Where-Object { $_ }

    # Deny wins over allow.
    if ($deny  -contains $needle) { return 'denied' }
    if ($allow -contains $needle) { return 'approved' }
    return 'unknown'
}

<#
.SYNOPSIS
    Load a license database (name -> license JSON map) into a case-insensitive
    hashtable that Get-DependencyLicense can query.
.DESCRIPTION
    In a real system this lookup would query a license registry or scan package
    metadata. Here it is backed by a static JSON file so runs are deterministic
    and offline-friendly (and so the lookup can be mocked in tests).
.PARAMETER Path
    Path to a JSON object mapping dependency name -> license id.
#>
function Import-LicenseDatabase {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "License database file not found: '$Path'"
    }

    try {
        $json = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    } catch {
        throw "Failed to parse license database '$Path': $($_.Exception.Message)"
    }

    # StringComparer.OrdinalIgnoreCase => case-insensitive name lookups.
    $db = [System.Collections.Hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($prop in $json.PSObject.Properties) {
        $db[$prop.Name] = $prop.Value
    }
    return $db
}

<#
.SYNOPSIS
    Look up the license for a dependency.  THIS is the seam that tests mock.
.DESCRIPTION
    Returns the license id recorded for $Name, or $null when the dependency is
    not in the database. Lookups are case-insensitive.
.PARAMETER Name
    Dependency name.
.PARAMETER Database
    Hashtable produced by Import-LicenseDatabase (or any name->license map).
#>
function Get-DependencyLicense {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [hashtable] $Database
    )

    if ($Database.ContainsKey($Name)) {
        return $Database[$Name]
    }
    return $null
}

<#
.SYNOPSIS
    Build a full compliance report for a manifest.
.DESCRIPTION
    Parses the manifest, looks up each dependency's license (via the mockable
    Get-DependencyLicense seam), classifies it against the policy, and returns a
    structured report: per-dependency Entries plus a Summary and an overall
    Result ('PASS' / 'FAIL').
.PARAMETER ManifestPath
    Path to the dependency manifest.
.PARAMETER Policy
    Object with .Allow and .Deny license arrays.
.PARAMETER Database
    name->license map used by Get-DependencyLicense.
.PARAMETER FailOnUnknown
    When set, dependencies with an unknown license also fail the overall result.
#>
function New-ComplianceReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ManifestPath,

        [Parameter(Mandatory)]
        [object] $Policy,

        [Parameter(Mandatory)]
        [hashtable] $Database,

        [switch] $FailOnUnknown
    )

    $dependencies = Read-DependencyManifest -Path $ManifestPath

    $entries = foreach ($dep in $dependencies) {
        $license = Get-DependencyLicense -Name $dep.Name -Database $Database
        $status  = Get-LicenseStatus -License $license -Policy $Policy
        [pscustomobject]@{
            Name    = $dep.Name
            Version = $dep.Version
            License = $license
            Status  = $status
        }
    }
    # Force an array even when there are 0 or 1 entries.
    $entries = @($entries)

    $summary = [pscustomobject]@{
        Approved = @($entries | Where-Object Status -EQ 'approved').Count
        Denied   = @($entries | Where-Object Status -EQ 'denied').Count
        Unknown  = @($entries | Where-Object Status -EQ 'unknown').Count
        Total    = $entries.Count
    }

    # Deny always fails; unknown fails only under the strict switch.
    $failed = ($summary.Denied -gt 0) -or ($FailOnUnknown -and $summary.Unknown -gt 0)

    return [pscustomobject]@{
        Manifest = [System.IO.Path]::GetFileName($ManifestPath)
        Entries  = $entries
        Summary  = $summary
        Result   = if ($failed) { 'FAIL' } else { 'PASS' }
    }
}

<#
.SYNOPSIS
    Render a compliance report to deterministic, human- and machine-readable text.
.DESCRIPTION
    Emits one '<name>@<version> | <license> | <status>' line per dependency, then
    a 'SUMMARY ...' line and a 'RESULT <PASS|FAIL>' line that downstream tooling
    (and the act test harness) can assert against. A null license renders as the
    literal token 'UNKNOWN'.
.PARAMETER Report
    Report object produced by New-ComplianceReport.
#>
function Format-ComplianceReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Report
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('DEPENDENCY LICENSE COMPLIANCE REPORT')
    $lines.Add("Manifest: $($Report.Manifest)")
    $lines.Add('----------------------------------------')

    foreach ($e in $Report.Entries) {
        $ref     = if ($e.Version) { "$($e.Name)@$($e.Version)" } else { $e.Name }
        $license = if ([string]::IsNullOrWhiteSpace($e.License)) { 'UNKNOWN' } else { $e.License }
        $lines.Add("$ref | $license | $($e.Status)")
    }

    $lines.Add('----------------------------------------')
    $s = $Report.Summary
    $lines.Add("SUMMARY approved=$($s.Approved) denied=$($s.Denied) unknown=$($s.Unknown) total=$($s.Total)")
    $lines.Add("RESULT $($Report.Result)")

    return $lines.ToArray()
}

# Public surface of the module.
Export-ModuleMember -Function `
    Read-DependencyManifest,
    Get-LicenseStatus,
    Import-LicenseDatabase,
    Get-DependencyLicense,
    New-ComplianceReport,
    Format-ComplianceReport
