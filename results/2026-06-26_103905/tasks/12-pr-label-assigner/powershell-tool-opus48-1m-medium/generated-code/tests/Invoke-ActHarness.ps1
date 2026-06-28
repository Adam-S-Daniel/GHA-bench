#!/usr/bin/env pwsh
<#
    Invoke-ActHarness.ps1

    End-to-end test harness that exercises the PR Label Assigner *through the
    GitHub Actions workflow* using nektos/act. Every test case:

      1. Gets its own throwaway git repo (project files + that case's fixture).
      2. Runs `act push --rm` against the real workflow.
      3. Has its full act output appended to act-result.txt (clearly delimited).
      4. Is asserted on: act exit code 0, every job "Job succeeded", and the
         EXACT expected LABELS / LABEL_COUNT values for that case's input.

    The harness is fail-fast: if any case fails (act error or assertion), it
    stops immediately so a broken pipeline costs a single act run rather than
    one per case.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Project root = parent of this tests/ directory.
$projectRoot = Split-Path $PSScriptRoot -Parent
$resultFile  = Join-Path $projectRoot 'act-result.txt'

# Start each run with a fresh result file.
if (Test-Path $resultFile) { Remove-Item $resultFile -Force }

# ---------------------------------------------------------------------------
# Test cases: (name, changed-files content, expected ordered LABELS, count)
#
# Expected values are derived by hand from fixtures/rules.json:
#   api=10, ci=15, tests=20, documentation=30, source=40 (lower = first)
# ---------------------------------------------------------------------------
$cases = @(
    [pscustomobject]@{
        Name          = 'multi-label-and-priority'
        ChangedFiles  = @(
            'docs/intro.md'
            'src/api/users.ps1'
            'src/api/users.test.ps1'
            'src/db/schema.ps1'
            'README.md'
        ) -join "`n"
        ExpectedLabels = 'api,tests,documentation,source'
        ExpectedCount  = 4
    }
    [pscustomobject]@{
        Name          = 'ci-and-docs-dedup'
        ChangedFiles  = @(
            '.github/workflows/build.yml'
            'docs/guide.md'
            'CHANGELOG.md'
        ) -join "`n"
        # build.yml -> ci(15); docs/guide.md -> documentation(30, via docs/** and *.md);
        # CHANGELOG.md -> documentation(30). documentation is de-duplicated.
        ExpectedLabels = 'ci,documentation'
        ExpectedCount  = 2
    }
    [pscustomobject]@{
        Name          = 'no-matches'
        ChangedFiles  = @(
            'LICENSE'
            'Makefile'
        ) -join "`n"
        ExpectedLabels = ''
        ExpectedCount  = 0
    }
)

function Strip-Ansi {
    param([string] $Text)
    # Remove ANSI colour/escape sequences so substring asserts are reliable.
    return ($Text -replace "`e\[[0-9;]*[A-Za-z]", '')
}

$caseNumber = 0
foreach ($case in $cases) {
    $caseNumber++
    Write-Host "=== Test case $caseNumber/$($cases.Count): $($case.Name) ===" -ForegroundColor Cyan

    # --- Set up an isolated git repo with this case's fixture data ---------
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("act-case-{0}-{1}" -f $caseNumber, [System.IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null

    try {
        # Copy project files needed by the workflow into the temp repo.
        foreach ($item in 'src', 'tests', 'fixtures', '.github', '.actrc') {
            $srcPath = Join-Path $projectRoot $item
            if (Test-Path $srcPath) {
                Copy-Item $srcPath -Destination $tmp -Recurse -Force
            }
        }

        # Overwrite the changed-files fixture with this case's input.
        Set-Content -Path (Join-Path $tmp 'fixtures/changed-files.txt') -Value $case.ChangedFiles -Encoding utf8

        # act/checkout require a committed git repo.
        Push-Location $tmp
        try {
            git init -q .
            git config user.email 'harness@example.com'
            git config user.name  'Act Harness'
            git add -A
            git -c commit.gpgsign=false commit -q -m "case $caseNumber"

            # --- Run the workflow through act --------------------------------
            # --pull=false: the runner image (act-ubuntu-pwsh) is built locally and
            # must not be fetched from a registry.
            Write-Host "Running: act push --rm --pull=false" -ForegroundColor DarkGray
            $actOutput = & act push --rm --pull=false 2>&1 | Out-String
            $actExit   = $LASTEXITCODE
        }
        finally {
            Pop-Location
        }

        $clean = Strip-Ansi $actOutput

        # --- Persist output to the required artifact ------------------------
        $delim = ('=' * 78)
        Add-Content -Path $resultFile -Value $delim
        Add-Content -Path $resultFile -Value "TEST CASE $caseNumber : $($case.Name)"
        Add-Content -Path $resultFile -Value "Changed files:`n$($case.ChangedFiles)"
        Add-Content -Path $resultFile -Value "Expected LABELS: '$($case.ExpectedLabels)'  Expected LABEL_COUNT: $($case.ExpectedCount)"
        Add-Content -Path $resultFile -Value "act exit code: $actExit"
        Add-Content -Path $resultFile -Value $delim
        Add-Content -Path $resultFile -Value $clean
        Add-Content -Path $resultFile -Value "`n"

        # --- Assertions (fail-fast) -----------------------------------------
        if ($actExit -ne 0) {
            throw "Case '$($case.Name)': act exited with code $actExit (expected 0). See $resultFile."
        }

        # Every job that ran must report success and none may fail.
        $succeeded = ([regex]::Matches($clean, 'Job succeeded')).Count
        if ($succeeded -lt 2) {
            throw "Case '$($case.Name)': expected >= 2 'Job succeeded' (test + assign-labels), found $succeeded."
        }
        if ($clean -match 'Job failed') {
            throw "Case '$($case.Name)': output contains 'Job failed'."
        }

        # Parse the exact LABELS line emitted by the entrypoint.
        # Use [ \t]* (not \s*) so an empty value does not let the match bleed
        # onto the next log line.
        $labelMatch = [regex]::Match($clean, 'LABELS:[ \t]*(?<v>\S*)')
        if (-not $labelMatch.Success) {
            throw "Case '$($case.Name)': no 'LABELS:' line found in act output."
        }
        $actualLabels = $labelMatch.Groups['v'].Value
        if ($actualLabels -ne $case.ExpectedLabels) {
            throw "Case '$($case.Name)': LABELS mismatch. Expected '$($case.ExpectedLabels)', got '$actualLabels'."
        }

        # Parse the exact LABEL_COUNT line.
        $countMatch = [regex]::Match($clean, 'LABEL_COUNT:[ \t]*(?<v>\d+)')
        if (-not $countMatch.Success) {
            throw "Case '$($case.Name)': no 'LABEL_COUNT:' line found in act output."
        }
        $actualCount = [int]$countMatch.Groups['v'].Value
        if ($actualCount -ne $case.ExpectedCount) {
            throw "Case '$($case.Name)': LABEL_COUNT mismatch. Expected $($case.ExpectedCount), got $actualCount."
        }

        Write-Host "PASS: $($case.Name)  (LABELS='$actualLabels', COUNT=$actualCount)" -ForegroundColor Green
    }
    finally {
        # Clean up the temp repo regardless of outcome.
        if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Write-Host "`nAll $($cases.Count) act test cases passed. Output saved to $resultFile" -ForegroundColor Green
