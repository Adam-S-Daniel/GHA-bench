#!/usr/bin/env pwsh
<#
.SYNOPSIS
    End-to-end act harness: runs the GitHub Actions workflow under nektos/act and
    asserts EXACT expected output for every fixture "test case".

.DESCRIPTION
    Per the task requirements:
      * Sets up an isolated temp git repo containing the project + all fixtures.
      * Runs `act push --rm` (a single run processes every fixture, keeping us
        well within the 3-run budget).
      * Saves the complete act output to act-result.txt (clearly delimited),
        together with a per-test-case assertion section.
      * Asserts act exited 0, that every job reports "Job succeeded", that the
        in-pipeline Pester suite passed, and that each fixture produced its
        known-good report lines (exact values, not just "some output").

    Exits 0 only if every assertion passes; non-zero otherwise.
#>
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path $PSScriptRoot -Parent
$actResult   = Join-Path $projectRoot 'act-result.txt'
$workflowRel = '.github/workflows/dependency-license-checker.yml'

# ---------------------------------------------------------------------------
# Known-good expected output per fixture (the "test cases"). Every line below
# must appear verbatim in the act output for the corresponding fixture.
# ---------------------------------------------------------------------------
$cases = @(
    @{
        Fixture = '01-node-mixed.json'
        Expect  = @(
            'Manifest: 01-node-mixed.json'
            'express@4.18.2 | MIT | approved'
            'gpl-tool@1.0.0 | GPL-3.0 | denied'
            'lodash@4.17.21 | MIT | approved'
            'mystery-lib@2.3.4 | UNKNOWN | unknown'
            'SUMMARY approved=2 denied=1 unknown=1 total=4'
            'RESULT FAIL'
        )
    },
    @{
        Fixture = '02-python-mixed.txt'
        Expect  = @(
            'Manifest: 02-python-mixed.txt'
            'agpl-package@0.5.0 | AGPL-3.0 | denied'
            'internal-thing@9.9.9 | UNKNOWN | unknown'
            'pyyaml@6.0 | MIT | approved'
            'requests@2.31.0 | Apache-2.0 | approved'
            'SUMMARY approved=2 denied=1 unknown=1 total=4'
            'RESULT FAIL'
        )
    },
    @{
        Fixture = '03-node-clean.json'
        Expect  = @(
            'Manifest: 03-node-clean.json'
            'axios@1.6.0 | MIT | approved'
            'react@18.2.0 | MIT | approved'
            'SUMMARY approved=2 denied=0 unknown=0 total=2'
            'RESULT PASS'
        )
    },
    @{
        Fixture = '04-empty.txt'
        Expect  = @(
            'Manifest: 04-empty.txt'
            'SUMMARY approved=0 denied=0 unknown=0 total=0'
            'RESULT PASS'
        )
    }
)

# Job display names that must each report success.
$expectedJobs = @('Pester unit tests', 'License compliance check', 'Compliance gate')

# ---------------------------------------------------------------------------
# 1) Build an isolated temp git repo with the project files + fixtures.
# ---------------------------------------------------------------------------
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("act-dlc-" + [guid]::NewGuid().ToString('n').Substring(0, 8))
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

Write-Host "Setting up isolated test repo at: $tempDir"
foreach ($item in '.actrc', '.github', 'src', 'bin', 'config', 'tests') {
    Copy-Item -Path (Join-Path $projectRoot $item) -Destination $tempDir -Recurse -Force
}

Push-Location $tempDir
try {
    git init -q 2>&1 | Out-Null
    git config user.email 'ci@example.com'
    git config user.name  'ci'
    git add -A 2>&1 | Out-Null
    git commit -q -m 'fixture under test' 2>&1 | Out-Null

    # -----------------------------------------------------------------------
    # 2) Run the workflow under act (single run covers all fixtures).
    #    --pull=false: the pwsh image is already present locally.
    # -----------------------------------------------------------------------
    Write-Host "Running: act push --rm --pull=false"
    $rawOutput = (& act push --rm --pull=false -W $workflowRel 2>&1 | Out-String)
    $actExit   = $LASTEXITCODE
}
finally {
    Pop-Location
}

