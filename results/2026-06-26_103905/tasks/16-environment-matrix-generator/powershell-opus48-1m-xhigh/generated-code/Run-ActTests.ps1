#!/usr/bin/env pwsh
#
# Run-ActTests.ps1 — end-to-end test harness.
#
# For every test case it:
#   1. builds a throwaway git repo containing the project files + that case's
#      fixture data (copied to matrix-config.json),
#   2. runs `act push --rm` against the workflow,
#   3. appends the full, clearly-delimited output to act-result.txt,
#   4. asserts act exited 0, every job reports "Job succeeded", no job failed,
#      and the generated matrix matches the EXACT known-good values for the case.
#
# Usage:
#   ./Run-ActTests.ps1                 # run all cases
#   ./Run-ActTests.ps1 -Cases case1-exclude   # run a single case (targeted re-run)
#
[CmdletBinding()]
param(
    [string[]] $Cases,
    [switch]   $KeepTemp
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProjectDir = $PSScriptRoot
$ActResult  = Join-Path $ProjectDir 'act-result.txt'
$WorkflowRel = '.github/workflows/environment-matrix-generator.yml'

# Files the workflow actually needs inside the isolated repo.
$ProjectFiles = @(
    'MatrixGenerator.psm1',
    'Generate-Matrix.ps1',
    'MatrixGenerator.Tests.ps1',
    '.actrc'
)

# ---------------------------------------------------------------------------
# Known-good expectations per case (computed from the script's deterministic
# output — see fixtures/*.json).
# ---------------------------------------------------------------------------
$AllCases = @(
    [pscustomobject]@{
        Name       = 'case1-exclude'
        Fixture    = 'fixtures/case1-exclude.json'
        Size       = '3'
        MaxParallel= '2'
        FailFast   = 'false'
        MatrixJson = '{"include":[{"os":"ubuntu-latest","node":"18"},{"os":"ubuntu-latest","node":"20"},{"os":"windows-latest","node":"20"}]}'
        JobSucceeded = 5   # generate(1) + build(3 combos) + summary(1)
    },
    [pscustomobject]@{
        Name       = 'case2-include'
        Fixture    = 'fixtures/case2-include.json'
        Size       = '3'
        MaxParallel= ''
        FailFast   = 'true'
        MatrixJson = '{"include":[{"os":"ubuntu-latest","node":"18"},{"os":"ubuntu-latest","node":"20","experimental":true},{"os":"macos-latest","node":"21"}]}'
        JobSucceeded = 5   # generate(1) + build(3 combos) + summary(1)
    },
    [pscustomobject]@{
        Name       = 'case3-fullproduct'
        Fixture    = 'fixtures/case3-fullproduct.json'
        Size       = '8'
        MaxParallel= '4'
        FailFast   = 'false'
        MatrixJson = '{"include":[{"os":"ubuntu-latest","python":"3.11","experimental":false},{"os":"ubuntu-latest","python":"3.11","experimental":true},{"os":"ubuntu-latest","python":"3.12","experimental":false},{"os":"ubuntu-latest","python":"3.12","experimental":true},{"os":"windows-latest","python":"3.11","experimental":false},{"os":"windows-latest","python":"3.11","experimental":true},{"os":"windows-latest","python":"3.12","experimental":false},{"os":"windows-latest","python":"3.12","experimental":true}]}'
        JobSucceeded = 10  # generate(1) + build(8 combos) + summary(1)
    }
)

if ($Cases) {
    $AllCases = $AllCases | Where-Object { $Cases -contains $_.Name }
    if (-not $AllCases) { throw "No matching cases for: $($Cases -join ', ')" }
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Remove-Ansi([string]$Text) {
    return ($Text -replace "`e\[[0-9;]*[A-Za-z]", '')
}

# Return the trimmed value after the first "<Key>=" occurrence, or $null.
function Get-LineValue([string]$Text, [string]$Key) {
    foreach ($line in ($Text -split "`n")) {
        $marker = "$Key="
        $idx = $line.IndexOf($marker)
        if ($idx -ge 0) {
            return $line.Substring($idx + $marker.Length).Trim()
        }
    }
    return $null
}

# True if some line mentions the job tag AND "Job succeeded".
function Test-JobSucceeded([string]$Text, [string]$JobTag) {
    foreach ($line in ($Text -split "`n")) {
        if ($line -match [regex]::Escape($JobTag) -and $line -match 'Job succeeded') { return $true }
    }
    return $false
}

# ---------------------------------------------------------------------------
# Per-case execution + assertions
# ---------------------------------------------------------------------------
function Invoke-Case($Case) {
    $failures = [System.Collections.Generic.List[string]]::new()
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("act-matrix-{0}-{1}" -f $Case.Name, [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null

    try {
        # 1. assemble the isolated repo --------------------------------------
        foreach ($f in $ProjectFiles) {
            Copy-Item -LiteralPath (Join-Path $ProjectDir $f) -Destination (Join-Path $tmp $f) -Force
        }
        New-Item -ItemType Directory -Path (Join-Path $tmp '.github/workflows') -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $ProjectDir $WorkflowRel) -Destination (Join-Path $tmp $WorkflowRel) -Force
        # the case fixture becomes the default config the workflow reads
        Copy-Item -LiteralPath (Join-Path $ProjectDir $Case.Fixture) -Destination (Join-Path $tmp 'matrix-config.json') -Force

        # 2. make it a git repo with one commit (checkout@v4 needs a HEAD) ----
        Push-Location $tmp
        try {
            & git init -b main *> $null
            & git config user.email 'harness@example.com' *> $null
            & git config user.name  'Act Harness' *> $null
            & git add -A *> $null
            & git commit -m 'matrix test fixture' *> $null

            # 3. run the workflow through act ---------------------------------
            Write-Host "[$($Case.Name)] running act push ..." -ForegroundColor Cyan
            $rawOut = & act push --rm --pull=false -W $WorkflowRel 2>&1 | Out-String
            $actExit = $LASTEXITCODE
        }
        finally {
            Pop-Location
        }

        # 4. persist the output ----------------------------------------------
        $delimiter = ('=' * 78)
        $section = @(
            $delimiter,
            "CASE: $($Case.Name)   (fixture: $($Case.Fixture))",
            "act exit code: $actExit",
            $delimiter,
            $rawOut,
            ''
        ) -join "`n"
        Add-Content -LiteralPath $ActResult -Value $section

        # 5. assertions -------------------------------------------------------
        $clean = Remove-Ansi $rawOut

        if ($actExit -ne 0) { $failures.Add("act exited with code $actExit (expected 0)") }

        $failedCount = ([regex]::Matches($clean, 'Job failed')).Count
        if ($failedCount -ne 0) { $failures.Add("found $failedCount 'Job failed' marker(s)") }

        $succeededCount = ([regex]::Matches($clean, 'Job succeeded')).Count
        if ($succeededCount -ne $Case.JobSucceeded) {
            $failures.Add("expected $($Case.JobSucceeded) 'Job succeeded' markers, found $succeededCount")
        }

        # act tags each job line with the job's display name, so match on those.
        foreach ($tag in @('Validate and generate matrix', 'Build ', 'Matrix summary')) {
            if (-not (Test-JobSucceeded $clean $tag)) {
                $failures.Add("no 'Job succeeded' for job '$tag'")
            }
        }

        $size = Get-LineValue $clean 'MATRIX_SIZE'
        if ($size -ne $Case.Size) { $failures.Add("MATRIX_SIZE expected '$($Case.Size)', got '$size'") }

        $mp = Get-LineValue $clean 'MAX_PARALLEL'
        if ($mp -ne $Case.MaxParallel) { $failures.Add("MAX_PARALLEL expected '$($Case.MaxParallel)', got '$mp'") }

        $ff = Get-LineValue $clean 'FAIL_FAST'
        if ($ff -ne $Case.FailFast) { $failures.Add("FAIL_FAST expected '$($Case.FailFast)', got '$ff'") }

        $mj = Get-LineValue $clean 'MATRIX_JSON'
        if ($mj -ne $Case.MatrixJson) {
            $failures.Add("MATRIX_JSON mismatch.`n   expected: $($Case.MatrixJson)`n   got:      $mj")
        }
    }
    finally {
        if (-not $KeepTemp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }

    # Leading comma keeps the List intact: returning it bare would let PowerShell
    # enumerate it (and an empty list would collapse to $null).
    return ,$failures
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
"act test run started" | Set-Content -LiteralPath $ActResult

$results = [ordered]@{}
foreach ($case in $AllCases) {
    $fails = Invoke-Case $case
    $results[$case.Name] = $fails
}

Write-Host ''
Write-Host '################ ACT TEST SUMMARY ################'
$anyFailed = $false
foreach ($name in $results.Keys) {
    $fails = @($results[$name])
    if ($fails.Count -eq 0) {
        Write-Host ("  PASS  {0}" -f $name) -ForegroundColor Green
    }
    else {
        $anyFailed = $true
        Write-Host ("  FAIL  {0}" -f $name) -ForegroundColor Red
        foreach ($f in $fails) { Write-Host ("          - {0}" -f $f) -ForegroundColor Red }
    }
}
Write-Host '##################################################'
Write-Host "Full act output saved to: $ActResult"

if ($anyFailed) { exit 1 } else { Write-Host 'All act test cases passed.' -ForegroundColor Green; exit 0 }
