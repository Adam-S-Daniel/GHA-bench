<#
    run-act-tests.ps1

    Drives the pr-label-assigner GitHub Actions workflow through `act` for
    each fixture test case: sets up an isolated temp git repo containing the
    project + that case's changed-files fixture, runs `act push --rm`,
    verifies both CI jobs succeeded and the computed label set matches the
    known-good expectation, and appends the full act transcript for every
    case to act-result.txt.

    This is the ONLY supported way to validate label-assignment behavior for
    this project: the script is exercised exclusively through the real
    GitHub Actions pipeline (via act), never invoked directly as a
    substitute for CI.
#>

$ErrorActionPreference = 'Stop'

$RepoRoot = $PSScriptRoot
$ResultPath = Join-Path $RepoRoot 'act-result.txt'
$ActImage = 'act-ubuntu-pwsh:latest'

# Everything the workflow's jobs need on disk inside the temp repo.
$ItemsToCopy = @(
    'PrLabelAssigner.psm1',
    'Invoke-PrLabelAssigner.ps1',
    'rules.json',
    'tests',
    'fixtures',
    '.github'
)

$TestCases = @(
    [PSCustomObject]@{
        Name           = 'case1-docs-only'
        FixtureFile    = 'fixtures/case1-docs-only.txt'
        ExpectedLabels = 'documentation'
    }
    [PSCustomObject]@{
        Name           = 'case2-api-and-tests'
        FixtureFile    = 'fixtures/case2-api-and-tests.txt'
        ExpectedLabels = 'api,tests'
    }
    [PSCustomObject]@{
        Name           = 'case3-priority-conflict'
        FixtureFile    = 'fixtures/case3-priority-conflict.txt'
        ExpectedLabels = 'assets,generated'
    }
)

if (Test-Path -LiteralPath $ResultPath) {
    Remove-Item -LiteralPath $ResultPath -Force
}

$overallSuccess = $true
$caseSummaries = [System.Collections.Generic.List[string]]::new()

foreach ($case in $TestCases) {
    Write-Host "==== Running act test case: $($case.Name) ===="

    $tempRepo = Join-Path ([System.IO.Path]::GetTempPath()) "pr-label-assigner-$($case.Name)"
    if (Test-Path -LiteralPath $tempRepo) {
        Remove-Item -LiteralPath $tempRepo -Recurse -Force
    }
    New-Item -ItemType Directory -Path $tempRepo -Force | Out-Null

    foreach ($item in $ItemsToCopy) {
        $source = Join-Path $RepoRoot $item
        $dest = Join-Path $tempRepo $item
        Copy-Item -Path $source -Destination $dest -Recurse -Force
    }

    $fixtureSource = Join-Path $RepoRoot $case.FixtureFile
    Copy-Item -Path $fixtureSource -Destination (Join-Path $tempRepo 'changed-files.txt') -Force

    Push-Location $tempRepo
    try {
        git init --quiet --initial-branch=main . 2>&1 | Out-Null
        git config user.email 'act-harness@example.com'
        git config user.name 'Act Harness'
        git add -A
        git commit --quiet -m "test case: $($case.Name)"

        # --pull=false: act defaults to force-pulling the image (even if present
        # locally) to check for updates. Our custom image only exists locally
        # (built via Dockerfile.act) and isn't published to any registry, so a
        # forced pull fails with a Docker Hub auth error before any workflow
        # step runs. Skipping the pull uses the already-built local image.
        $actOutput = & act push --rm --pull=false -P "ubuntu-latest=$ActImage" 2>&1
        $actExitCode = $LASTEXITCODE
    } finally {
        Pop-Location
    }

    $outputLines = @($actOutput | ForEach-Object { $_.ToString() })

    $finalLabelsLine = $outputLines | Where-Object { $_ -match 'FINAL_LABELS=' } | Select-Object -Last 1
    $actualLabels = if ($finalLabelsLine) {
        ($finalLabelsLine -replace '^.*FINAL_LABELS=', '').Trim()
    } else {
        $null
    }

    $jobSucceededCount = @($outputLines | Where-Object { $_ -match 'Job succeeded' }).Count

    $exitCodeOk = ($actExitCode -eq 0)
    $labelsOk = ($actualLabels -eq $case.ExpectedLabels)
    $jobsOk = ($jobSucceededCount -ge 2)

    $caseSuccess = $exitCodeOk -and $labelsOk -and $jobsOk
    if (-not $caseSuccess) {
        $overallSuccess = $false
    }

    $delimiter = '=' * 80
    $header = @(
        $delimiter
        "TEST CASE: $($case.Name)"
        "Fixture:              $($case.FixtureFile)"
        "Expected labels:      $($case.ExpectedLabels)"
        "Actual labels:        $actualLabels"
        "act exit code:        $actExitCode (expected 0) => $(if ($exitCodeOk) { 'PASS' } else { 'FAIL' })"
        "Labels match:         $(if ($labelsOk) { 'PASS' } else { 'FAIL' })"
        "'Job succeeded' count: $jobSucceededCount (expected >= 2, one per job) => $(if ($jobsOk) { 'PASS' } else { 'FAIL' })"
        "CASE RESULT:          $(if ($caseSuccess) { 'PASS' } else { 'FAIL' })"
        $delimiter
        '--- act output ---'
    ) -join "`n"

    $footer = "--- end act output for $($case.Name) ---`n`n"

    Add-Content -Path $ResultPath -Value $header
    Add-Content -Path $ResultPath -Value ($outputLines -join "`n")
    Add-Content -Path $ResultPath -Value $footer

    $caseSummaries.Add("$($case.Name): $(if ($caseSuccess) { 'PASS' } else { 'FAIL' }) (labels='$actualLabels', exit=$actExitCode, jobSucceededCount=$jobSucceededCount)")

    Remove-Item -LiteralPath $tempRepo -Recurse -Force -ErrorAction SilentlyContinue
}

$summaryBlock = @(
    ('=' * 80)
    'SUMMARY'
    ($caseSummaries -join "`n")
    "OVERALL: $(if ($overallSuccess) { 'PASS' } else { 'FAIL' })"
    ('=' * 80)
) -join "`n"

Add-Content -Path $ResultPath -Value $summaryBlock
Write-Host $summaryBlock

if (-not $overallSuccess) {
    exit 1
}
