<#
.SYNOPSIS
    End-to-end test harness: runs every test case THROUGH the GitHub
    Actions workflow via act (nektos/act).

.DESCRIPTION
    For each test case:
      1. Builds a temp git repo containing the project files plus that
         case's fixture data (changed-files.txt + label-rules.json).
      2. Runs `act push --rm` against the pr-label-assigner.yml workflow.
         Inside the workflow, the full Pester suite runs (test job) and the
         label assigner resolves the fixture "PR" (assign-labels job).
      3. Appends the full act output to act-result.txt (clearly delimited).
      4. Asserts: act exit code 0, the EXACT expected "FINAL LABELS:" value
         for that case's input, and that every job reports "Job succeeded".

    Exits non-zero with a summary if any assertion fails.

.NOTES
    This file lives at the repo root (not in tests/) on purpose: the
    workflow's test job runs `Invoke-Pester -Path ./tests` inside the act
    container, and this harness must never be executed there (it would
    recurse into docker-in-docker).
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot   = $PSScriptRoot
$resultFile = Join-Path $repoRoot 'act-result.txt'

# Each case = one simulated PR (changed files + ruleset) and the known-good
# label set the workflow must print for it.
$testCases = @(
    @{
        Name         = 'Case 1: basic mapping - docs/api/tests globs each hit once'
        ChangedFiles = @('docs/readme.md', 'src/api/users.ps1', 'src/core/parser.test.ps1')
        Rules        = @(
            @{ pattern = 'docs/**';    labels = @('documentation'); priority = 10 }
            @{ pattern = 'src/api/**'; labels = @('api');           priority = 10 }
            @{ pattern = '*.test.*';   labels = @('tests');         priority = 10 }
        )
        Expected     = 'FINAL LABELS: api,documentation,tests'
    }
    @{
        Name         = 'Case 2: priority conflict - docs/api/** (10) beats docs/** (20) per file'
        ChangedFiles = @('docs/api/spec.md', 'docs/intro.md')
        Rules        = @(
            @{ pattern = 'docs/**';     labels = @('documentation'); priority = 20 }
            @{ pattern = 'docs/api/**'; labels = @('api-docs');      priority = 10 }
        )
        Expected     = 'FINAL LABELS: api-docs,documentation'
    }
    @{
        Name         = 'Case 3: multiple labels per rule + unmatched file contributes nothing'
        ChangedFiles = @('src/api/handler.ps1', 'README.md')
        Rules        = @(
            @{ pattern = 'src/api/**'; labels = @('api', 'backend'); priority = 10 }
            @{ pattern = 'docs/**';    labels = @('documentation');  priority = 10 }
        )
        Expected     = 'FINAL LABELS: api,backend'
    }
)

# Fresh result artifact for this run.
Set-Content -Path $resultFile -Value "act e2e test results - $(Get-Date -Format o)`n"

$failures = @()

foreach ($case in $testCases) {
    Write-Host "`n=== $($case.Name) ===" -ForegroundColor Cyan

    # --- 1. temp git repo with project files + case fixtures ---------------
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('act-labeler-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $tmp | Out-Null

    try {
        foreach ($item in @('src', 'tests', 'fixtures', '.github', '.actrc')) {
            Copy-Item -Path (Join-Path $repoRoot $item) -Destination $tmp -Recurse
        }

        # Overwrite the fixtures with this case's simulated PR.
        $case.ChangedFiles | Set-Content -Path (Join-Path $tmp 'fixtures' 'changed-files.txt')
        ConvertTo-Json @($case.Rules) | Set-Content -Path (Join-Path $tmp 'fixtures' 'label-rules.json')

        git -C $tmp init -q -b main
        git -C $tmp -c user.email='harness@example.com' -c user.name='Act Harness' add -A
        git -C $tmp -c user.email='harness@example.com' -c user.name='Act Harness' commit -q -m 'test case fixture'

        # --- 2. run the workflow through act --------------------------------
        Push-Location $tmp
        try {
            # --pull=false: the runner image exists only locally; act's
            # default force-pull would fail against the public registry.
            $output = & act push --rm --pull=false `
                -W .github/workflows/pr-label-assigner.yml `
                -P ubuntu-latest=act-ubuntu-pwsh:latest 2>&1 | Out-String
            $exitCode = $LASTEXITCODE
        }
        finally {
            Pop-Location
        }

        # --- 3. append delimited output to act-result.txt -------------------
        Add-Content -Path $resultFile -Value @"
================================================================================
$($case.Name)
Expected: $($case.Expected)
Exit code: $exitCode
================================================================================
$output
"@

        # --- 4. assertions ---------------------------------------------------
        if ($exitCode -ne 0) {
            $failures += "$($case.Name): act exited with code $exitCode (expected 0)"
        }
        if ($output -notmatch [regex]::Escape($case.Expected)) {
            $failures += "$($case.Name): output did not contain exact expected line '$($case.Expected)'"
        }
        foreach ($job in @('Pester tests', 'Assign labels')) {
            if ($output -notmatch "(?m)/$([regex]::Escape($job))\].*Job succeeded") {
                $failures += "$($case.Name): job '$job' did not report 'Job succeeded'"
            }
        }

        Write-Host ("  exit={0}  expected-line-found={1}" -f $exitCode, ($output -match [regex]::Escape($case.Expected)))
    }
    finally {
        Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- summary ----------------------------------------------------------------
Add-Content -Path $resultFile -Value "`n=== HARNESS SUMMARY ==="
if ($failures.Count -gt 0) {
    $failures | ForEach-Object {
        Write-Host "FAIL: $_" -ForegroundColor Red
        Add-Content -Path $resultFile -Value "FAIL: $_"
    }
    Add-Content -Path $resultFile -Value "RESULT: FAILED ($($failures.Count) assertion(s))"
    exit 1
}

Add-Content -Path $resultFile -Value "RESULT: ALL $($testCases.Count) CASES PASSED"
Write-Host "`nALL $($testCases.Count) CASES PASSED" -ForegroundColor Green
exit 0
