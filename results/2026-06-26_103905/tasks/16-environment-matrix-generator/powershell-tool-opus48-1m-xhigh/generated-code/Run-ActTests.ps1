#!/usr/bin/env pwsh
<#
.SYNOPSIS
    End-to-end test harness: runs the workflow through `act` for several fixture
    configs and asserts exact expected values from the captured output.

.DESCRIPTION
    For each selected test case this harness:
      1. Builds a throwaway git repo in the system temp dir containing the
         project files plus that case's fixture copied to matrix-config.json.
      2. Runs `act push --rm` against the workflow (using the project's .actrc
         to pin the pwsh/Pester container image).
      3. Appends the full act output to act-result.txt (clearly delimited).
      4. Asserts act exited 0, the Pester job passed, the generated matrix
         expanded to the EXACT known-good combinations, every job reports
         "Job succeeded", and the final report line is present.

    Cases are run in order and the harness stops at the first failing case so a
    structural problem does not burn repeated `act` runs.

.PARAMETER Cases
    Subset of case names to run (basic, features, includes). Default: all.

.PARAMETER Append
    Append to act-result.txt instead of truncating it first.
#>
[CmdletBinding()]
param(
    [string[]] $Cases,
    [switch]   $Append
)

$ErrorActionPreference = 'Stop'
$root       = $PSScriptRoot
$resultFile = Join-Path $root 'act-result.txt'

# ---------------------------------------------------------------------------
# Case oracles. Each "Combos" entry is the canonical "key=value;..." form
# (keys sorted alphabetically) of one expected job in the generated matrix.
# These are hand-derived (an independent oracle), NOT produced by the code
# under test.
# ---------------------------------------------------------------------------
$allCases = @(
    @{
        Name        = 'basic'
        Fixture     = 'fixtures/basic.json'
        Count       = 3
        MaxParallel = '2'
        FailFast    = 'false'
        Combos      = @(
            'node=18;os=ubuntu-latest'
            'node=20;os=ubuntu-latest'
            'node=20;os=windows-latest'
        )
    }
    @{
        Name        = 'features'
        Fixture     = 'fixtures/features.json'
        Count       = 6
        MaxParallel = '4'
        FailFast    = 'true'
        Combos      = @(
            'feature=minimal;os=ubuntu-latest;python=3.11'
            'feature=full;os=ubuntu-latest;python=3.11'
            'feature=minimal;os=ubuntu-latest;python=3.12'
            'experimental=true;feature=full;os=ubuntu-latest;python=3.12'
            'feature=minimal;os=macos-latest;python=3.11'
            'feature=minimal;os=macos-latest;python=3.12'
        )
    }
    @{
        Name        = 'includes'
        Fixture     = 'fixtures/includes.json'
        Count       = 5
        MaxParallel = '3'
        FailFast    = 'false'
        Combos      = @(
            'cache=true;node=18;os=ubuntu-latest'
            'node=20;os=ubuntu-latest'
            'cache=true;node=18;os=windows-latest'
            'node=20;os=windows-latest'
            'experimental=true;node=22;os=macos-latest'
        )
    }
)

$expectedPesterPassed = 35   # MatrixGenerator.Tests (25) + Generate-Matrix.Tests (10)

$selected = if ($Cases) {
    $allCases | Where-Object { $Cases -contains $_.Name }
} else {
    $allCases
}
if (-not $selected) { throw "No matching cases for: $($Cases -join ', ')" }

# Canonicalise a parsed combo object into "k=v;..." with keys sorted.
function ConvertTo-Canonical {
    param([object] $Combo)
    $pairs = foreach ($p in ($Combo.PSObject.Properties | Sort-Object Name)) {
        "$($p.Name)=$($p.Value)"
    }
    return ($pairs -join ';')
}

# ---------------------------------------------------------------------------
# Result file header
# ---------------------------------------------------------------------------
if (-not $Append) {
    Set-Content -Path $resultFile -Value "ACT TEST RESULTS"
    Add-Content -Path $resultFile -Value ("Generated: " + [DateTime]::UtcNow.ToString('o'))
    Add-Content -Path $resultFile -Value ("Cases: " + (($selected | ForEach-Object { $_.Name }) -join ', '))
    Add-Content -Path $resultFile -Value ('=' * 70)
}

$projectItems = @('.github', 'src', 'tests', 'fixtures', 'Generate-Matrix.ps1', 'matrix-config.json', '.actrc')

$allPassed = $true

