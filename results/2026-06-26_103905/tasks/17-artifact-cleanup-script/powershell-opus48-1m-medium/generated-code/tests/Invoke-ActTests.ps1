#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Integration test harness: runs the artifact-cleanup workflow end-to-end via
    `act` (nektos/act) for each test case and asserts on EXACT expected output.

.DESCRIPTION
    For every test case this harness:
      1. Builds a throwaway git repo containing the project + that case's fixture.
      2. Runs `act push --rm` with the case's policy passed via --env.
      3. Appends the full act output to act-result.txt (clearly delimited).
      4. Asserts act exited 0, both jobs report "Job succeeded", and every
         RESULT: line matches the known-good value for that input.

    All testing of the script goes THROUGH the pipeline - the script is never
    invoked directly here.

    NOTE: kept to 3 act runs (one per case) to respect the run budget.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$resultFile  = Join-Path $projectRoot 'act-result.txt'

# Start with a clean result artifact.
Set-Content -LiteralPath $resultFile -Value "ACT INTEGRATION TEST RESULTS`n" -Encoding utf8

# ---------------------------------------------------------------------------
# Test cases: each has a fixture (written as fixtures/sample.json in the temp
# repo), policy env vars, and the EXACT expected RESULT values.
# ---------------------------------------------------------------------------
$cases = @(
    @{
        Name    = 'full-policy-dry-run'
        Fixture = @'
[
  { "name": "ci-old",    "sizeBytes": 1000, "createdAt": "2026-04-01T00:00:00Z", "workflowName": "ci",      "workflowRunId": 101 },
  { "name": "ci-mid",    "sizeBytes": 500,  "createdAt": "2026-06-10T00:00:00Z", "workflowName": "ci",      "workflowRunId": 102 },
  { "name": "ci-new",    "sizeBytes": 500,  "createdAt": "2026-06-25T00:00:00Z", "workflowName": "ci",      "workflowRunId": 103 },
  { "name": "ci-newer",  "sizeBytes": 500,  "createdAt": "2026-06-26T00:00:00Z", "workflowName": "ci",      "workflowRunId": 104 },
  { "name": "release-1", "sizeBytes": 2000, "createdAt": "2026-06-20T00:00:00Z", "workflowName": "release", "workflowRunId": 201 }
]
'@
        Env     = @{ MAXAGE = '30'; KEEPLATEST = '2'; MAXSIZE = '2500'; DRYRUN = 'true' }
        Expect  = @{
            DRY_RUN        = 'True'
            DELETED_COUNT  = '3'
            RETAINED_COUNT = '2'
            SPACE_RECLAIMED= '3500'
            RETAINED_SIZE  = '1000'
            Deletes        = @('ci-mid', 'ci-old', 'release-1')
        }
    },
    @{
        Name    = 'max-age-only-execute'
        Fixture = @'
[
  { "name": "keep-me",   "sizeBytes": 100, "createdAt": "2026-06-26T00:00:00Z", "workflowName": "ci", "workflowRunId": 301 },
  { "name": "delete-me", "sizeBytes": 400, "createdAt": "2026-01-01T00:00:00Z", "workflowName": "ci", "workflowRunId": 302 }
]
'@
        Env     = @{ MAXAGE = '30'; KEEPLATEST = '0'; MAXSIZE = '0'; DRYRUN = 'false' }
        Expect  = @{
            DRY_RUN        = 'False'
            DELETED_COUNT  = '1'
            RETAINED_COUNT = '1'
            SPACE_RECLAIMED= '400'
            RETAINED_SIZE  = '100'
            Deletes        = @('delete-me')
        }
    },
    @{
        Name    = 'nothing-to-delete'
        Fixture = @'
[
  { "name": "a", "sizeBytes": 100, "createdAt": "2026-06-25T00:00:00Z", "workflowName": "ci", "workflowRunId": 401 },
  { "name": "b", "sizeBytes": 200, "createdAt": "2026-06-26T00:00:00Z", "workflowName": "ci", "workflowRunId": 402 }
]
'@
        Env     = @{ MAXAGE = '0'; KEEPLATEST = '5'; MAXSIZE = '0'; DRYRUN = 'true' }
        Expect  = @{
            DRY_RUN        = 'True'
            DELETED_COUNT  = '0'
            RETAINED_COUNT = '2'
            SPACE_RECLAIMED= '0'
            RETAINED_SIZE  = '300'
            Deletes        = @()
        }
    }
)

# Parse "RESULT:KEY=VALUE" lines out of act output.
function Get-ResultMap {
    param([string] $Output)
    $map = @{}
    $deletes = New-Object System.Collections.Generic.List[string]
    foreach ($line in ($Output -split "`r?`n")) {
        if ($line -match 'RESULT:DELETE=(.+?)\s*$') {
            $deletes.Add($Matches[1].Trim())
        }
        elseif ($line -match 'RESULT:([A-Z_]+)=(.+?)\s*$') {
            $map[$Matches[1]] = $Matches[2].Trim()
        }
    }
    $map['Deletes'] = $deletes
    return $map
}

