<#
.SYNOPSIS
    Drives the semantic-version-bumper GitHub Actions workflow through
    `act`, one temp git repo per test case, and asserts exact expected
    output values. Writes all raw act output to act-result.txt.

.DESCRIPTION
    Per the benchmark's workflow-validation requirements, every test case
    must exercise the workflow end-to-end via `act push --rm` rather than
    calling the PowerShell script directly. This script:
      1. Copies the project into a fresh temp dir for each case.
      2. Overwrites fixtures/commits.txt with that case's fixture.
      3. Initializes a throwaway git repo and commits everything.
      4. Runs `act push --rm`, capturing stdout/stderr.
      5. Appends the captured output to act-result.txt (delimited per case).
      6. Asserts exit code 0, "Job succeeded" for every job, and the exact
         expected previous/new version + bump type in the output.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$ResultFile = Join-Path $RepoRoot 'act-result.txt'
Remove-Item -Path $ResultFile -ErrorAction SilentlyContinue

$ProjectFiles = @(
    'VersionBumper.psm1',
    'Invoke-VersionBump.ps1',
    'VERSION',
    'CHANGELOG.md',
    'fixtures',
    'tests',
    '.github',
    '.actrc'
)

$TestCases = @(
    [PSCustomObject]@{
        Name             = 'feat-commits-minor-bump'
        Fixture          = 'commits-feat.txt'
        StartVersion     = '1.1.0'
        ExpectedNew      = '1.2.0'
        ExpectedBumpType = 'minor'
    },
    [PSCustomObject]@{
        Name             = 'fix-commits-patch-bump'
        Fixture          = 'commits-fix.txt'
        StartVersion     = '1.1.0'
        ExpectedNew      = '1.1.1'
        ExpectedBumpType = 'patch'
    },
    [PSCustomObject]@{
        Name             = 'breaking-commits-major-bump'
        Fixture          = 'commits-breaking.txt'
        StartVersion     = '1.1.0'
        ExpectedNew      = '2.0.0'
        ExpectedBumpType = 'major'
    }
)

$overallSuccess = $true

foreach ($case in $TestCases) {
    Write-Host "=== Running act test case: $($case.Name) ===" -ForegroundColor Cyan

    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("vb-act-" + [Guid]::NewGuid())
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    try {
        foreach ($item in $ProjectFiles) {
            Copy-Item -Path (Join-Path $RepoRoot $item) -Destination (Join-Path $tempDir $item) -Recurse -Force
        }

        Set-Content -Path (Join-Path $tempDir 'VERSION') -Value $case.StartVersion -NoNewline
        Copy-Item -Path (Join-Path $tempDir "fixtures/$($case.Fixture)") -Destination (Join-Path $tempDir 'fixtures/commits.txt') -Force

        Push-Location $tempDir
        try {
            git init -q .
            git config user.email 'act-test@example.com'
            git config user.name 'act-test'
            git add -A
            git commit -q -m "test case: $($case.Name)"

            $output = & act push --rm --pull=false 2>&1 | Out-String
            $exitCode = $LASTEXITCODE
        } finally {
            Pop-Location
        }

        $delimiter = "===== TEST CASE: $($case.Name) (expected new_version=$($case.ExpectedNew), bump_type=$($case.ExpectedBumpType)) ====="
        Add-Content -Path $ResultFile -Value $delimiter
        Add-Content -Path $ResultFile -Value $output
        Add-Content -Path $ResultFile -Value "===== END TEST CASE: $($case.Name) (exit code: $exitCode) ====="
        Add-Content -Path $ResultFile -Value ''

        $caseSuccess = $true

        if ($exitCode -ne 0) {
            Write-Host "FAIL [$($case.Name)]: act exited with code $exitCode" -ForegroundColor Red
            $caseSuccess = $false
        }

        $jobSuccessCount = ([regex]::Matches($output, 'Job succeeded')).Count
        if ($jobSuccessCount -lt 2) {
            Write-Host "FAIL [$($case.Name)]: expected 2 'Job succeeded' messages (test + bump-version), found $jobSuccessCount" -ForegroundColor Red
            $caseSuccess = $false
        }

        if ($output -notmatch "new_version=$([regex]::Escape($case.ExpectedNew))") {
            Write-Host "FAIL [$($case.Name)]: expected output to contain 'new_version=$($case.ExpectedNew)'" -ForegroundColor Red
            $caseSuccess = $false
        }

        if ($output -notmatch "bump_type=$([regex]::Escape($case.ExpectedBumpType))") {
            Write-Host "FAIL [$($case.Name)]: expected output to contain 'bump_type=$($case.ExpectedBumpType)'" -ForegroundColor Red
            $caseSuccess = $false
        }

        if ($output -notmatch "previous_version=$([regex]::Escape($case.StartVersion))") {
            Write-Host "FAIL [$($case.Name)]: expected output to contain 'previous_version=$($case.StartVersion)'" -ForegroundColor Red
            $caseSuccess = $false
        }

        if ($caseSuccess) {
            Write-Host "PASS [$($case.Name)]: exit=$exitCode new_version=$($case.ExpectedNew) bump_type=$($case.ExpectedBumpType)" -ForegroundColor Green
        } else {
            $overallSuccess = $false
        }
    } finally {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if (-not $overallSuccess) {
    throw 'One or more act test cases failed. See act-result.txt for full output.'
}

Write-Host 'All act test cases passed.' -ForegroundColor Green
