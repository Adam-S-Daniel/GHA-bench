<#
.SYNOPSIS
    Act-based integration harness for the Test Results Aggregator workflow.

.DESCRIPTION
    Every test case is exercised end-to-end THROUGH the GitHub Actions workflow
    using nektos/act. For each case the harness:
      1. Creates a temporary git repo containing the project files plus that
         case's fixture data,
      2. Runs `act push --rm` (pointing FIXTURE_DIR at the case's data),
      3. Appends the full act output to act-result.txt (clearly delimited),
      4. Asserts act exited 0,
      5. Asserts every job reports "Job succeeded",
      6. Parses the emitted Markdown summary and asserts EXACT expected values
         (totals + flaky tests) for that case's known input.

.PARAMETER Cases
    Comma-separated indices of cases to run (default: all).

.PARAMETER Append
    Append to act-result.txt instead of truncating it first.
#>
[CmdletBinding()]
param(
    [string]$Cases = 'all',
    [switch]$Append
)

$ErrorActionPreference = 'Stop'
$repoRoot   = $PSScriptRoot
$actResult  = Join-Path $repoRoot 'act-result.txt'
$workflowRel = '.github/workflows/test-results-aggregator.yml'

if (-not $Append -and (Test-Path $actResult)) { Remove-Item $actResult -Force }

# ---------------------------------------------------------------------------
# Test case definitions. Each Setup writes its fixture files into <repo>/<Dir>
# and the workflow is pointed at it via FIXTURE_DIR. Expected values are the
# known-good aggregate for that exact input.
# ---------------------------------------------------------------------------
$caseDefs = @(
    @{
        Name = 'default-bundled-fixtures'
        Dir  = './fixtures'    # the committed sample fixtures
        Setup = { param($repo) }   # nothing extra to write
        Expected = @{
            Total = 12; Passed = 6; Failed = 4; Skipped = 2
            Flaky = @('test_login', 'test_add_item'); NoFlaky = $false
        }
    },
    @{
        Name = 'all-green-no-flaky'
        Dir  = './ci-fixtures-green'
        Setup = {
            param($repo)
            $d = Join-Path $repo 'ci-fixtures-green'
            New-Item -ItemType Directory -Path $d -Force | Out-Null
            @'
<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="Green" tests="3" failures="0" errors="0" skipped="0" time="3.0">
    <testcase classname="Green" name="t_one"   time="1.0"/>
    <testcase classname="Green" name="t_two"   time="1.0"/>
    <testcase classname="Green" name="t_three" time="1.0"/>
  </testsuite>
</testsuites>
'@ | Set-Content -Path (Join-Path $d 'green.xml') -Encoding utf8
            @'
{ "tests": [
  { "name": "t_four", "suite": "Green", "status": "passed", "duration": 0.5 },
  { "name": "t_five", "suite": "Green", "status": "passed", "duration": 0.5 }
] }
'@ | Set-Content -Path (Join-Path $d 'green.json') -Encoding utf8
        }
        Expected = @{
            Total = 5; Passed = 5; Failed = 0; Skipped = 0
            Flaky = @(); NoFlaky = $true
        }
    },
    @{
        Name = 'mixed-with-one-flaky'
        Dir  = './ci-fixtures-flaky'
        Setup = {
            param($repo)
            $d = Join-Path $repo 'ci-fixtures-flaky'
            New-Item -ItemType Directory -Path $d -Force | Out-Null
            # Run A: alpha passes, beta fails, gamma skipped.
            @'
{ "tests": [
  { "name": "t_alpha", "suite": "Mix", "status": "passed",  "duration": 1.0 },
  { "name": "t_beta",  "suite": "Mix", "status": "failed",  "duration": 1.0 },
  { "name": "t_gamma", "suite": "Mix", "status": "skipped", "duration": 0.0 }
] }
'@ | Set-Content -Path (Join-Path $d 'runA.json') -Encoding utf8
            # Run B: alpha now FAILS (=> flaky), beta fails again (=> not flaky).
            @'
{ "tests": [
  { "name": "t_alpha", "suite": "Mix", "status": "failed", "duration": 1.0 },
  { "name": "t_beta",  "suite": "Mix", "status": "failed", "duration": 1.0 }
] }
'@ | Set-Content -Path (Join-Path $d 'runB.json') -Encoding utf8
        }
        Expected = @{
            Total = 5; Passed = 1; Failed = 3; Skipped = 1
            Flaky = @('t_alpha'); NoFlaky = $false
        }
    }
)

# Resolve which cases to run.
$indices = if ($Cases -eq 'all') { 0..($caseDefs.Count - 1) }
           else { $Cases.Split(',') | ForEach-Object { [int]$_.Trim() } }

# Files/dirs copied into each temp repo.
$projectItems = @(
    'TestResultsAggregator.ps1',
    'TestResultsAggregator.Tests.ps1',
    'fixtures',
    '.github',
    '.actrc'
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Get-SummaryBlock {
    # Extract the text the workflow prints between the BEGIN/END markers.
    param([string]$Output)
    $m = [regex]::Match($Output, '----- BEGIN SUMMARY -----(.*?)----- END SUMMARY -----',
        [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $m.Success) { return $null }
    return $m.Groups[1].Value
}

$failures = @()
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if ($Condition) {
        Write-Host "    [PASS] $Message" -ForegroundColor Green
    } else {
        Write-Host "    [FAIL] $Message" -ForegroundColor Red
        $script:failures += $Message
    }
}

# ---------------------------------------------------------------------------
# Run each case through act.
# ---------------------------------------------------------------------------
foreach ($i in $indices) {
    $case = $caseDefs[$i]
    Write-Host "`n=== Case [$i] $($case.Name) ===" -ForegroundColor Cyan

    # 1. Build an isolated temp git repo with the project + case fixtures.
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("act-trc-" + $case.Name + "-" + $i)
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    New-Item -ItemType Directory -Path $tmp | Out-Null

    foreach ($item in $projectItems) {
        $src = Join-Path $repoRoot $item
        if (Test-Path $src) { Copy-Item $src (Join-Path $tmp $item) -Recurse -Force }
    }
    & $case.Setup $tmp

    # Initialize a git repo (act/checkout require one with a commit).
    Push-Location $tmp
    try {
        git init -q
        git config user.email 'ci@example.com'
        git config user.name  'ci'
        git add -A
        git commit -q -m 'fixture' | Out-Null

        # 2. Run the workflow via act for the push event.
        Write-Host "    Running act (FIXTURE_DIR=$($case.Dir)) ..."
        # --pull=false: the pwsh image (act-ubuntu-pwsh) is built locally and is
        # not in any registry, so never attempt to pull it.
        $out = & act push --rm --pull=false --env "FIXTURE_DIR=$($case.Dir)" -W $workflowRel 2>&1 | Out-String
        $actExit = $LASTEXITCODE
    } finally {
        Pop-Location
    }

    # 3. Persist the output, clearly delimited.
    $header = "`n================ ACT OUTPUT: case [$i] $($case.Name) (FIXTURE_DIR=$($case.Dir)) ================`n"
    Add-Content -Path $actResult -Value $header
    Add-Content -Path $actResult -Value $out
    Add-Content -Path $actResult -Value "================ END case [$i] (act exit=$actExit) ================`n"

    # 4. Assert act exit code.
    Assert-True ($actExit -eq 0) "act exited 0 (got $actExit)"

    # 5. Assert every job succeeded (2 jobs: unit-tests + aggregate).
    $succeeded = ([regex]::Matches($out, 'Job succeeded')).Count
    Assert-True ($succeeded -ge 2) "both jobs report 'Job succeeded' (found $succeeded)"
    Assert-True ($out -notmatch 'Job failed') "no job reported 'Job failed'"

    # 6. Parse the summary and assert EXACT expected values.
    $block = Get-SummaryBlock -Output $out
    Assert-True ($null -ne $block) 'summary block was emitted'
    if ($block) {
        $e = $case.Expected
        Assert-True ($block -match "\| Total \| $($e.Total) \|")     "Total = $($e.Total)"
        Assert-True ($block -match "\| Passed \| $($e.Passed) \|")   "Passed = $($e.Passed)"
        Assert-True ($block -match "\| Failed \| $($e.Failed) \|")   "Failed = $($e.Failed)"
        Assert-True ($block -match "\| Skipped \| $($e.Skipped) \|") "Skipped = $($e.Skipped)"

        if ($e.NoFlaky) {
            Assert-True ($block -match 'No flaky tests detected') 'reports no flaky tests'
        } else {
            foreach ($f in $e.Flaky) {
                Assert-True ($block -match [regex]::Escape($f)) "flaky test listed: $f"
            }
        }
    }

    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------------
# Final verdict.
# ---------------------------------------------------------------------------
Write-Host "`n================ SUMMARY ================" -ForegroundColor Cyan
if ($failures.Count -eq 0) {
    Write-Host "All act integration assertions passed." -ForegroundColor Green
    Write-Host "Output saved to: $actResult"
    exit 0
} else {
    Write-Host "$($failures.Count) assertion(s) FAILED:" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}
