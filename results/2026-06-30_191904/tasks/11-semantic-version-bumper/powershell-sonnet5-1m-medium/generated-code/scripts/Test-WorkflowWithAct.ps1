<#
    .SYNOPSIS
    Drives the semantic-version-bumper GitHub Actions workflow through `act`
    for each test-case fixture, asserting exact expected output. Writes all
    act output to act-result.txt in the current working directory.

    .DESCRIPTION
    For each test case this script:
      1. Creates a fresh temp git repo containing the project files.
      2. Overwrites version.json / commits.txt with that case's fixture data.
      3. Commits and runs `act push --rm`.
      4. Appends the captured output to act-result.txt (clearly delimited).
      5. Asserts act exited 0, every job reported "Job succeeded", and the
         output contains the exact expected new version string.
#>
param(
    [string]$ResultPath = (Join-Path (Get-Location) 'act-result.txt')
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')

$testCases = @(
    [pscustomobject]@{
        Name            = 'feat-commit-bumps-minor'
        CommitsFixture  = 'commits-feat.txt'
        ExpectedVersion = '1.2.0'
    },
    [pscustomobject]@{
        Name            = 'fix-commit-bumps-patch'
        CommitsFixture  = 'commits-fix.txt'
        ExpectedVersion = '1.1.1'
    },
    [pscustomobject]@{
        Name            = 'breaking-commit-bumps-major'
        CommitsFixture  = 'commits-breaking.txt'
        ExpectedVersion = '2.0.0'
    }
)

if (Test-Path -LiteralPath $ResultPath) {
    Remove-Item -LiteralPath $ResultPath -Force
}

$failures = @()

foreach ($case in $testCases) {
    Write-Host "=== Running act test case: $($case.Name) ==="

    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "svb-act-$([Guid]::NewGuid())"
    New-Item -ItemType Directory -Path $tempDir | Out-Null

    try {
        # Copy the whole project (scripts, tests, workflow) into the temp repo.
        Copy-Item -Path (Join-Path $repoRoot 'scripts') -Destination (Join-Path $tempDir 'scripts') -Recurse
        Copy-Item -Path (Join-Path $repoRoot 'tests') -Destination (Join-Path $tempDir 'tests') -Recurse
        Copy-Item -Path (Join-Path $repoRoot '.github') -Destination (Join-Path $tempDir '.github') -Recurse
        Copy-Item -Path (Join-Path $repoRoot 'version.json') -Destination (Join-Path $tempDir 'version.json')
        Copy-Item -Path (Join-Path $repoRoot 'commits.txt') -Destination (Join-Path $tempDir 'commits.txt')
        Copy-Item -Path (Join-Path $repoRoot '.actrc') -Destination (Join-Path $tempDir '.actrc')

        # Swap in this test case's fixture as the commit log the workflow reads.
        $fixturePath = Join-Path $tempDir 'tests' 'fixtures' $case.CommitsFixture
        Copy-Item -Path $fixturePath -Destination (Join-Path $tempDir 'commits.txt') -Force

        Push-Location $tempDir
        try {
            git init --quiet 2>&1 | Out-Null
            git -c user.email='test@example.com' -c user.name='act-test' add -A 2>&1 | Out-Null
            git -c user.email='test@example.com' -c user.name='act-test' commit --quiet -m 'test commit' 2>&1 | Out-Null

            $actArgs = @('push', '--rm', '--pull=false')
            $output = & act @actArgs 2>&1 | Out-String
            $exitCode = $LASTEXITCODE
        }
        finally {
            Pop-Location
        }

        $delimiter = "`n===== TEST CASE: $($case.Name) (expected version: $($case.ExpectedVersion)) =====`n"
        Add-Content -LiteralPath $ResultPath -Value $delimiter
        Add-Content -LiteralPath $ResultPath -Value $output
        Add-Content -LiteralPath $ResultPath -Value "`n----- act exit code: $exitCode -----`n"

        if ($exitCode -ne 0) {
            $failures += "$($case.Name): act exited with code $exitCode (expected 0)"
            continue
        }

        $jobSuccessCount = ([regex]::Matches($output, 'Job succeeded')).Count
        if ($jobSuccessCount -lt 2) {
            $failures += "$($case.Name): expected 2 'Job succeeded' messages (test + bump-version), found $jobSuccessCount"
        }

        $expectedLine = "New version: $($case.ExpectedVersion)"
        if ($output -notmatch [regex]::Escape($expectedLine)) {
            $failures += "$($case.Name): expected output to contain '$expectedLine' but it did not"
        }
    }
    finally {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($failures.Count -gt 0) {
    Write-Host "FAILURES:"
    $failures | ForEach-Object { Write-Host " - $_" }
    throw "$($failures.Count) act test case(s) failed. See $ResultPath for full output."
}

Write-Host "All $($testCases.Count) act test cases passed. Full output written to $ResultPath"
