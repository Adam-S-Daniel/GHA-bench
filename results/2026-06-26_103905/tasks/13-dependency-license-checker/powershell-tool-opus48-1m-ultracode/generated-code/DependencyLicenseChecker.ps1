#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Dependency License Checker — parses a dependency manifest, resolves each
    dependency's license, and reports its compliance status against an
    allow-list / deny-list of licenses.

.DESCRIPTION
    Supported manifests:
      * package.json      (npm — "dependencies" + "devDependencies")
      * requirements.txt  (pip — one requirement per line)

    The license of each dependency is resolved via Get-DependencyLicense. In a
    real system this would query a registry or scan installed packages; here it
    reads from a "license database" (a name -> license map) so the result is
    deterministic, and is mocked in the unit tests.

    Compliance status for each dependency is one of:
      * approved — license is on the allow-list
      * denied   — license is on the deny-list (deny takes precedence)
      * unknown  — license could not be resolved, or is on neither list

    The script is written so it can be BOTH:
      * dot-sourced (`. ./DependencyLicenseChecker.ps1`) to expose its functions
        for unit testing — the CLI body at the bottom is guarded and does NOT run
        on dot-source; and
      * executed (`./DependencyLicenseChecker.ps1 -ConfigPath ...`) as a CLI that
        prints a compliance report.

.PARAMETER ConfigPath
    Path to a JSON config file describing compliance policy and (optionally) the
    manifest / license-database locations. Shape:
        {
          "manifest":        "examples/package.json",   # optional
          "licenseDb":       "examples/licenses.json",   # optional
          "allow":           ["MIT", "Apache-2.0"],
          "deny":            ["GPL-3.0"],
          "failOnViolation": false                       # optional
        }
    Defaults to "compliance.config.json" in the current directory.

.PARAMETER ManifestPath
    Path to the dependency manifest. Overrides "manifest" from the config.

.PARAMETER LicenseDbPath
    Path to a JSON license database (a { "pkg-name": "LICENSE" } map) used by the
    default Get-DependencyLicense lookup. Overrides "licenseDb" from the config.

.PARAMETER Format
    Output format: Text (default), Json, or Markdown.

.PARAMETER FailOnViolation
    If set, the script exits with code 1 when any dependency is "denied".
    (Can also be enabled via "failOnViolation": true in the config file.)

.EXAMPLE
    ./DependencyLicenseChecker.ps1 -ConfigPath compliance.config.json -Format Text
#>
[CmdletBinding()]
param(
    # NOTE: parameters are intentionally NOT [Mandatory] so the file can be
    # dot-sourced in tests without PowerShell prompting for input. Required
    # values are validated explicitly inside Invoke-LicenseCheck with clear
    # error messages (requirement: handle errors gracefully).
    [string]$ConfigPath = 'compliance.config.json',
    [string]$ManifestPath,
    [string]$LicenseDbPath,
    [ValidateSet('Text', 'Json', 'Markdown')]
    [string]$Format = 'Text',
    [switch]$FailOnViolation
)

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# Manifest parsing
# ---------------------------------------------------------------------------

function Get-CleanVersion {
    <#
        Normalises a version specifier into a bare version string by stripping
        common range/operator prefixes (npm: ^ ~ >= etc; pip: == >= ~= etc).
        e.g. "^4.18.2" -> "4.18.2", ">=2.0" -> "2.0", "*" -> "*".
    #>
    param([string]$Raw)

    if ($null -eq $Raw) { return '' }
    $v = $Raw.Trim()
    # Remove a leading comparison/range operator and any following whitespace.
    $v = $v -replace '^\s*(===|==|~=|>=|<=|!=|\^|~|>|<|=|v)\s*', ''
    return $v.Trim()
}

function ConvertFrom-PackageJson {
    <# Parses an npm package.json into [pscustomobject]@{ Name; Version } items. #>
    param([Parameter(Mandatory)][string]$Content)

    try {
        $json = $Content | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Failed to parse package.json: $($_.Exception.Message)"
    }

    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($section in 'dependencies', 'devDependencies') {
        # Use PSObject.Properties so we can tell "absent" from "present but empty".
        $block = $json.PSObject.Properties[$section]
        if ($null -eq $block -or $null -eq $block.Value) { continue }
        foreach ($prop in $block.Value.PSObject.Properties) {
            $results.Add([pscustomobject]@{
                Name    = $prop.Name
                Version = Get-CleanVersion $prop.Value
                Scope   = $section
            })
        }
    }
    return $results.ToArray()
}

