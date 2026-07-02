<#
    .SYNOPSIS
    Acceptance test harness. For each fixture scenario, sets up an isolated
    temp git repo containing the project (with that scenario's
    package.json swapped in), runs the GitHub Actions workflow via
    `act push --rm`, and asserts on exact expected values from the output.

    .DESCRIPTION
    This is the *acceptance* test runner required by the task spec: every
    test case must execute through the actual GitHub Actions workflow via
    act, not by calling the script directly. All act output is appended
    to act-result.txt, clearly delimited per case.
#>

$ErrorActionPreference = 'Stop'
$RepoRoot = $PSScriptRoot
$ResultFile = Join-Path $RepoRoot 'act-result.txt'

# Files/dirs that make up the deliverable and must be present in every
# temp repo the harness spins up.
$ProjectItems = @(
    '.actrc',
    '.github',
    'Invoke-LicenseCheck.ps1',
    'LicenseChecker.psm1',
    'fixtures',
    'license-database.json',
    'license-policy.json',
    'package.json',
    'tests'
)

$TestCases = @(
    [PSCustomObject]@{
        Name            = 'all-approved'
        FixtureManifest = 'fixtures/package-allowed.json'
        ExpectedSummary = 'Summary: Approved=3, Denied=0, Unknown=0'
    },
    [PSCustomObject]@{
        Name            = 'with-denied-license'
        FixtureManifest = 'fixtures/package-denied.json'
        ExpectedSummary = 'Summary: Approved=1, Denied=1, Unknown=0'
    },
    [PSCustomObject]@{
        Name            = 'with-unknown-license'
        FixtureManifest = 'fixtures/package-unknown.json'
        ExpectedSummary = 'Summary: Approved=0, Denied=0, Unknown=1'
    }
)

if (Test-Path -LiteralPath $ResultFile) {
    Remove-Item -LiteralPath $ResultFile
}

$allPassed = $true

foreach ($case in $TestCases) {
    Write-Output "==== Running act test case: $($case.Name) ===="

    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "license-checker-act-$($case.Name)-$([guid]::NewGuid())"
    New-Item -ItemType Directory -Path $tempDir | Out-Null

    try {
        foreach ($item in $ProjectItems) {
            Copy-Item -Path (Join-Path $RepoRoot $item) -Destination (Join-Path $tempDir $item) -Recurse
        }

        # Swap in this case's fixture as the repo's package.json so the
        # compliance-report job checks a different dependency set each run.
        Copy-Item -Path (Join-Path $RepoRoot $case.FixtureManifest) -Destination (Join-Path $tempDir 'package.json') -Force

        Push-Location $tempDir
        try {
            git init -q -b main . 2>&1 | Out-Null
            git config user.email 'act-harness@example.com'
            git config user.name 'Act Test Harness'
            git add -A
            git commit -q -m "test case: $($case.Name)"

            # --pull=false: act-ubuntu-pwsh:latest is a locally-built image, not
            # a registry image; act's default force-pull would otherwise try
            # (and fail) to pull it from Docker Hub.
            $output = & act push --rm --pull=false 2>&1 | Out-String
            $exitCode = $LASTEXITCODE
        }
        finally {
            Pop-Location
        }

        $delimiter = '=' * 80
        $header = @"
$delimiter
TEST CASE: $($case.Name)
Fixture: $($case.FixtureManifest)
Expected summary line: $($case.ExpectedSummary)
act exit code: $exitCode
$delimiter
"@
        Add-Content -LiteralPath $ResultFile -Value $header
        Add-Content -LiteralPath $ResultFile -Value $output

        $caseFailures = [System.Collections.Generic.List[string]]::new()

        if ($exitCode -ne 0) {
            $caseFailures.Add("act exited with code $exitCode, expected 0")
        }

        $jobSucceededCount = ([regex]::Matches($output, 'Job succeeded')).Count
        if ($jobSucceededCount -lt 2) {
            $caseFailures.Add("expected 2 'Job succeeded' markers (one per job: test, compliance-report), found $jobSucceededCount")
        }

        if ($output -notmatch [regex]::Escape($case.ExpectedSummary)) {
            $caseFailures.Add("expected output to contain exact string '$($case.ExpectedSummary)', but it did not")
        }

        if ($caseFailures.Count -gt 0) {
            $allPassed = $false
            Write-Output "FAIL: $($case.Name)"
            $caseFailures | ForEach-Object { Write-Output "  - $_" }
        }
        else {
            Write-Output "PASS: $($case.Name)"
        }
    }
    finally {
        Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if (-not $allPassed) {
    Write-Error "One or more act acceptance test cases failed. See $ResultFile for details."
    exit 1
}

Write-Output "All act acceptance test cases passed. Results recorded in $ResultFile."
exit 0
