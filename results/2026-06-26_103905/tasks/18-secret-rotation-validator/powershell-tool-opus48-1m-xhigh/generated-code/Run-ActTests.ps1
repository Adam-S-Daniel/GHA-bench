#requires -Version 7.0
<#
    .SYNOPSIS
        End-to-end test harness that exercises the Secret Rotation Validator
        ENTIRELY through the GitHub Actions workflow using `act` (nektos/act).

    .DESCRIPTION
        For each test case this harness:
          1. Builds an isolated temp git repo containing the project files plus that
             case's fixture data (copied over fixtures/secrets.json, the workflow's
             default config).
          2. Runs `act push --rm` against the workflow in that repo.
          3. Appends the full act output to act-result.txt (clearly delimited).
          4. Asserts act exited 0, that every job shows "Job succeeded", and that the
             captured output contains the EXACT expected SUMMARY / NOTIFY / report
             values for that case's input.

        On a fresh (non -Append) run it first runs the workflow-structure Pester
        suite (./meta-tests) and records the result too.

        The REFERENCE_DATE is pinned in the workflow (2026-06-28), so the expected
        values below are exact and deterministic.

    .PARAMETER Cases
        Which case(s) to run. Default: all three.

    .PARAMETER Append
        Append to an existing act-result.txt instead of starting fresh. Used to split
        the run across invocations while staying within the act-run budget.

    .PARAMETER ActImage
        The local runner image (built with pwsh + Pester). Passed via -P so act does
        not try to pull it (it has no registry source).
#>
[CmdletBinding()]
param(
    [ValidateSet('mixed', 'all-ok', 'all-expired')]
    [string[]]$Cases = @('mixed', 'all-ok', 'all-expired'),
    [switch]$Append,
    [string]$ActImage = 'act-ubuntu-pwsh:latest'
)

$ErrorActionPreference = 'Stop'
$Root       = $PSScriptRoot
$ResultFile = Join-Path $Root 'act-result.txt'

# ---------------------------------------------------------------------------
# Exact, deterministic expectations per case (validated independently first).
# ---------------------------------------------------------------------------
$Expectations = @{
    'mixed' = @{
        Fixture = 'fixtures/cases/mixed.json'
        Contains = @(
            'SUMMARY expired=1 warning=1 ok=1 total=3'
            'NOTIFY EXPIRED legacy-db-password overdue=88 requiredBy=billing-api,reports-worker'
            'NOTIFY WARNING payments-api-key days=2 requiredBy=payments-gateway'
            'NOTIFY OK session-cache-secret days=63 requiredBy=web-frontend'
            '<<<REPORT FORMAT=markdown>>>'
            '| legacy-db-password | 2026-01-01 | 90 | 2026-04-01 | 88 | billing-api, reports-worker |'
            '<<<REPORT FORMAT=json>>>'
            '"daysUntilExpiry": -88'
            'PESTER_RESULT passed=40 failed=0'
        )
    }
    'all-ok' = @{
        Fixture = 'fixtures/cases/all-ok.json'
        Contains = @(
            'SUMMARY expired=0 warning=0 ok=2 total=2'
            'NOTIFY OK fresh-signing-key days=357 requiredBy=auth-service'
            'NOTIFY OK monitoring-token days=87 requiredBy=observability'
            '## Expired (0)'
        )
    }
    'all-expired' = @{
        Fixture = 'fixtures/cases/all-expired.json'
        Contains = @(
            'SUMMARY expired=2 warning=0 ok=0 total=2'
            'NOTIFY EXPIRED ancient-root-cred overdue=58 requiredBy=legacy-system'
            'NOTIFY EXPIRED expired-tls-cert overdue=28 requiredBy=edge-proxy,load-balancer'
            '## OK (0)'
        )
    }
}

# Project files copied into each isolated test repo.
$ProjectItems = @(
    'src', 'tests', 'fixtures',
    'Invoke-SecretRotationValidator.ps1',
    '.github'
)

# ---------------------------------------------------------------------------
# Tiny assertion tracker.
# ---------------------------------------------------------------------------
$script:Failures = New-Object System.Collections.Generic.List[string]
$script:Passes   = 0

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if ($Condition) {
        $script:Passes++
        Write-Host "  [PASS] $Message" -ForegroundColor Green
    } else {
        $script:Failures.Add($Message)
        Write-Host "  [FAIL] $Message" -ForegroundColor Red
    }
}

function Remove-Ansi {
    param([string]$Text)
    return [regex]::Replace($Text, "`e\[[0-9;]*m", '')
}

function Write-Result {
    param([string]$Text)
    Add-Content -LiteralPath $ResultFile -Value $Text
}

