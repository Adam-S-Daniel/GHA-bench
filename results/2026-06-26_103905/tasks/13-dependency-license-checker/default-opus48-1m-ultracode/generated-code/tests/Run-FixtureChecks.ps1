#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Run the license compliance checker against every fixture manifest and print
    a clearly-delimited report per fixture. Used by the GitHub Actions workflow.
.DESCRIPTION
    Each fixture under tests/fixtures/manifests is processed by bin/check-licenses.ps1.
    The combined output is written both to stdout (so act/CI captures it) and to
    compliance-report.txt at the repository root (for artifact upload in real CI).

    Policy and license-database paths honor the POLICY_FILE / LICENSE_DB_FILE
    environment variables (set by the workflow) and fall back to config/ defaults.

    The checker is invoked as a child pwsh process so its `exit` call ends only
    that child, not this aggregator.
#>
$ErrorActionPreference = 'Stop'

$root        = Split-Path $PSScriptRoot -Parent
$cli         = Join-Path $root 'bin' 'check-licenses.ps1'
$manifestDir = Join-Path $PSScriptRoot 'fixtures' 'manifests'

# Resolve config from workflow env vars when present, else sensible defaults.
$policy = if ($env:POLICY_FILE)     { Join-Path $root $env:POLICY_FILE }     else { Join-Path $root 'config' 'policy.json' }
$db     = if ($env:LICENSE_DB_FILE) { Join-Path $root $env:LICENSE_DB_FILE } else { Join-Path $root 'config' 'licenses.json' }

if (-not (Test-Path $manifestDir)) { throw "Fixture directory not found: '$manifestDir'" }

$fixtures = Get-ChildItem -Path $manifestDir -File | Sort-Object Name
if ($fixtures.Count -eq 0) { throw "No fixtures found in '$manifestDir'" }

$report = [System.Collections.Generic.List[string]]::new()

foreach ($f in $fixtures) {
    $report.Add("===== FIXTURE: $($f.Name) =====")

    $out = & pwsh -NoLogo -NoProfile -File $cli `
        -ManifestPath $f.FullName -PolicyPath $policy -LicenseDbPath $db
    $childExit = $LASTEXITCODE

    foreach ($line in $out) { $report.Add([string]$line) }

    if ($childExit -ne 0) {
        throw "Checker exited $childExit for fixture '$($f.Name)'"
    }
    $report.Add("===== END FIXTURE: $($f.Name) =====")
}

# Persist for artifact upload in real CI, and echo to stdout for act/CI logs.
$reportPath = Join-Path $root 'compliance-report.txt'
Set-Content -Path $reportPath -Value $report -Encoding utf8

$report | ForEach-Object { Write-Output $_ }
Write-Output "Compliance report written to $reportPath"