function ConvertFrom-RequirementsTxt {
    <# Parses a pip requirements.txt into [pscustomobject]@{ Name; Version } items. #>
    param([Parameter(Mandatory)][string]$Content)

    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($line in ($Content -split "`r?`n")) {
        $trimmed = $line.Trim()
        if ($trimmed -eq '') { continue }                 # blank line
        if ($trimmed.StartsWith('#')) { continue }        # full-line comment
        if ($trimmed.StartsWith('-')) { continue }        # options (-r, --hash, ...)

        # Strip inline comments and environment markers (e.g. "; python_version<'3'").
        $spec = ($trimmed -split '\s+#')[0]
        $spec = ($spec -split ';')[0].Trim()
        if ($spec -eq '') { continue }

        # Split name from version on the first comparison operator.
        if ($spec -match '^([A-Za-z0-9._\-\[\]]+?)\s*(===|==|~=|>=|<=|!=|>|<|=)\s*(.+)$') {
            $name    = $Matches[1]
            $version = Get-CleanVersion $Matches[3]
        } else {
            $name    = $spec
            $version = ''
        }
        # Drop pip "extras" suffix, e.g. "requests[security]" -> "requests".
        $name = ($name -split '\[')[0].Trim()
        if ($name -eq '') { continue }

        $results.Add([pscustomobject]@{
            Name    = $name
            Version = $version
            Scope   = 'requirements'
        })
    }
    return $results.ToArray()
}

function Get-Dependencies {
    <#
        Reads a manifest file from disk and returns its dependencies as objects
        with Name / Version / Scope. The manifest type is detected from the file
        name (package.json -> npm; requirements*.txt -> pip).
    #>
    param([Parameter(Mandatory)][string]$ManifestPath)

    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        throw "Manifest file not found: '$ManifestPath'"
    }

    $content = Get-Content -LiteralPath $ManifestPath -Raw
    $leaf = Split-Path -Path $ManifestPath -Leaf

    if ($leaf -ieq 'package.json' -or $leaf -ilike '*.json') {
        return ConvertFrom-PackageJson -Content $content
    } elseif ($leaf -ilike '*requirements*.txt' -or $leaf -ilike '*.txt') {
        return ConvertFrom-RequirementsTxt -Content $content
    } else {
        throw "Unsupported manifest type: '$leaf'. Supported: package.json, requirements.txt."
    }
}

# ---------------------------------------------------------------------------
# License resolution (the "lookup" — mocked in tests)
# ---------------------------------------------------------------------------

function Get-DependencyLicense {
    <#
        Resolves a dependency's license. This is the seam that unit tests mock.
        The default implementation looks the name up in a provided license
        database (a hashtable mapping name -> SPDX license id). Returns $null
        when the license is unknown.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$Version,
        [hashtable]$LicenseDatabase
    )

    if ($LicenseDatabase -and $LicenseDatabase.ContainsKey($Name)) {
        return $LicenseDatabase[$Name]
    }
    return $null
}

function Get-LicenseStatus {
    <#
        Classifies a license string against the allow/deny policy.
        Precedence: unresolved -> unknown; deny wins over allow.
    #>
    param(
        [string]$License,
        [string[]]$AllowList,
        [string[]]$DenyList
    )

    if ([string]::IsNullOrWhiteSpace($License)) { return 'unknown' }

    # -contains is case-insensitive for strings, which is forgiving of casing.
    if ($DenyList  -and ($DenyList  -contains $License)) { return 'denied' }
    if ($AllowList -and ($AllowList -contains $License)) { return 'approved' }
    return 'unknown'
}

# ---------------------------------------------------------------------------
# Report generation
# ---------------------------------------------------------------------------