$failures = New-Object System.Collections.Generic.List[string]

foreach ($case in $cases) {
    $name = $case.Name
    Write-Host "`n=== Running act case: $name ===" -ForegroundColor Cyan

    # --- build throwaway repo --------------------------------------------------
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("actcase_" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null

    try {
        foreach ($item in 'src', 'tests', 'fixtures', '.github', 'Invoke-Cleanup.ps1', '.actrc') {
            Copy-Item -Path (Join-Path $projectRoot $item) -Destination $tmp -Recurse -Force
        }

        # Override the fixture this case operates on.
        Set-Content -LiteralPath (Join-Path $tmp 'fixtures' 'sample.json') -Value $case.Fixture -Encoding utf8

        # act needs a git repo.
        Push-Location $tmp
        git init -q | Out-Null
        git config user.email 'test@example.com'
        git config user.name  'act-harness'
        git add -A
        git commit -q -m 'act test case' | Out-Null

        # --- assemble act args ---------------------------------------------------
        # --pull=false: use the locally-built image instead of force-pulling it
        # from a registry (which requires auth and would fail offline).
        $actArgs = @('push', '--rm', '--pull=false', '-P', 'ubuntu-latest=act-ubuntu-pwsh:latest')
        foreach ($k in $case.Env.Keys) {
            $actArgs += @('--env', "$k=$($case.Env[$k])")
        }

        Write-Host "act $($actArgs -join ' ')"
        $output = (& act @actArgs 2>&1 | Out-String)
        $exit = $LASTEXITCODE
        Pop-Location

        # --- persist output ------------------------------------------------------
        Add-Content -LiteralPath $resultFile -Value "`n========================================"
        Add-Content -LiteralPath $resultFile -Value "TEST CASE: $name"
        Add-Content -LiteralPath $resultFile -Value "ENV: $(( $case.Env.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ' ')"
        Add-Content -LiteralPath $resultFile -Value "ACT EXIT CODE: $exit"
        Add-Content -LiteralPath $resultFile -Value "----------------------------------------"
        Add-Content -LiteralPath $resultFile -Value $output

        # --- assertions ----------------------------------------------------------
        if ($exit -ne 0) {
            $failures.Add("[$name] act exited $exit (expected 0)")
            continue
        }

        # Both jobs must report success.
        $succeeded = ([regex]::Matches($output, 'Job succeeded')).Count
        if ($succeeded -lt 2) {
            $failures.Add("[$name] expected >=2 'Job succeeded' (unit-tests + cleanup-plan), saw $succeeded")
        }

        $map = Get-ResultMap -Output $output
        foreach ($key in 'DRY_RUN', 'DELETED_COUNT', 'RETAINED_COUNT', 'SPACE_RECLAIMED', 'RETAINED_SIZE') {
            $expected = [string] $case.Expect[$key]
            $actual   = if ($map.ContainsKey($key)) { [string] $map[$key] } else { '<missing>' }
            if ($actual -ne $expected) {
                $failures.Add("[$name] $key expected '$expected' but got '$actual'")
            }
            else {
                Write-Host "  OK  $key=$actual" -ForegroundColor Green
            }
        }

        # Exact set of deleted artifact names.
        $expectedDeletes = @($case.Expect.Deletes | Sort-Object)
        $actualDeletes   = @($map['Deletes'] | Sort-Object)
        $expJoin = ($expectedDeletes -join ',')
        $actJoin = ($actualDeletes -join ',')
        if ($expJoin -ne $actJoin) {
            $failures.Add("[$name] deletes expected '[$expJoin]' but got '[$actJoin]'")
        }
        else {
            Write-Host "  OK  Deletes=[$actJoin]" -ForegroundColor Green
        }
    }
    finally {
        if ((Get-Location).Path -eq $tmp) { Pop-Location -ErrorAction SilentlyContinue }
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
Write-Host "`n=== ACT INTEGRATION SUMMARY ===" -ForegroundColor Cyan
if ($failures.Count -gt 0) {
    foreach ($f in $failures) { Write-Host "FAIL: $f" -ForegroundColor Red }
    Add-Content -LiteralPath $resultFile -Value "`nOVERALL: FAILED ($($failures.Count) assertion failures)"
    throw "Act integration tests FAILED with $($failures.Count) assertion failure(s). See act-result.txt."
}
else {
    Write-Host "All act integration assertions passed." -ForegroundColor Green
    Add-Content -LiteralPath $resultFile -Value "`nOVERALL: PASSED (all $($cases.Count) cases)"
}
