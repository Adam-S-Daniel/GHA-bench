#requires -Version 7.0
<#
    .SYNOPSIS
    Runs the dependency-license-checker workflow through `act` for every test
    case fixture, capturing all output to act-result.txt and asserting exact
    expected values (per the "tests must run through the pipeline" rule).

    For each test case:
      1. Copy the project into a fresh temp git repo.
      2. Overwrite fixtures/manifest.json with that case's fixture data.
      3. Commit, then run `act push --rm`.
      4. Append the captured output to act-result.txt under a delimiter.
      5. Assert: exit code 0, both jobs report success, and the report
         contains the exact expected license/status values for that case.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = $PSScriptRoot
$resultFile = Join-Path $repoRoot 'act-result.txt'
Remove-Item -Path $resultFile -ErrorAction SilentlyContinue

# Files/dirs to copy into each temp repo (everything needed to run the workflow).
$itemsToCopy = @(
    '.github',
    '.actrc',
    'fixtures',
    'tests',
    'LicenseChecker.psm1',
    'Invoke-LicenseCheck.ps1'
)

$testCases = @(
    [PSCustomObject]@{
        Name           = 'case1-all-approved'
        FixtureFile    = 'fixtures/act-cases/case1-all-approved.json'
        ExpectedRows   = @(
            @{ Name = 'lodash'; License = 'MIT'; Status = 'Approved' }
            @{ Name = 'express'; License = 'MIT'; Status = 'Approved' }
        )
        ExpectedSummary = 'Summary: 2 approved, 0 denied, 0 unknown (total 2)'
    },
    [PSCustomObject]@{
        Name           = 'case2-has-denied'
        FixtureFile    = 'fixtures/act-cases/case2-has-denied.json'
        ExpectedRows   = @(
            @{ Name = 'lodash'; License = 'MIT'; Status = 'Approved' }
            @{ Name = 'gpl-lib'; License = 'GPL-3.0'; Status = 'Denied' }
        )
        ExpectedSummary = 'Summary: 1 approved, 1 denied, 0 unknown (total 2)'
    },
    [PSCustomObject]@{
        Name           = 'case3-has-unknown'
        FixtureFile    = 'fixtures/act-cases/case3-has-unknown.json'
        ExpectedRows   = @(
            @{ Name = 'left-pad'; License = 'WTFPL'; Status = 'Unknown' }
            @{ Name = 'totally-unlisted-package'; License = 'Unknown'; Status = 'Unknown' }
        )
        ExpectedSummary = 'Summary: 0 approved, 0 denied, 2 unknown (total 2)'
    }
)

$allPassed = $true

foreach ($case in $testCases) {
    Write-Host "=== Running act test case: $($case.Name) ==="

    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "license-checker-act-$($case.Name)-$([guid]::NewGuid().ToString('N').Substring(0,8))"
    New-Item -ItemType Directory -Path $tempDir | Out-Null

    try {
        foreach ($item in $itemsToCopy) {
            $source = Join-Path $repoRoot $item
            $dest = Join-Path $tempDir $item
            Copy-Item -Path $source -Destination $dest -Recurse -Force
        }

        # Overwrite the manifest with this case's fixture data.
        Copy-Item -Path (Join-Path $repoRoot $case.FixtureFile) -Destination (Join-Path $tempDir 'fixtures/manifest.json') -Force

        Push-Location $tempDir
        try {
            git init --quiet | Out-Null
            git config user.email 'act-test@example.com' | Out-Null
            git config user.name 'act-test' | Out-Null
            git add -A | Out-Null
            git commit --quiet -m "test case: $($case.Name)" | Out-Null

            # --pull=false: the act runner image is already present locally;
            # forcing a pull hits a registry auth wall in this environment.
            $output = & act push --rm --pull=false 2>&1 | Out-String
            $exitCode = $LASTEXITCODE
        }
        finally {
            Pop-Location
        }

        # Persist raw output for inspection, clearly delimited per case.
        Add-Content -Path $resultFile -Value "===== TEST CASE: $($case.Name) ====="
        Add-Content -Path $resultFile -Value "Exit code: $exitCode"
        Add-Content -Path $resultFile -Value $output
        Add-Content -Path $resultFile -Value "===== END TEST CASE: $($case.Name) ====="
        Add-Content -Path $resultFile -Value ''

        $casePassed = $true

        if ($exitCode -ne 0) {
            Write-Host "FAIL [$($case.Name)]: act exited with code $exitCode (expected 0)" -ForegroundColor Red
            $casePassed = $false
        }

        # act prints one "Job succeeded" line per job on success.
        $successCount = ([regex]::Matches($output, 'Job succeeded')).Count
        if ($successCount -lt 2) {
            Write-Host "FAIL [$($case.Name)]: expected 2 'Job succeeded' lines (one per job), found $successCount" -ForegroundColor Red
            $casePassed = $false
        }

        foreach ($row in $case.ExpectedRows) {
            $pattern = "$([regex]::Escape($row.Name)).*$([regex]::Escape($row.License)).*$([regex]::Escape($row.Status))"
            if ($output -notmatch $pattern) {
                Write-Host "FAIL [$($case.Name)]: expected report row matching '$pattern' not found in output" -ForegroundColor Red
                $casePassed = $false
            }
        }

        if ($output -notmatch [regex]::Escape($case.ExpectedSummary)) {
            Write-Host "FAIL [$($case.Name)]: expected summary line '$($case.ExpectedSummary)' not found in output" -ForegroundColor Red
            $casePassed = $false
        }

        if ($casePassed) {
            Write-Host "PASS [$($case.Name)]" -ForegroundColor Green
        }
        else {
            $allPassed = $false
        }
    }
    finally {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if (-not $allPassed) {
    throw 'One or more act test cases failed. See act-result.txt for full output.'
}

Write-Host 'All act test cases passed.' -ForegroundColor Green
