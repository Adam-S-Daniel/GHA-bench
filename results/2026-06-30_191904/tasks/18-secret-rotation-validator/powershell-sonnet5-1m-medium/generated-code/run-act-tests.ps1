<#
    .SYNOPSIS
    Runs the secret-rotation-validator GitHub Actions workflow through `act`
    for each of several fixture-data test cases, capturing all output to
    act-result.txt and asserting on exact expected values from each case's
    known-good result.

    Each test case: build a fresh temp git repo containing the project
    files plus that case's fixture data, run `act push --rm`, and assert
    the run succeeded (exit 0) and produced the exact expected numbers.
#>

$ErrorActionPreference = 'Stop'
$repoRoot = $PSScriptRoot
$resultPath = Join-Path $repoRoot 'act-result.txt'
Remove-Item -LiteralPath $resultPath -ErrorAction SilentlyContinue

# Files/dirs to copy into each temp repo (everything act needs to run the workflow).
$itemsToCopy = @('.github', 'src', 'tests', 'fixtures', 'Invoke-Validator.ps1', '.actrc')

function Copy-ProjectInto {
    param([string]$Destination)
    foreach ($item in $itemsToCopy) {
        Copy-Item -Path (Join-Path $repoRoot $item) -Destination (Join-Path $Destination $item) -Recurse -Force
    }
}

function Invoke-ActTestCase {
    param(
        [string]$CaseName,
        [string[]]$ActArgs,         # extra arguments appended to `act` (e.g. event name, --input)
        [string[]]$ExpectedStrings  # exact strings that MUST appear in the act output
    )

    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "act-test-$CaseName-$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $tempDir | Out-Null

    try {
        Copy-ProjectInto -Destination $tempDir

        Push-Location $tempDir
        try {
            git init -q
            git -c user.email="act@test.local" -c user.name="act-test" add -A
            git -c user.email="act@test.local" -c user.name="act-test" commit -q -m "test case $CaseName"

            $output = & act @ActArgs --rm --pull=false 2>&1 | Out-String
            $exitCode = $LASTEXITCODE
        }
        finally {
            Pop-Location
        }

        $delimiter = "===== TEST CASE: $CaseName ====="
        Add-Content -LiteralPath $resultPath -Value $delimiter
        Add-Content -LiteralPath $resultPath -Value $output
        Add-Content -LiteralPath $resultPath -Value "===== EXIT CODE: $exitCode ====="
        Add-Content -LiteralPath $resultPath -Value ''

        Write-Output "[$CaseName] act exit code: $exitCode"
        if ($exitCode -ne 0) {
            throw "[$CaseName] act exited with non-zero code $exitCode"
        }

        if ($output -notmatch 'Job succeeded') {
            throw "[$CaseName] expected at least one 'Job succeeded' line in act output"
        }

        $jobSucceededCount = ([regex]::Matches($output, 'Job succeeded')).Count
        if ($jobSucceededCount -lt 2) {
            throw "[$CaseName] expected both 'test' and 'validate' jobs to report success (found $jobSucceededCount 'Job succeeded' lines)"
        }

        foreach ($expected in $ExpectedStrings) {
            if ($output -notlike "*$expected*") {
                throw "[$CaseName] expected output to contain '$expected' but it did not"
            }
        }

        Write-Output "[$CaseName] PASSED - all expected values found"
        return $true
    }
    finally {
        Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$allPassed = $true

# Test case 1: `push` event, default warning-days (7, the workflow's default).
# At the workflow's pinned CurrentDate (2026-03-01) with WarningDays=7:
#   db-password            -> Expired (-29 days)
#   payment-gateway-token  -> Warning (2 days remaining, <= 7)
#   tls-cert, ssh-deploy-key -> Ok
$allPassed = (Invoke-ActTestCase -CaseName 'push-default-warning-days' -ActArgs @('push') -ExpectedStrings @(
    '| db-password | 2026-01-01 | 30 | -29 |',
    '| payment-gateway-token | 2026-02-01 | 30 | 2 |',
    '| tls-cert | 2026-01-01 | 90 | 31 |',
    '| ssh-deploy-key | 2026-02-15 | 60 | 46 |'
)) -and $allPassed

# Test case 2: `workflow_dispatch` event with warning-days=1. The same
# payment-gateway-token now has 2 days remaining, which no longer falls
# within a 1-day warning window, so it moves from Warning into Ok -- a
# different, verifiable combination of counts driven by the same fixture.
$allPassed = (Invoke-ActTestCase -CaseName 'workflow-dispatch-warning-days-1' -ActArgs @('workflow_dispatch', '--input', 'warning-days=1') -ExpectedStrings @(
    'Warning window: 1 days',
    '| db-password | 2026-01-01 | 30 | -29 |',
    '## Warning',
    '_None_',
    '| payment-gateway-token | 2026-02-01 | 30 | 2 |'
)) -and $allPassed

if (-not $allPassed) {
    Write-Error 'One or more act test cases failed. See act-result.txt for full output.'
    exit 1
}

Write-Output 'All act test cases passed.'
exit 0