foreach ($case in $selected) {
    Write-Host ""
    Write-Host ("### Running act case: {0} ###" -f $case.Name) -ForegroundColor Cyan

    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("act-mtx-" + $case.Name + "-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    try {
        # --- Stage project files -------------------------------------------
        foreach ($item in $projectItems) {
            $src = Join-Path $root $item
            if (Test-Path $src) {
                Copy-Item -Path $src -Destination $tempDir -Recurse -Force
            }
        }
        # Drop this case's fixture in as the default config.
        Copy-Item -Path (Join-Path $root $case.Fixture) -Destination (Join-Path $tempDir 'matrix-config.json') -Force

        # --- Make it a git repo (act push needs one) -----------------------
        Push-Location $tempDir
        try {
            git init -q 2>&1 | Out-Null
            git -c user.email='harness@example.com' -c user.name='harness' add -A 2>&1 | Out-Null
            git -c user.email='harness@example.com' -c user.name='harness' commit -q -m "matrix case $($case.Name)" 2>&1 | Out-Null

            # --- Run act -------------------------------------------------------
            Write-Host "Running: act push --rm --pull=false ..."
            $actOutput = & act push --rm --pull=false -W .github/workflows/environment-matrix-generator.yml 2>&1
            $actExit   = $LASTEXITCODE
        }
        finally {
            Pop-Location
        }

        $actText = ($actOutput | Out-String)

        # --- Persist output ------------------------------------------------
        Add-Content -Path $resultFile -Value ""
        Add-Content -Path $resultFile -Value ("########## CASE: {0} (fixture {1}) ##########" -f $case.Name, $case.Fixture)
        Add-Content -Path $resultFile -Value ("act exit code: {0}" -f $actExit)
        Add-Content -Path $resultFile -Value ("expected combinations: {0}" -f $case.Count)
        Add-Content -Path $resultFile -Value ('-' * 70)
        Add-Content -Path $resultFile -Value $actText
        Add-Content -Path $resultFile -Value ("########## END CASE: {0} ##########" -f $case.Name)

        # --- Assertions ----------------------------------------------------
        $failures = [System.Collections.Generic.List[string]]::new()

        if ($actExit -ne 0) { $failures.Add("act exit code was $actExit (expected 0)") }

        # Pester job
        $pm = [regex]::Match($actText, 'PESTER-RESULT passed=(\d+) failed=(\d+)')
        if (-not $pm.Success) {
            $failures.Add("PESTER-RESULT line not found")
        }
        else {
            if ([int]$pm.Groups[2].Value -ne 0) { $failures.Add("Pester failed count = $($pm.Groups[2].Value) (expected 0)") }
            if ([int]$pm.Groups[1].Value -ne $expectedPesterPassed) {
                $failures.Add("Pester passed count = $($pm.Groups[1].Value) (expected $expectedPesterPassed)")
            }
        }

        # Scalar summary values emitted by Generate-Matrix.ps1
        if ($actText -notmatch [regex]::Escape("matrix-count=$($case.Count)")) {
            $failures.Add("missing 'matrix-count=$($case.Count)'")
        }
        if ($actText -notmatch [regex]::Escape("matrix-max-parallel=$($case.MaxParallel)")) {
            $failures.Add("missing 'matrix-max-parallel=$($case.MaxParallel)'")
        }
        if ($actText -notmatch [regex]::Escape("matrix-fail-fast=$($case.FailFast)")) {
            $failures.Add("missing 'matrix-fail-fast=$($case.FailFast)'")
        }

        # Build fan-out: parse every BUILD-COMBO line into the actual combo set.
        $comboMatches = [regex]::Matches($actText, 'BUILD-COMBO\s+(\{.*?\})')
        $actualCombos = @()
        foreach ($m in $comboMatches) {
            try {
                $actualCombos += (ConvertTo-Canonical ($m.Groups[1].Value | ConvertFrom-Json))
            } catch {
                $failures.Add("could not parse BUILD-COMBO json: $($m.Groups[1].Value)")
            }
        }
        if ($actualCombos.Count -ne $case.Count) {
            $failures.Add("BUILD-COMBO count = $($actualCombos.Count) (expected $($case.Count))")
        }
        $expectedSet = ($case.Combos | Sort-Object) -join '|'
        $actualSet   = ($actualCombos | Sort-Object) -join '|'
        if ($expectedSet -ne $actualSet) {
            $failures.Add("combination set mismatch.`n  expected: $expectedSet`n  actual:   $actualSet")
        }

        # Every job succeeded; none failed. Jobs = test + generate + build*count + report.
        $expectedJobs = $case.Count + 3
        $succeeded = ([regex]::Matches($actText, 'Job succeeded')).Count
        $failed    = ([regex]::Matches($actText, 'Job failed')).Count
        if ($failed -ne 0)              { $failures.Add("found $failed 'Job failed' line(s)") }
        if ($succeeded -ne $expectedJobs) { $failures.Add("'Job succeeded' count = $succeeded (expected $expectedJobs)") }

        # Final report line
        if ($actText -notmatch [regex]::Escape("ALL-DONE matrix-count=$($case.Count) build=success")) {
            $failures.Add("missing final 'ALL-DONE matrix-count=$($case.Count) build=success' line")
        }

        # --- Verdict -------------------------------------------------------
        if ($failures.Count -eq 0) {
            Add-Content -Path $resultFile -Value ("RESULT: PASS ({0} combinations, {1} jobs succeeded)" -f $case.Count, $expectedJobs)
            Write-Host ("CASE {0}: PASS" -f $case.Name) -ForegroundColor Green
        }
        else {
            $allPassed = $false
            Add-Content -Path $resultFile -Value "RESULT: FAIL"
            foreach ($f in $failures) { Add-Content -Path $resultFile -Value ("  - " + $f) }
            Write-Host ("CASE {0}: FAIL" -f $case.Name) -ForegroundColor Red
            foreach ($f in $failures) { Write-Host ("  - " + $f) -ForegroundColor Red }
            break   # stop early to conserve act runs
        }
    }
    finally {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Add-Content -Path $resultFile -Value ('=' * 70)
Add-Content -Path $resultFile -Value ("OVERALL: " + ($(if ($allPassed) { 'PASS' } else { 'FAIL' })))

if (-not $allPassed) {
    throw "One or more act test cases FAILED. See $resultFile."
}
Write-Host ""
Write-Host "ALL ACT TEST CASES PASSED" -ForegroundColor Green