# ---------------------------------------------------------------------------
# Build an isolated git repo for one case.
# ---------------------------------------------------------------------------
function New-CaseRepo {
    param([string]$Case)

    $temp = Join-Path ([System.IO.Path]::GetTempPath()) ("act-secret-rotation-" + $Case + "-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $temp -Force | Out-Null

    foreach ($item in $ProjectItems) {
        Copy-Item -Path (Join-Path $Root $item) -Destination $temp -Recurse -Force
    }

    # Overlay this case's fixture as the workflow's default config.
    Copy-Item -Path (Join-Path $Root $Expectations[$Case].Fixture) `
        -Destination (Join-Path $temp 'fixtures' 'secrets.json') -Force

    # act evaluates push branch filters ([main, master]); commit on master.
    git -C $temp init -b master --quiet
    git -C $temp -c user.email='harness@example.com' -c user.name='act-harness' add -A
    git -C $temp -c user.email='harness@example.com' -c user.name='act-harness' commit -m "test: $Case fixture" --quiet

    return $temp
}

# ---------------------------------------------------------------------------
# Run act for one case and assert on its output.
# ---------------------------------------------------------------------------
function Invoke-Case {
    param([string]$Case)

    Write-Host "`n=== CASE: $Case ===" -ForegroundColor Cyan
    $repo = New-CaseRepo -Case $Case

    $actArgs = @('push', '--rm', '--pull=false', '--action-offline-mode', '-P', "ubuntu-latest=$ActImage")

    Push-Location $repo
    try {
        $env:NO_COLOR = '1'
        $raw  = & act @actArgs 2>&1 | Out-String
        $exit = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }

    $clean = Remove-Ansi $raw

    # ---- Persist to the required artifact, clearly delimited. ----
    Write-Result ("=" * 100)
    Write-Result "TEST CASE: $Case"
    Write-Result "FIXTURE:   $($Expectations[$Case].Fixture) (copied to fixtures/secrets.json)"
    Write-Result "COMMAND:   act $($actArgs -join ' ')"
    Write-Result "EXIT CODE: $exit"
    Write-Result ("-" * 100)
    Write-Result $clean
    Write-Result ("=" * 100)
    Write-Result ''

    # ---- Assertions ----
    Assert-True ($exit -eq 0) "[$Case] act exited 0 (was $exit)"

    $jobSucceeded = ([regex]::Matches($clean, 'Job succeeded')).Count
    Assert-True ($jobSucceeded -ge 2) "[$Case] both jobs report 'Job succeeded' (found $jobSucceeded)"
    Assert-True (-not ($clean -match 'Job failed')) "[$Case] no job reports 'Job failed'"

    foreach ($needle in $Expectations[$Case].Contains) {
        Assert-True ($clean.Contains($needle)) "[$Case] output contains: $needle"
    }

    # Clean up the temp repo.
    Remove-Item -LiteralPath $repo -Recurse -Force -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------------
# Run the workflow-structure Pester suite (host-side) and record it.
# ---------------------------------------------------------------------------
function Invoke-StructureTests {
    Write-Host "`n=== Workflow structure tests (meta-tests) ===" -ForegroundColor Cyan
    $result = Invoke-Pester -Path (Join-Path $Root 'meta-tests') -PassThru -Output Detailed

    Write-Result ("=" * 100)
    Write-Result "WORKFLOW STRUCTURE TESTS (Invoke-Pester ./meta-tests)"
    Write-Result "Passed: $($result.PassedCount)  Failed: $($result.FailedCount)"
    Write-Result ("=" * 100)
    Write-Result ''

    Assert-True ($result.FailedCount -eq 0) "structure tests pass ($($result.PassedCount) passed, $($result.FailedCount) failed)"
}

# ===========================================================================
# Main
# ===========================================================================
if (-not $Append) {
    Set-Content -LiteralPath $ResultFile -Value @(
        "Secret Rotation Validator - act integration results"
        "Generated by Run-ActTests.ps1"
        "Runner image: $ActImage"
        ""
    )
    Invoke-StructureTests
}

foreach ($case in $Cases) {
    Invoke-Case -Case $case
}

# ---------------------------------------------------------------------------
# Final report.
# ---------------------------------------------------------------------------
Write-Host "`n================ HARNESS SUMMARY ================" -ForegroundColor Cyan
Write-Host "Passed assertions: $script:Passes"
Write-Host "Failed assertions: $($script:Failures.Count)"

if ($script:Failures.Count -gt 0) {
    Write-Host "`nFailures:" -ForegroundColor Red
    $script:Failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    Write-Result "RESULT: FAILED ($($script:Failures.Count) assertion(s) failed)"
    exit 1
}

Write-Host "`nAll assertions passed." -ForegroundColor Green
Write-Result "RESULT: PASSED (all $script:Passes assertion(s) passed)"
exit 0