function New-ComplianceReport {
    <#
        Builds the per-dependency compliance result set. Calls Get-DependencyLicense
        for each dependency (mockable) and classifies the result. Returns an array
        of [pscustomobject]@{ Name; Version; License; Status }.
    #>
    param(
        [Parameter(Mandatory)][object[]]$Dependencies,
        [string[]]$AllowList,
        [string[]]$DenyList,
        [hashtable]$LicenseDatabase
    )

    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($dep in $Dependencies) {
        $license = Get-DependencyLicense -Name $dep.Name -Version $dep.Version -LicenseDatabase $LicenseDatabase
        $status  = Get-LicenseStatus -License $license -AllowList $AllowList -DenyList $DenyList
        $results.Add([pscustomobject]@{
            Name    = $dep.Name
            Version = if ([string]::IsNullOrEmpty($dep.Version)) { '*' } else { $dep.Version }
            License = if ([string]::IsNullOrWhiteSpace($license)) { 'UNKNOWN' } else { $license }
            Status  = $status
        })
    }
    return $results.ToArray()
}

function Get-ComplianceSummary {
    <# Aggregates a report into total/approved/denied/unknown counts. #>
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Report)

    [pscustomobject]@{
        Total    = $Report.Count
        Approved = @($Report | Where-Object Status -eq 'approved').Count
        Denied   = @($Report | Where-Object Status -eq 'denied').Count
        Unknown  = @($Report | Where-Object Status -eq 'unknown').Count
    }
}

function Format-ComplianceReport {
    <#
        Renders a compliance report in the requested format. Text is the default
        and produces stable, greppable lines suitable for asserting exact values:
            [APPROVED] express@4.18.2 -> MIT
            Summary: total=4 approved=2 denied=1 unknown=1
            Result: NON-COMPLIANT
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Report,
        [ValidateSet('Text', 'Json', 'Markdown')][string]$Format = 'Text'
    )

    $summary = Get-ComplianceSummary -Report $Report
    $result  = if ($summary.Denied -gt 0) { 'NON-COMPLIANT' } else { 'COMPLIANT' }

    switch ($Format) {
        'Json' {
            return ([pscustomobject]@{
                dependencies = $Report
                summary      = $summary
                result       = $result
            } | ConvertTo-Json -Depth 6)
        }
        'Markdown' {
            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add('# Dependency License Compliance Report')
            $lines.Add('')
            $lines.Add('| Dependency | Version | License | Status |')
            $lines.Add('| --- | --- | --- | --- |')
            foreach ($r in $Report) {
                $lines.Add("| $($r.Name) | $($r.Version) | $($r.License) | $($r.Status.ToUpper()) |")
            }
            $lines.Add('')
            $lines.Add("**Summary:** total=$($summary.Total) approved=$($summary.Approved) denied=$($summary.Denied) unknown=$($summary.Unknown)")
            $lines.Add("**Result:** $result")
            return ($lines -join "`n")
        }
        default {
            # Text
            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add('Dependency License Compliance Report')
            $lines.Add('====================================')
            foreach ($r in $Report) {
                $tag = "[$($r.Status.ToUpper())]"
                $lines.Add("$tag $($r.Name)@$($r.Version) -> $($r.License)")
            }
            $lines.Add("Summary: total=$($summary.Total) approved=$($summary.Approved) denied=$($summary.Denied) unknown=$($summary.Unknown)")
            $lines.Add("Result: $result")
            return ($lines -join "`n")
        }
    }
}

# ---------------------------------------------------------------------------
# Config + orchestration
# ---------------------------------------------------------------------------

function Get-CheckerConfig {
    <#
        Loads and validates the JSON config file. Returns a normalised object
        with Allow/Deny arrays plus optional Manifest/LicenseDb/FailOnViolation.
    #>
    param([Parameter(Mandatory)][string]$ConfigPath)

    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        throw "Config file not found: '$ConfigPath'"
    }
    try {
        $cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Failed to parse config '$ConfigPath': $($_.Exception.Message)"
    }

    # Helper to read an optional string property without StrictMode errors.
    $get = { param($obj, $prop) if ($obj.PSObject.Properties[$prop]) { $obj.$prop } else { $null } }

    [pscustomobject]@{
        Allow           = @(& $get $cfg 'allow')
        Deny            = @(& $get $cfg 'deny')
        Manifest        = & $get $cfg 'manifest'
        LicenseDb       = & $get $cfg 'licenseDb'
        FailOnViolation = [bool](& $get $cfg 'failOnViolation')
    }
}

