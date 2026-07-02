<#
.SYNOPSIS
    Runs the test-results-aggregator workflow through `act` in an isolated
    temp git repo, asserts on exact expected output, and writes all act
    output to act-result.txt.
#>

$ErrorActionPreference = 'Stop'
$RepoRoot = $PSScriptRoot
$ResultFile = Join-Path $RepoRoot 'act-result.txt'
Remove-Item -LiteralPath $ResultFile -ErrorAction SilentlyContinue

function Invoke-ActCase {
    param(
        [Parameter(Mandatory)] [string] $CaseName
    )

    $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Path $tmpDir | Out-Null

    foreach ($item in @('.github', 'src', 'tests', 'fixtures', 'Invoke-Aggregation.ps1', '.actrc')) {
        Copy-Item -Path (Join-Path $RepoRoot $item) -Destination $tmpDir -Recurse
    }

    Push-Location $tmpDir
    try {
        git init -q
        git config user.email test@test.com
        git config user.name test
        git add -A
        git commit -q -m $CaseName

        $output = & act push --rm --pull=false 2>&1 | Out-String
        $exitCode = $LASTEXITCODE

        "===== CASE: $CaseName =====" | Add-Content -LiteralPath $ResultFile
        $output | Add-Content -LiteralPath $ResultFile
        "===== EXIT CODE: $exitCode =====" | Add-Content -LiteralPath $ResultFile
        ""  | Add-Content -LiteralPath $ResultFile

        return [PSCustomObject]@{
            CaseName = $CaseName
            Output   = $output
            ExitCode = $exitCode
        }
    }
    finally {
        Pop-Location
        Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$failures = @()

# Case 1: default fixtures — expect the known-good aggregation numbers and
# both jobs succeeding.
$case1 = Invoke-ActCase -CaseName 'default-fixtures'

if ($case1.ExitCode -ne 0) {
    $failures += "Case 'default-fixtures' expected exit code 0, got $($case1.ExitCode)"
}
if ($case1.Output -notmatch '\| 7 \| 2 \| 3 \|') {
    $failures += "Case 'default-fixtures' expected totals row '| 7 | 2 | 3 |' in output"
}
if ($case1.Output -notmatch 'TestMultiply') {
    $failures += "Case 'default-fixtures' expected flaky test 'TestMultiply' in output"
}
if ($case1.Output -notmatch 'TestSubtract') {
    $failures += "Case 'default-fixtures' expected flaky test 'TestSubtract' in output"
}
if ($case1.Output -notmatch 'Tests Passed: 9, ') {
    $failures += "Case 'default-fixtures' expected Pester summary 'Tests Passed: 9, ' in output"
}
$jobSucceededCount = ([regex]::Matches($case1.Output, 'Job succeeded')).Count
if ($jobSucceededCount -ne 2) {
    $failures += "Case 'default-fixtures' expected 2 'Job succeeded' occurrences (unit-tests + aggregate), got $jobSucceededCount"
}

if ($failures.Count -gt 0) {
    Write-Output "ACT HARNESS FAILURES:"
    $failures | ForEach-Object { Write-Output " - $_" }
    exit 1
}

Write-Output "All act harness assertions passed. Results written to $ResultFile"
