#Requires -Version 7.0
<#
.SYNOPSIS
    End-to-end act harness for the PR Label Assigner workflow.

.DESCRIPTION
    For each test case this harness:
      1. Builds an isolated temp git repo containing the project files plus the
         case's fixture data (its own changed-files.json).
      2. Runs `act push --rm` against the workflow inside that repo.
      3. Appends the full act output to act-result.txt (clearly delimited).
      4. Asserts act exited 0, that every job reported "Job succeeded", and that
         the workflow emitted the EXACT expected "Labels: ..." line for the input.

    Limited to one act run per test case (3 total) to respect act's cost.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProjectDir = $PSScriptRoot
$ResultFile = Join-Path $ProjectDir 'act-result.txt'

# Start each run with a fresh result file.
if (Test-Path $ResultFile) { Remove-Item $ResultFile -Force }

# ---------------------------------------------------------------------------
# Test cases: distinct fixture inputs with their known-good expected labels.
# Expected values were derived from fixtures/config.json and verified directly.
# ---------------------------------------------------------------------------
$TestCases = @(
    [pscustomobject]@{
        Name           = 'mixed-paths'
        ChangedFiles   = @('docs/guide.md', 'src/api/users.ts', 'src/api/users.test.ts', 'README.md')
        ExpectedLabels = 'tests, api, backend, documentation'
    }
    [pscustomobject]@{
        Name           = 'docs-only'
        ChangedFiles   = @('docs/intro.md', 'docs/advanced/topics.md')
        ExpectedLabels = 'documentation'
    }
    [pscustomobject]@{
        Name           = 'exclusive-priority'
        ChangedFiles   = @('generated/api.ts', 'src/app.ts', 'package.json')
        ExpectedLabels = 'skip-review, dependencies, backend'
    }
)

# Files copied into each isolated test repo.
$ProjectFiles = @(
    'PrLabelAssigner.ps1',
    'PrLabelAssigner.Tests.ps1',
    'Workflow.Tests.ps1',
    '.actrc'
)

$failures = @()

foreach ($tc in $TestCases) {
    Write-Host "=== Test case: $($tc.Name) ===" -ForegroundColor Cyan

    # 1. Build an isolated temp git repo with the project + this case's fixture.
    $repo = Join-Path ([System.IO.Path]::GetTempPath()) ("pr-label-" + [System.IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Path $repo -Force | Out-Null
    try {
        foreach ($f in $ProjectFiles) {
            Copy-Item -Path (Join-Path $ProjectDir $f) -Destination (Join-Path $repo $f) -Force
        }
        Copy-Item -Path (Join-Path $ProjectDir '.github') -Destination $repo -Recurse -Force
        Copy-Item -Path (Join-Path $ProjectDir 'fixtures') -Destination $repo -Recurse -Force

        # Overwrite the changed-files fixture with this case's data.
        $tc.ChangedFiles | ConvertTo-Json |
            Set-Content -Path (Join-Path $repo 'fixtures/changed-files.json') -Encoding utf8

        # act requires a git repository.
        Push-Location $repo
        try {
            git init -q 2>&1 | Out-Null
            git config user.email 'harness@example.com' 2>&1 | Out-Null
            git config user.name  'act-harness'         2>&1 | Out-Null
            git add -A 2>&1 | Out-Null
            git commit -q -m "fixture: $($tc.Name)" 2>&1 | Out-Null

            # 2. Run act for the push event. --pull=false: image is already local.
            $actOutput = & act push --rm --pull=false 2>&1 | Out-String
            $actExit = $LASTEXITCODE
        } finally {
            Pop-Location
        }

        # 3. Persist the output, clearly delimited.
        $delim = ('=' * 70)
        Add-Content -Path $ResultFile -Value $delim
        Add-Content -Path $ResultFile -Value "TEST CASE: $($tc.Name)"
        Add-Content -Path $ResultFile -Value "INPUT CHANGED FILES: $($tc.ChangedFiles -join ', ')"
        Add-Content -Path $ResultFile -Value "EXPECTED LABELS: $($tc.ExpectedLabels)"
        Add-Content -Path $ResultFile -Value "ACT EXIT CODE: $actExit"
        Add-Content -Path $ResultFile -Value $delim
        Add-Content -Path $ResultFile -Value $actOutput

        # 4. Assertions.
        $caseErrors = @()

        if ($actExit -ne 0) {
            $caseErrors += "act exited with code $actExit (expected 0)."
        }

        # Every job must report success. The workflow has two jobs (test, label).
        $succeeded = ([regex]::Matches($actOutput, 'Job succeeded')).Count
        if ($succeeded -lt 2) {
            $caseErrors += "Expected >= 2 'Job succeeded' messages, found $succeeded."
        }

        # Exact expected label line must be present in the output.
        $expectedLine = "Labels: $($tc.ExpectedLabels)"
        if ($actOutput -notmatch [regex]::Escape($expectedLine)) {
            $caseErrors += "Did not find exact expected output line: '$expectedLine'."
        }

        if ($caseErrors.Count -gt 0) {
            Write-Host "  FAILED:" -ForegroundColor Red
            $caseErrors | ForEach-Object { Write-Host "    - $_" -ForegroundColor Red }
            $failures += "$($tc.Name): " + ($caseErrors -join ' ')
        } else {
            Write-Host "  PASSED (labels: $($tc.ExpectedLabels); jobs succeeded: $succeeded)" -ForegroundColor Green
        }
    } finally {
        Remove-Item $repo -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ""
Write-Host "act output saved to: $ResultFile"

if ($failures.Count -gt 0) {
    Write-Host "OVERALL: FAILED" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}

Write-Host "OVERALL: ALL $($TestCases.Count) ACT TEST CASES PASSED" -ForegroundColor Green
exit 0