# Strip ANSI colour codes so substring assertions are robust.
$cleanOutput = [regex]::Replace($rawOutput, "\x1b\[[0-9;]*m", "")

# ---------------------------------------------------------------------------
# 3) Persist the full act output + a delimited per-case section.
# ---------------------------------------------------------------------------
$header = @(
    '================================================================'
    " ACT RESULT  (generated $(Get-Date -Format 'u'))"
    " act exit code: $actExit"
    '================================================================'
    ''
    '===================== RAW ACT OUTPUT ==========================='
)
Set-Content -Path $actResult -Value $header -Encoding utf8
Add-Content -Path $actResult -Value $cleanOutput -Encoding utf8

# ---------------------------------------------------------------------------
# 4) Assertions.
# ---------------------------------------------------------------------------
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-Contains {
    param([string] $Haystack, [string] $Needle, [string] $Label)
    if ($Haystack.Contains($Needle)) {
        return "PASS  $Label"
    } else {
        $script:failures.Add($Label)
        return "FAIL  $Label  (missing: '$Needle')"
    }
}

$assertLines = [System.Collections.Generic.List[string]]::new()
$assertLines.Add('')
$assertLines.Add('===================== ASSERTIONS ===============================')

# 4a) act exited 0.
if ($actExit -eq 0) {
    $assertLines.Add("PASS  act exited 0")
} else {
    $failures.Add("act exit code $actExit")
    $assertLines.Add("FAIL  act exited $actExit (expected 0)")
}

# 4b) Every job reports success. NOTE: act right-pads job names to equal width
# inside the log prefix (e.g. "[Dependency License Checker/Compliance gate   ]"),
# so we match the prefix up to the name without requiring the closing bracket.
foreach ($job in $expectedJobs) {
    $assertLines.Add((Assert-Contains $cleanOutput "Dependency License Checker/$job" "job present: $job"))
}
$jobSucceeded = ([regex]::Matches($cleanOutput, 'Job succeeded')).Count
if ($jobSucceeded -ge $expectedJobs.Count) {
    $assertLines.Add("PASS  'Job succeeded' appears $jobSucceeded times (>= $($expectedJobs.Count))")
} else {
    $failures.Add("Job succeeded count $jobSucceeded")
    $assertLines.Add("FAIL  'Job succeeded' appears $jobSucceeded times (expected >= $($expectedJobs.Count))")
}

# 4c) The in-pipeline Pester suite passed (all 23 unit tests, run through act).
$assertLines.Add((Assert-Contains $cleanOutput 'Tests Passed: 23' 'in-pipeline Pester suite: 23 passed, 0 failed'))
$assertLines.Add((Assert-Contains $cleanOutput 'Failed: 0'        'in-pipeline Pester suite: no failures'))

# 4d) Each fixture (test case) produced its exact known-good report.
foreach ($case in $cases) {
    $assertLines.Add("--- test case: $($case.Fixture) ---")
    $assertLines.Add((Assert-Contains $cleanOutput "===== FIXTURE: $($case.Fixture) =====" "$($case.Fixture): delimiter present"))
    foreach ($line in $case.Expect) {
        $assertLines.Add((Assert-Contains $cleanOutput $line "$($case.Fixture): '$line'"))
    }
}

$assertLines.Add('')
if ($failures.Count -eq 0) {
    $assertLines.Add("RESULT: ALL ASSERTIONS PASSED")
} else {
    $assertLines.Add("RESULT: $($failures.Count) ASSERTION(S) FAILED")
}

Add-Content -Path $actResult -Value $assertLines -Encoding utf8

# Echo the assertion section to the console too.
$assertLines | ForEach-Object { Write-Host $_ }
Write-Host ""
Write-Host "Full act output + assertions saved to: $actResult"

# Best-effort cleanup of the temp repo.
Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue

if ($failures.Count -ne 0) {
    Write-Error "$($failures.Count) assertion(s) failed - see act-result.txt"
    exit 1
}
Write-Host "All act assertions passed."
exit 0
