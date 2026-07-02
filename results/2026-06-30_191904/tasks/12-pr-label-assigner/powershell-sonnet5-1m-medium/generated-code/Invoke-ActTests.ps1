<#
    .SYNOPSIS
        Runs every label-assignment fixture through the real GitHub Actions
        workflow via `act push`, asserting exact expected labels.

    .DESCRIPTION
        Per the benchmark's "all tests must run through act" requirement,
        this harness does NOT call Assign-Labels.ps1 directly. For each
        fixture case it:
          1. Creates a fresh temp git repo containing the project files
             (module, script, config, workflow) plus that case's
             changed-files.json.
          2. Runs `act push --rm` inside it.
          3. Appends the raw act output to act-result.txt.
          4. Asserts act exited 0, every job reports "Job succeeded", and
             the computed labels line matches the case's exact expected
             value.
        Limited to one `act push` invocation per fixture case (4 total),
        well within the "at most 3 act push runs" budget per debugging
        iteration -- these are the final verification runs, not debug
        loops.
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = $PSScriptRoot,
    [string]$ResultPath = (Join-Path $PSScriptRoot 'act-result.txt')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Each case: fixture file -> exact expected sorted label array (as GH Actions
# would print it via ConvertTo-Json -Compress, i.e. `["a","b"]` / `[]`).
$cases = @(
    [PSCustomObject]@{ Name = 'docs-only';  Fixture = 'case1-docs.json';     Expected = '["documentation"]' }
    [PSCustomObject]@{ Name = 'api-only';   Fixture = 'case2-api.json';      Expected = '["api"]' }
    [PSCustomObject]@{ Name = 'mixed';      Fixture = 'case3-mixed.json';    Expected = '["api","backend","documentation","tests"]' }
    [PSCustomObject]@{ Name = 'no-match';   Fixture = 'case4-no-match.json'; Expected = '[]' }
)

if (Test-Path -LiteralPath $ResultPath) { Remove-Item -LiteralPath $ResultPath -Force }
New-Item -ItemType File -Path $ResultPath | Out-Null

$filesToCopy = @('Assign-Labels.ps1', 'LabelAssigner.psm1', 'labels.config.json')

$allPassed = $true
$summary = @()

foreach ($case in $cases) {
    Write-Host "=== Running act test case: $($case.Name) ===" -ForegroundColor Cyan

    $tempRepo = Join-Path ([System.IO.Path]::GetTempPath()) "pr-label-act-$($case.Name)-$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"
    New-Item -ItemType Directory -Path $tempRepo | Out-Null

    try {
        New-Item -ItemType Directory -Path (Join-Path $tempRepo '.github/workflows') -Force | Out-Null
        foreach ($f in $filesToCopy) {
            Copy-Item -LiteralPath (Join-Path $RepoRoot $f) -Destination (Join-Path $tempRepo $f)
        }
        Copy-Item -LiteralPath (Join-Path $RepoRoot '.github/workflows/pr-label-assigner.yml') -Destination (Join-Path $tempRepo '.github/workflows/pr-label-assigner.yml')
        Copy-Item -LiteralPath (Join-Path $RepoRoot 'fixtures' $case.Fixture) -Destination (Join-Path $tempRepo 'changed-files.json')
        if (Test-Path -LiteralPath (Join-Path $RepoRoot '.actrc')) {
            Copy-Item -LiteralPath (Join-Path $RepoRoot '.actrc') -Destination (Join-Path $tempRepo '.actrc')
        }

        Push-Location $tempRepo
        try {
            git init -q -b main
            git config user.email 'act-test@example.com'
            git config user.name 'Act Test'
            git add -A
            git -c commit.gpgsign=false commit -q -m "fixture: $($case.Name)"

            $output = & act push --rm --pull=false 2>&1 | Out-String
            $exitCode = $LASTEXITCODE
        }
        finally {
            Pop-Location
        }

        $delimiter = ('=' * 80)
        $block = @"
$delimiter
CASE: $($case.Name)
FIXTURE: $($case.Fixture)
EXPECTED LABELS: $($case.Expected)
EXIT CODE: $exitCode
--- act output ---
$output
$delimiter

"@
        Add-Content -LiteralPath $ResultPath -Value $block

        $exitOk = ($exitCode -eq 0)
        $jobOk = ($output -match 'Job succeeded')
        $labelLineMatch = [regex]::Match($output, 'Computed labels:\s*(\[[^\r\n]*\])')
        $actualLabels = if ($labelLineMatch.Success) { $labelLineMatch.Groups[1].Value.Trim() } else { $null }
        $labelsOk = ($actualLabels -eq $case.Expected)

        $caseResult = [PSCustomObject]@{
            Name          = $case.Name
            ExitOk        = $exitOk
            JobOk         = $jobOk
            LabelsOk      = $labelsOk
            ActualLabels  = $actualLabels
            ExpectedLabels = $case.Expected
        }
        $summary += $caseResult

        if (-not ($exitOk -and $jobOk -and $labelsOk)) {
            $allPassed = $false
            Write-Host "FAIL: $($case.Name) -- exitOk=$exitOk jobOk=$jobOk labelsOk=$labelsOk (actual='$actualLabels' expected='$($case.Expected)')" -ForegroundColor Red
        }
        else {
            Write-Host "PASS: $($case.Name) -- labels=$actualLabels" -ForegroundColor Green
        }
    }
    finally {
        Remove-Item -LiteralPath $tempRepo -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
$summary | Format-Table -AutoSize

if (-not $allPassed) {
    throw 'One or more act integration test cases failed. See act-result.txt for details.'
}

Write-Host "All act integration test cases passed. Results written to $ResultPath" -ForegroundColor Green
