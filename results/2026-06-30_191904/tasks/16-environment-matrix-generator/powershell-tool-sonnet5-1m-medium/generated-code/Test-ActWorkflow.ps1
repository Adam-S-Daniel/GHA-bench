<#
    .SYNOPSIS
    Drives the environment-matrix-generator workflow end-to-end through
    `act`, once per fixture-driven test case. This is the "pipeline" test
    harness required by the task: rather than invoking the PowerShell script
    directly, each case sets up an isolated temp git repo with the project
    files plus that case's fixture as the active config.json, runs
    `act push --rm`, and asserts on the exact values act printed.

    Every fixture under ./fixtures is *also* exercised on every run (the
    generate-matrix job loops over all of them), so the oversized-matrix
    validation-error case is verified on every invocation without needing
    its own dedicated act run -- keeping the total act push count at 3,
    within the benchmark's stated limit.

    Output of every run is appended to act-result.txt in the current working
    directory, clearly delimited by test case name.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = $PSScriptRoot
$resultFile = Join-Path $repoRoot 'act-result.txt'
if (Test-Path $resultFile) { Remove-Item $resultFile -Force }

# Files that make up the project (everything act/the workflow needs).
$projectFiles = @(
    'MatrixGenerator.psm1',
    'Generate-Matrix.ps1',
    'MatrixGenerator.Tests.ps1',
    '.github',
    'fixtures',
    '.actrc'
)

# Each test case: which fixture becomes the active config.json, and the
# exact values we expect the pipeline to have produced for it.
$cases = @(
    [ordered]@{
        Name             = 'basic'
        Fixture          = 'fixtures/basic.json'
        ExpectedCount    = 4
        ExpectedMaxPar   = 4
        ExpectedFailFast = 'False'
    },
    [ordered]@{
        Name             = 'with-flags'
        Fixture          = 'fixtures/with-flags.json'
        ExpectedCount    = 12
        ExpectedMaxPar   = 6
        ExpectedFailFast = 'True'
    },
    [ordered]@{
        Name             = 'minimal'
        Fixture          = 'fixtures/minimal.json'
        ExpectedCount    = 1
        ExpectedMaxPar   = $null
        ExpectedFailFast = 'True'
    }
)

$allPassed = $true

foreach ($case in $cases) {
    Write-Output "Running act test case: $($case.Name)"

    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "matrix-gen-act-$($case.Name)-$([System.IO.Path]::GetRandomFileName())"
    New-Item -ItemType Directory -Path $tempDir | Out-Null

    try {
        foreach ($item in $projectFiles) {
            Copy-Item -Path (Join-Path $repoRoot $item) -Destination (Join-Path $tempDir $item) -Recurse
        }
        Copy-Item -Path (Join-Path $repoRoot $case.Fixture) -Destination (Join-Path $tempDir 'config.json')

        Push-Location $tempDir
        try {
            git init -q
            git config user.email 'act-harness@example.com'
            git config user.name 'act-harness'
            git add -A
            git commit -q -m "test: $($case.Name)"

            $output = & act push --rm --pull=false 2>&1 | Out-String
            $exitCode = $LASTEXITCODE
        }
        finally {
            Pop-Location
        }

        $delimiter = "=" * 80
        $section = @"
$delimiter
TEST CASE: $($case.Name)  (fixture: $($case.Fixture))
ACT EXIT CODE: $exitCode
$delimiter
$output

"@
        Add-Content -Path $resultFile -Value $section

        if ($exitCode -ne 0) {
            Write-Output "FAIL [$($case.Name)]: act exited with code $exitCode"
            $allPassed = $false
            continue
        }

        # Every job in the pipeline (test, generate-matrix, one per build cell) must succeed.
        $succeededJobs = ([regex]::Matches($output, 'Job succeeded')).Count
        if ($succeededJobs -lt ($case.ExpectedCount + 2)) {
            Write-Output "FAIL [$($case.Name)]: expected at least $($case.ExpectedCount + 2) succeeded jobs (test + generate-matrix + $($case.ExpectedCount) build cells), found $succeededJobs"
            $allPassed = $false
        }

        # act echoes the step's GITHUB_OUTPUT write as "::set-output:: matrix=<json>" --
        # pull the compact JSON straight from there and assert exact values.
        if ($output -notmatch '::set-output:: matrix=(\{.*\})\s*\r?\n') {
            Write-Output "FAIL [$($case.Name)]: could not find the 'matrix' step output in act output"
            $allPassed = $false
            continue
        }
        $activeJson = $Matches[1] | ConvertFrom-Json

        if ($activeJson.matrix.include.Count -ne $case.ExpectedCount) {
            Write-Output "FAIL [$($case.Name)]: expected $($case.ExpectedCount) matrix combinations, got $($activeJson.matrix.include.Count)"
            $allPassed = $false
        }

        $actualFailFast = [string]$activeJson.'fail-fast'
        if ($actualFailFast -ne $case.ExpectedFailFast) {
            Write-Output "FAIL [$($case.Name)]: expected fail-fast=$($case.ExpectedFailFast), got $actualFailFast"
            $allPassed = $false
        }

        $hasMaxParallel = $activeJson.PSObject.Properties.Name -contains 'max-parallel'
        if ($null -eq $case.ExpectedMaxPar) {
            if ($hasMaxParallel) {
                Write-Output "FAIL [$($case.Name)]: expected no max-parallel key, but found $($activeJson.'max-parallel')"
                $allPassed = $false
            }
        }
        elseif (-not $hasMaxParallel -or $activeJson.'max-parallel' -ne $case.ExpectedMaxPar) {
            Write-Output "FAIL [$($case.Name)]: expected max-parallel=$($case.ExpectedMaxPar), got $($activeJson.'max-parallel')"
            $allPassed = $false
        }

        # The oversized fixture is looped over on every run (generate-matrix
        # iterates ./fixtures/*.json) so its validation error must always appear.
        if ($output -notmatch 'VALIDATION ERROR:.*exceeds the maximum allowed size \(10\)') {
            Write-Output "FAIL [$($case.Name)]: expected the oversized-fixture validation error to be present"
            $allPassed = $false
        }

        Write-Output "PASS [$($case.Name)]: exit=0, cells=$($activeJson.matrix.include.Count), max-parallel=$($activeJson.'max-parallel'), fail-fast=$($activeJson.'fail-fast')"
    }
    finally {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if (-not $allPassed) {
    throw "One or more act workflow test cases failed. See $resultFile for full output."
}

Write-Output "All act workflow test cases passed. Full output saved to $resultFile."
