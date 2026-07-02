<#
.SYNOPSIS
    End-to-end test harness: runs every test case through the GitHub Actions
    workflow via act (nektos/act) and asserts on exact expected output.

.DESCRIPTION
    For each test case:
      1. Builds a temp git repo containing the project files plus that case's
         fixture written to fixtures/ci-case.json (the path the workflow reads).
      2. Runs `act push --rm` in the temp repo and captures all output.
      3. Appends the delimited output (and the assertion results) to
         act-result.txt in this directory.
      4. Asserts: act exit code 0, every job reports "Job succeeded", and the
         output contains the exact known-good report lines for that fixture.
         ANSI color codes are stripped before comparison (Pester embeds them
         mid-line in its summary).

    -Replay re-runs the assertions against the raw act output already saved
    in act-result.txt without invoking act again (act runs are expensive).

    Exits 0 only if every assertion in every case passes.
#>
[CmdletBinding()]
param(
    [switch] $Replay
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$resultFile = Join-Path $root 'act-result.txt'
$delimiter = ('=' * 80)

# Both jobs run the same deterministic AS_OF_DATE (2026-01-15) baked into the
# workflow env, so every expected value below is exact, not approximate.
# Inside the container actionlint is absent, so its structure test skips:
# 35 passed + 1 skipped is the exact expected Pester summary for every case.
$pesterSummary = 'Tests Passed: 35, Failed: 0, Skipped: 1'

$cases = @(
    [pscustomobject]@{
        Name    = 'mixed-urgency'
        Fixture = Get-Content (Join-Path $root 'fixtures' 'secrets.json') -Raw
        Expected = @(
            # Pester job: full suite green inside the container.
            $pesterSummary
            # Markdown report: exact totals and exact rows, most urgent first.
            '**Totals:** 4 secrets — 2 expired, 1 warning, 1 ok'
            '## EXPIRED (2) — rotate immediately'
            '| signing-key | 2025-12-28 | -18 | 2025-07-01 | 180 | auth-service |'
            '| db-password | 2025-12-30 | -16 | 2025-10-01 | 90 | billing-api, reporting-service |'
            '## WARNING (1) — rotate soon'
            '| api-key | 2026-01-18 | 3 | 2025-10-20 | 90 | web-frontend, mobile-app |'
            '## OK (1)'
            '| tls-cert | 2027-01-01 | 351 | 2026-01-01 | 365 | ingress |'
            # JSON report: exact summary counts and most-urgent secret.
            '"total": 4'
            '"expired": 2'
            '"warning": 1'
            '"name": "signing-key"'
            '"daysUntilExpiry": -18'
        )
    }
    [pscustomobject]@{
        Name    = 'all-ok'
        Fixture = @'
{
  "warningWindowDays": 14,
  "secrets": [
    { "name": "alpha-token", "lastRotated": "2026-01-10", "rotationPolicyDays": 90,  "requiredBy": ["svc-a"] },
    { "name": "beta-token",  "lastRotated": "2026-01-05", "rotationPolicyDays": 180, "requiredBy": [] },
    { "name": "gamma-cert",  "lastRotated": "2025-12-01", "rotationPolicyDays": 365, "requiredBy": ["svc-b", "svc-c"] }
  ]
}
'@
        Expected = @(
            $pesterSummary
            '**Totals:** 3 secrets — 0 expired, 0 warning, 3 ok'
            '## EXPIRED (0) — rotate immediately'
            '_No secrets in this group._'
            '## OK (3)'
            '| alpha-token | 2026-04-10 | 85 | 2026-01-10 | 90 | svc-a |'
            '| beta-token | 2026-07-04 | 170 | 2026-01-05 | 180 | - |'
            '| gamma-cert | 2026-12-01 | 320 | 2025-12-01 | 365 | svc-b, svc-c |'
            '"total": 3'
            '"expired": 0'
            '"ok": 3'
            '"name": "alpha-token"'
        )
    }
)

function Remove-AnsiCodes {
    # Pester colors its output; the escape sequences land mid-line in the
    # captured text and would defeat exact substring comparison.
    param([string] $Text)
    $Text -replace "`e\[[0-9;]*m", ''
}

function Test-CaseOutput {
    # Applies every assertion for one case; returns a list of failure strings.
    param([pscustomobject] $Case, [string] $RawOutput, [int] $ActExit)

    $failures = [System.Collections.Generic.List[string]]::new()
    $clean = Remove-AnsiCodes -Text $RawOutput

    if ($ActExit -ne 0) {
        $failures.Add("act exited with code $ActExit (expected 0)")
    }
    foreach ($job in 'Pester tests', 'Rotation report') {
        if ($clean -notmatch "\[Secret Rotation Validator/$job\].*Job succeeded") {
            $failures.Add("job '$job' did not report 'Job succeeded'")
        }
    }
    foreach ($expected in $Case.Expected) {
        if (-not $clean.Contains($expected)) {
            $failures.Add("missing exact expected output: $expected")
        }
    }
    , $failures
}

function Invoke-ActCase {
    # Builds the temp git repo for a case and runs the workflow through act.
    # Returns the raw output lines and the act exit code.
    param([pscustomobject] $Case)

    $projectItems = @('.github', '.actrc', 'src', 'tests', 'fixtures', 'Invoke-SecretRotationValidator.ps1')
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "srv-act-$($Case.Name)-$PID"
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    New-Item -ItemType Directory -Path $tmp | Out-Null

    try {
        foreach ($item in $projectItems) {
            Copy-Item -Path (Join-Path $root $item) -Destination $tmp -Recurse
        }
        # Install this case's fixture where the workflow's CONFIG_PATH points.
        Set-Content -Path (Join-Path $tmp 'fixtures' 'ci-case.json') -Value $Case.Fixture

        Push-Location $tmp
        try {
            git init -q -b main 2>&1 | Out-Null
            git add -A 2>&1 | Out-Null
            git -c user.email='ci@example.com' -c user.name='ci' commit -q -m "case $($Case.Name)" 2>&1 | Out-Null

            $output = & act push --rm --pull=false 2>&1 | ForEach-Object { [string]$_ }
            [pscustomobject]@{ Output = $output; ExitCode = $LASTEXITCODE }
        }
        finally {
            Pop-Location
        }
    }
    finally {
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Read-SavedCaseOutputs {
    # Parses act-result.txt back into per-case raw output + exit code so
    # assertions can be replayed without re-running act.
    param([string] $Path)

    if (-not (Test-Path $Path)) {
        throw "Cannot replay: '$Path' not found. Run the harness without -Replay first."
    }
    $saved = @{}
    $currentName = $null
    $buffer = [System.Collections.Generic.List[string]]::new()
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^TEST CASE: (\S+)$') {
            $currentName = $Matches[1]
            $buffer.Clear()
        }
        elseif ($null -ne $currentName -and $line -match '^--- act exit code: (\d+) ---$') {
            $saved[$currentName] = [pscustomobject]@{
                Output   = @($buffer | Where-Object { $_ -ne $delimiter })
                ExitCode = [int]$Matches[1]
            }
            $currentName = $null
        }
        elseif ($null -ne $currentName) {
            $buffer.Add($line)
        }
    }
    $saved
}

# --- Main ---

$savedOutputs = if ($Replay) { Read-SavedCaseOutputs -Path $resultFile } else { $null }

$newContent = [System.Collections.Generic.List[string]]::new()
$newContent.Add("act end-to-end test results - secret-rotation-validator`n")
$totalFailures = 0

foreach ($case in $cases) {
    Write-Host "`n===== CASE: $($case.Name) =====" -ForegroundColor Cyan

    if ($Replay) {
        if (-not $savedOutputs.ContainsKey($case.Name)) {
            throw "Cannot replay: no saved act output for case '$($case.Name)'."
        }
        Write-Host 'Replaying saved act output...'
        $run = $savedOutputs[$case.Name]
    }
    else {
        Write-Host 'Running act push (this takes a while)...'
        $run = Invoke-ActCase -Case $case
    }

    # --- Record raw output, clearly delimited per case ---
    $newContent.Add($delimiter)
    $newContent.Add("TEST CASE: $($case.Name)")
    $newContent.Add($delimiter)
    foreach ($line in $run.Output) { $newContent.Add($line) }
    $newContent.Add("--- act exit code: $($run.ExitCode) ---")
    $newContent.Add('')

    # --- Assertions ---
    $failures = Test-CaseOutput -Case $case -RawOutput ($run.Output -join "`n") -ActExit $run.ExitCode

    $newContent.Add("ASSERTIONS for case '$($case.Name)':")
    if ($failures.Count -eq 0) {
        $msg = "PASS: exit code 0, all jobs succeeded, all $($case.Expected.Count) exact-output assertions matched"
        $newContent.Add("  $msg")
        Write-Host $msg -ForegroundColor Green
    }
    else {
        foreach ($f in $failures) {
            $newContent.Add("  FAIL: $f")
            Write-Host "FAIL: $f" -ForegroundColor Red
        }
        $totalFailures += $failures.Count
    }
    $newContent.Add('')
}

$newContent.Add($delimiter)
$verdict = if ($totalFailures -eq 0) { 'RESULT: ALL CASES PASSED' } else { "RESULT: $totalFailures ASSERTION FAILURE(S)" }
$newContent.Add($verdict)
Set-Content -Path $resultFile -Value $newContent
Write-Host "`n$verdict"
exit ([int]($totalFailures -ne 0))
