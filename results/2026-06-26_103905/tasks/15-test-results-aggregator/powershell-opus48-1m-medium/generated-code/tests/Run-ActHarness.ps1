<#
.SYNOPSIS
    End-to-end act harness. Runs the GitHub Actions workflow under `act` for
    several test cases, each with different result-file fixtures, and asserts on
    the EXACT aggregated values the workflow prints.

.DESCRIPTION
    For each case:
      1. Build an isolated temp git repo containing the project files + that
         case's result files (written into results-input/).
      2. Run `act push --rm`, capturing all output.
      3. Append the output (clearly delimited) to act-result.txt.
      4. Assert act exited 0, every job shows "Job succeeded", and the printed
         AGG_* totals exactly match the known-good values for that input.

    At most 3 `act push` runs are performed (one per case).
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot      = Split-Path $PSScriptRoot -Parent
$ActResultFile = Join-Path $RepoRoot 'act-result.txt'

# Start each run with a fresh aggregate log.
Set-Content -LiteralPath $ActResultFile -Value "# act harness results`n" -Encoding utf8

# ---------------------------------------------------------------------------
# Test cases. Each declares the result files to drop into results-input/ and
# the exact aggregate values the workflow must print.
# ---------------------------------------------------------------------------
$cases = @(
    @{
        Name  = 'default-flaky'
        Files = @{
            'run1-junit.xml'   = (Get-Content (Join-Path $RepoRoot 'fixtures/run1-junit.xml') -Raw)
            'run2-results.json' = (Get-Content (Join-Path $RepoRoot 'fixtures/run2-results.json') -Raw)
        }
        # run1: Login P, Legacy S, AddToCart P, Checkout F
        # run2: Login P, Legacy S, AddToCart P, Checkout P  => Checkout flaky
        Expect = @{ Total = 8; Passed = 5; Failed = 1; Skipped = 2; FlakyCount = 1; Flaky = 'ShopSuite.Test_Checkout' }
    },
    @{
        Name  = 'all-green'
        Files = @{
            'a.xml' = @'
<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="G" tests="2" failures="0" skipped="0" time="3.0">
    <testcase name="Test_1" classname="G" time="1.0"/>
    <testcase name="Test_2" classname="G" time="2.0"/>
  </testsuite>
</testsuites>
'@
            'b.json' = @'
{ "tests": [
  { "name": "Test_1", "suite": "G", "status": "passed", "duration": 1.0 },
  { "name": "Test_3", "suite": "G", "status": "passed", "duration": 0.5 }
] }
'@
        }
        # No failures anywhere => nothing flaky.
        Expect = @{ Total = 4; Passed = 4; Failed = 0; Skipped = 0; FlakyCount = 0; Flaky = '' }
    },
    @{
        Name  = 'consistent-failure'
        Files = @{
            'a.xml' = @'
<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="H" tests="1" failures="1" skipped="0" time="1.0">
    <testcase name="Test_Bad" classname="H" time="1.0">
      <failure message="boom">stack</failure>
    </testcase>
  </testsuite>
</testsuites>
'@
            'b.json' = @'
{ "tests": [
  { "name": "Test_Bad", "suite": "H", "status": "failed", "duration": 1.0 }
] }
'@
        }
        # Fails in BOTH runs => failing but NOT flaky.
        Expect = @{ Total = 2; Passed = 0; Failed = 2; Skipped = 0; FlakyCount = 0; Flaky = '' }
    }
)