function Import-LicenseDatabase {
    <# Loads a license database JSON ({ "pkg": "LICENSE" }) into a hashtable. #>
    param([string]$LicenseDbPath)

    $db = @{}
    if ([string]::IsNullOrWhiteSpace($LicenseDbPath)) { return $db }
    if (-not (Test-Path -LiteralPath $LicenseDbPath -PathType Leaf)) {
        throw "License database file not found: '$LicenseDbPath'"
    }
    try {
        $obj = Get-Content -LiteralPath $LicenseDbPath -Raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Failed to parse license database '$LicenseDbPath': $($_.Exception.Message)"
    }
    foreach ($prop in $obj.PSObject.Properties) { $db[$prop.Name] = $prop.Value }
    return $db
}

function Invoke-LicenseCheck {
    <#
        Top-level orchestration: load config + license db, parse the manifest,
        build the report, and return both the rendered text and the structured
        report + summary. Throws clear errors for any missing inputs.
    #>
    param(
        [string]$ConfigPath = 'compliance.config.json',
        [string]$ManifestPath,
        [string]$LicenseDbPath,
        [string]$Format = 'Text'
    )

    $config = Get-CheckerConfig -ConfigPath $ConfigPath

    # Explicit param overrides config; config provides the fallback.
    $manifest = if ($ManifestPath)   { $ManifestPath }   else { $config.Manifest }
    $licDb    = if ($LicenseDbPath)  { $LicenseDbPath }  else { $config.LicenseDb }

    if ([string]::IsNullOrWhiteSpace($manifest)) {
        throw "No manifest specified. Provide -ManifestPath or set 'manifest' in the config."
    }

    $licenseDatabase = Import-LicenseDatabase -LicenseDbPath $licDb
    $dependencies    = Get-Dependencies -ManifestPath $manifest
    $report          = New-ComplianceReport -Dependencies $dependencies `
                          -AllowList $config.Allow -DenyList $config.Deny `
                          -LicenseDatabase $licenseDatabase
    $summary         = Get-ComplianceSummary -Report $report
    $rendered        = Format-ComplianceReport -Report $report -Format $Format

    [pscustomobject]@{
        Manifest        = $manifest
        Report          = $report
        Summary         = $summary
        Rendered        = $rendered
        FailOnViolation = $config.FailOnViolation
    }
}

# ---------------------------------------------------------------------------
# CLI entry point (guarded so dot-sourcing for tests does NOT run it)
# ---------------------------------------------------------------------------

function Invoke-Main {
    param(
        [string]$ConfigPath,
        [string]$ManifestPath,
        [string]$LicenseDbPath,
        [string]$Format,
        [switch]$FailOnViolation
    )

    try {
        $outcome = Invoke-LicenseCheck -ConfigPath $ConfigPath -ManifestPath $ManifestPath `
                       -LicenseDbPath $LicenseDbPath -Format $Format

        # IMPORTANT: print the report with Write-Host (the information/host stream)
        # rather than Write-Output. Write-Output would mix the report lines into
        # this function's return value, so the caller's `$code = Invoke-Main` would
        # capture the text instead of just the exit code. Write-Host still appears
        # on stdout / in CI logs.
        Write-Host $outcome.Rendered

        # Emit a markdown summary to the GitHub Actions job summary when available.
        if ($env:GITHUB_STEP_SUMMARY) {
            $md = Format-ComplianceReport -Report $outcome.Report -Format 'Markdown'
            Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value $md
        }

        $fail = $FailOnViolation.IsPresent -or $outcome.FailOnViolation
        if ($fail -and $outcome.Summary.Denied -gt 0) {
            # GitHub Actions error annotation — clean message, no stack noise.
            Write-Host "::error::Compliance check failed: $($outcome.Summary.Denied) denied license(s) found."
            return 1
        }
        return 0
    } catch {
        Write-Host "::error::Dependency license check error: $($_.Exception.Message)"
        return 1
    }
}

# The guard: $MyInvocation.InvocationName is '.' only when the file is being
# dot-sourced. In that case we skip the CLI body so tests get clean functions.
if ($MyInvocation.InvocationName -ne '.') {
    $exitCode = Invoke-Main -ConfigPath $ConfigPath -ManifestPath $ManifestPath `
                    -LicenseDbPath $LicenseDbPath -Format $Format -FailOnViolation:$FailOnViolation
    exit $exitCode
}
