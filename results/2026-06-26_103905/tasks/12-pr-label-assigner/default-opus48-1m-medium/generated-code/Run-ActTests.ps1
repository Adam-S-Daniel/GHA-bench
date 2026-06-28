#!/usr/bin/env pwsh
# Run-ActTests.ps1
#
# End-to-end test harness. Every test case is executed THROUGH the GitHub
# Actions workflow via `act` (never against the script directly). For each case
# we build an isolated temp git repo containing the project files plus that
# case's fixture data, run `act push --rm`, capture the output, and assert on
# the EXACT expected label set.
#
# Output for every case is appended to ./act-result.txt (a required artifact).
#
# Usage:  pwsh ./Run-ActTests.ps1

$ErrorActionPreference = 'Stop'
$ProjectRoot = $PSScriptRoot
$ResultFile  = Join-Path $ProjectRoot 'act-result.txt'

# Fresh result file for this run.
Set-Content -LiteralPath $ResultFile -Value "PR Label Assigner — act end-to-end results`n" -Encoding utf8

# Files that make up the project (copied into each temp repo).
$ProjectFiles = @(
    'PRLabelAssigner.ps1',
    'Assign-Labels.ps1',
    'PRLabelAssigner.Tests.ps1',
    '.actrc'
)

# ---------------------------------------------------------------------------
# Test cases. Each defines its own rules + changed files and the EXACT labels
# the pipeline must produce. Expected values are computed by hand:
#
#   priorities: api=100, tests=80, ci=60, source=50, documentation=10
# ---------------------------------------------------------------------------
$Rules = @'
{
  "rules": [
    { "pattern": "docs/**",    "label": "documentation", "priority": 10 },
    { "pattern": "src/api/**", "label": "api",           "priority": 100 },
    { "pattern": "src/**",     "label": "source",        "priority": 50 },
    { "pattern": "*.test.*",   "label": "tests",         "priority": 80 },
    { "pattern": "*.md",       "label": "documentation", "priority": 10 },
    { "pattern": ".github/**", "label": "ci",            "priority": 60 }
  ]
}
'@

$Cases = @(
    @{
        Name          = 'mixed-multi-label-priority'
        Rules         = $Rules
        ChangedFiles  = @(
            'docs/intro.md',
            'src/api/users.js',
            'src/api/users.test.js',
            'src/utils/helpers.js'
        ) -join "`n"
        # documentation(10), api(100), source(50), tests(80) -> ordered desc
        ExpectedLabels = 'api,tests,source,documentation'
        ExpectedCount  = 4
    },
    @{
        Name          = 'docs-only-dedup'
        Rules         = $Rules
        ChangedFiles  = @('docs/a.md', 'docs/guide/b.md', 'README.md') -join "`n"
        # all map to 'documentation' and must be de-duplicated to a single label
        ExpectedLabels = 'documentation'
        ExpectedCount  = 1
    },
    @{
        Name          = 'no-matches-empty-set'
        Rules         = '{ "rules": [ { "pattern": "src/api/**", "label": "api", "priority": 1 } ] }'
        ChangedFiles  = @('LICENSE', 'Makefile') -join "`n"
        # nothing matches -> empty label set
        ExpectedLabels = ''
        ExpectedCount  = 0
    }
)

function Add-Result {
    param([string] $Text)
    Add-Content -LiteralPath $ResultFile -Value $Text -Encoding utf8
}

$failures = 0