function New-CaseRepo {
    param([hashtable]$Case)

    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("act-" + $Case.Name + "-" + [System.IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Path $tmp | Out-Null

    # Copy the project files needed to run the workflow.
    foreach ($item in 'src', 'tests', 'fixtures', '.github', 'Invoke-Aggregation.ps1', '.actrc') {
        $srcPath = Join-Path $RepoRoot $item
        if (Test-Path $srcPath) {
            Copy-Item -Path $srcPath -Destination $tmp -Recurse -Force
        }
    }

    # Write this case's result files into a fresh results-input/ directory.
    $inputDir = Join-Path $tmp 'results-input'
    New-Item -ItemType Directory -Path $inputDir | Out-Null
    foreach ($fileName in $Case.Files.Keys) {
        Set-Content -LiteralPath (Join-Path $inputDir $fileName) -Value $Case.Files[$fileName] -Encoding utf8
    }

    # Initialise a git repo (act requires one) with a deterministic identity.
    Push-Location $tmp
    try {
        git init -q
        git config user.email 'harness@example.com'
        git config user.name  'harness'
        git add -A
        git -c commit.gpgsign=false commit -qm "case $($Case.Name)"
    } finally {
        Pop-Location
    }
    return $tmp
}

$allPassed = $true

foreach ($case in $cases) {
    Write-Host "=== Running act case: $($case.Name) ===" -ForegroundColor Cyan
    $repo = New-CaseRepo -Case $case

    Push-Location $repo
    try {
        # Run the workflow's push event. --rm cleans up containers afterwards.
        # --pull=false uses the locally-built act-ubuntu-pwsh image instead of
        # attempting a registry pull (which would fail for a local-only image).
        $output = & act push --rm --pull=false 2>&1 | Out-String
        $actExit = $LASTEXITCODE
    } finally {
        Pop-Location
    }

    # Append delimited output to the aggregate log (a required artifact).
    Add-Content -LiteralPath $ActResultFile -Value "`n========================================"
    Add-Content -LiteralPath $ActResultFile -Value "=== CASE: $($case.Name) (act exit $actExit) ==="
    Add-Content -LiteralPath $ActResultFile -Value "========================================"
    Add-Content -LiteralPath $ActResultFile -Value $output

    Remove-Item -Recurse -Force $repo -ErrorAction SilentlyContinue

    # ---- Assertions -------------------------------------------------------
    $caseOk = $true
    $fail = { param($msg) $script:caseOk = $false; $script:allPassed = $false; Write-Host "  FAIL: $msg" -ForegroundColor Red }

    if ($actExit -ne 0) { & $fail "act exited $actExit (expected 0)" }

    # Every job must report success; none may fail.
    $succeeded = ([regex]::Matches($output, 'Job succeeded')).Count
    if ($succeeded -lt 2) { & $fail "expected >=2 'Job succeeded' (got $succeeded)" }
    if ($output -match 'Job failed') { & $fail "output contains 'Job failed'" }

    # Exact-value assertions parsed from the AGG_* lines the script printed.
    $parse = {
        param($key)
        $m = [regex]::Match($output, "$key=(.*)")
        if ($m.Success) { $m.Groups[1].Value.Trim() } else { $null }
    }
    $checks = @(
        @{ Key = 'AGG_TOTAL';       Exp = "$($case.Expect.Total)" }
        @{ Key = 'AGG_PASSED';      Exp = "$($case.Expect.Passed)" }
        @{ Key = 'AGG_FAILED';      Exp = "$($case.Expect.Failed)" }
        @{ Key = 'AGG_SKIPPED';     Exp = "$($case.Expect.Skipped)" }
        @{ Key = 'AGG_FLAKY_COUNT'; Exp = "$($case.Expect.FlakyCount)" }
        @{ Key = 'AGG_FLAKY';       Exp = "$($case.Expect.Flaky)" }
    )
    foreach ($c in $checks) {
        $actual = (& $parse $c.Key)
        if ($actual -ne $c.Exp) { & $fail "$($c.Key): expected '$($c.Exp)', got '$actual'" }
    }

    if ($caseOk) { Write-Host "  PASS: $($case.Name)" -ForegroundColor Green }
}

Write-Host ""
if ($allPassed) {
    Write-Host "ALL ACT CASES PASSED" -ForegroundColor Green
    exit 0
} else {
    Write-Host "ONE OR MORE ACT CASES FAILED (see $ActResultFile)" -ForegroundColor Red
    exit 1
}