foreach ($case in $Cases) {
    Write-Host "=== Test case: $($case.Name) ===" -ForegroundColor Cyan

    # 1. Build an isolated temp git repo with project files + this case's fixtures.
    $work = Join-Path ([System.IO.Path]::GetTempPath()) ("prlabel_" + $case.Name + '_' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $work '.github/workflows') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $work 'fixtures') -Force | Out-Null

    foreach ($f in $ProjectFiles) {
        Copy-Item -LiteralPath (Join-Path $ProjectRoot $f) -Destination (Join-Path $work $f) -Force
    }
    Copy-Item -LiteralPath (Join-Path $ProjectRoot '.github/workflows/pr-label-assigner.yml') `
              -Destination (Join-Path $work '.github/workflows/pr-label-assigner.yml') -Force

    Set-Content -LiteralPath (Join-Path $work 'fixtures/rules.json')         -Value $case.Rules        -Encoding utf8
    Set-Content -LiteralPath (Join-Path $work 'fixtures/changed-files.txt')  -Value $case.ChangedFiles -Encoding utf8

    # 2. Make it a git repo (actions/checkout@v4 + act expect a committed repo).
    Push-Location $work
    try {
        git init -q 2>&1 | Out-Null
        git config user.email 'ci@example.com' 2>&1 | Out-Null
        git config user.name  'CI' 2>&1 | Out-Null
        git add -A 2>&1 | Out-Null
        git commit -q -m "fixture: $($case.Name)" 2>&1 | Out-Null

        # 3. Run the pipeline through act, capturing combined output.
        # --pull=false: the pwsh image is built locally and must not be pulled.
        Write-Host "Running: act push --rm --pull=false" -ForegroundColor DarkGray
        $output = & act push --rm --pull=false -W .github/workflows/pr-label-assigner.yml 2>&1 | Out-String
        $actExit = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }

    # 4. Record the output, clearly delimited.
    Add-Result "================================================================"
    Add-Result "TEST CASE: $($case.Name)"
    Add-Result "Expected FINAL_LABELS=$($case.ExpectedLabels)"
    Add-Result "Expected LABEL_COUNT=$($case.ExpectedCount)"
    Add-Result "act exit code: $actExit"
    Add-Result "----------------------------------------------------------------"
    Add-Result $output
    Add-Result "================================================================`n"

    # 5. Assertions.
    $caseFailed = $false

    if ($actExit -ne 0) {
        Write-Host "  FAIL: act exited with code $actExit (expected 0)" -ForegroundColor Red
        $caseFailed = $true
    }

    # act prints a "FINAL_LABELS=..." line from the workflow step. Normalise it.
    $labelLine = ($output -split "`n" | Where-Object { $_ -match 'FINAL_LABELS=' } | Select-Object -Last 1)
    $actualLabels = if ($labelLine -match 'FINAL_LABELS=([^\r\n|]*)') { $matches[1].Trim() } else { '<none>' }

    $countLine = ($output -split "`n" | Where-Object { $_ -match 'LABEL_COUNT=' } | Select-Object -Last 1)
    $actualCount = if ($countLine -match 'LABEL_COUNT=([0-9]+)') { [int]$matches[1] } else { -1 }

    if ($actualLabels -ne $case.ExpectedLabels) {
        Write-Host "  FAIL: FINAL_LABELS was '$actualLabels' (expected '$($case.ExpectedLabels)')" -ForegroundColor Red
        $caseFailed = $true
    }
    else {
        Write-Host "  OK: FINAL_LABELS='$actualLabels'" -ForegroundColor Green
    }

    if ($actualCount -ne $case.ExpectedCount) {
        Write-Host "  FAIL: LABEL_COUNT was '$actualCount' (expected '$($case.ExpectedCount)')" -ForegroundColor Red
        $caseFailed = $true
    }
    else {
        Write-Host "  OK: LABEL_COUNT=$actualCount" -ForegroundColor Green
    }

    # Both jobs (unit-tests + assign-labels) must report success.
    $jobSucceeded = ([regex]::Matches($output, 'Job succeeded')).Count
    if ($jobSucceeded -lt 2) {
        Write-Host "  FAIL: expected >=2 'Job succeeded' lines, found $jobSucceeded" -ForegroundColor Red
        $caseFailed = $true
    }
    else {
        Write-Host "  OK: found $jobSucceeded 'Job succeeded' line(s)" -ForegroundColor Green
    }

    if ($caseFailed) { $failures++ }

    # Cleanup temp repo (keep result file).
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Add-Result "SUMMARY: $($Cases.Count - $failures)/$($Cases.Count) case(s) passed."
Write-Host ""
if ($failures -gt 0) {
    Write-Host "$failures of $($Cases.Count) case(s) FAILED. See $ResultFile" -ForegroundColor Red
    exit 1
}
Write-Host "All $($Cases.Count) case(s) passed. Results in $ResultFile" -ForegroundColor Green
