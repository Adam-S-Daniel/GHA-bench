# Tests for the GitHub Actions workflow that wraps the aggregator.
#
# Three layers, mirroring the task's "Workflow Structure Tests" and
# "All Tests Must Run Through Act" requirements:
#   1. Structure  — parse the YAML and assert triggers / jobs / steps / script refs.
#   2. actionlint — run the linter and assert it passes (exit 0).
#   3. act        — run the workflow in Docker for two distinct fixture cases,
#                   append all output to act-result.txt, and assert on the EXACT
#                   aggregate values the known-good fixtures must produce.
#
# The act layer is tagged 'Act' so the fast static layers can be run on their own
# (Invoke-Pester ... -ExcludeTagFilter Act) without paying Docker startup costs.

# --- Discovery-time values (needed for -Skip evaluation) ---
$RepoRoot      = Split-Path -Parent $PSScriptRoot
$WorkflowPath  = Join-Path $RepoRoot '.github/workflows/test-results-aggregator.yml'
# act + docker must both be present for the act layer to run for real.
$HasActStack   = [bool](Get-Command act -ErrorAction SilentlyContinue) -and
                 [bool](Get-Command docker -ErrorAction SilentlyContinue)

# Helper: stand up a throwaway git repo containing exactly the project files a
# real checkout would have, drop the given case's fixtures into fixtures/, then
# run the workflow with `act`. Returns the exit code and captured output, and
# appends the output to act-result.txt (clearly delimited per case).
#
# Defined in the global scope so it survives Pester's discovery -> run phase
# transition and is callable from the act Describe's BeforeAll.
function Global:Invoke-WorkflowActCase {
    param(
        [Parameter(Mandatory)][string]$CaseName,
        [Parameter(Mandatory)][string]$FixtureSource,  # dir whose files become fixtures/
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$ActResultPath
    )

    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("tra-act-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    $pushed = $false
    try {
        Push-Location $tmp; $pushed = $true

        # Minimal git repo (act reads committed state).
        git init -q 2>&1 | Out-Null
        git config user.email 'ci@example.com' 2>&1 | Out-Null
        git config user.name  'CI'             2>&1 | Out-Null

        # Copy project files into the temp repo root.
        Copy-Item (Join-Path $RepoRoot 'TestResultsAggregator.psm1') $tmp
        Copy-Item (Join-Path $RepoRoot 'Invoke-Aggregator.ps1')      $tmp
        if (Test-Path (Join-Path $RepoRoot '.actrc')) {
            Copy-Item (Join-Path $RepoRoot '.actrc') $tmp
        }
        New-Item -ItemType Directory -Path (Join-Path $tmp '.github/workflows') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $tmp 'tests')             -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $tmp 'fixtures')          -Force | Out-Null
        Copy-Item (Join-Path $RepoRoot '.github/workflows/test-results-aggregator.yml') (Join-Path $tmp '.github/workflows')
        Copy-Item (Join-Path $RepoRoot 'tests/TestResultsAggregator.Tests.ps1')         (Join-Path $tmp 'tests')

        # This case's fixture data becomes the (default) fixtures/ directory.
        Copy-Item (Join-Path $FixtureSource '*') (Join-Path $tmp 'fixtures')

        git add -A 2>&1 | Out-Null
        git commit -qm "act case: $CaseName" 2>&1 | Out-Null

        # Run the workflow. --pull=false because the act image is a local build.
        $output = & act push --rm --pull=false 2>&1 | Out-String
        $exit = $LASTEXITCODE

        Pop-Location; $pushed = $false

        # Append, clearly delimited, to the required act-result.txt artifact.
        $header = @(
            ''
            '================================================================'
            "ACT CASE: $CaseName"
            "FIXTURE SOURCE: $FixtureSource"
            "TIMESTAMP: $(Get-Date -Format 'o')"
            '================================================================'
        ) -join [Environment]::NewLine
        Add-Content -Path $ActResultPath -Value $header
        Add-Content -Path $ActResultPath -Value $output
        Add-Content -Path $ActResultPath -Value "ACT EXIT CODE: $exit"

        return [PSCustomObject]@{ CaseName = $CaseName; ExitCode = $exit; Output = $output }
    }
    finally {
        if ($pushed) { Pop-Location }
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

BeforeAll {
    $script:RepoRoot      = Split-Path -Parent $PSScriptRoot
    $script:WorkflowPath  = Join-Path $script:RepoRoot '.github/workflows/test-results-aggregator.yml'
    $script:ActResultPath = Join-Path $script:RepoRoot 'act-result.txt'
    Import-Module powershell-yaml -ErrorAction Stop
    $script:Workflow = ConvertFrom-Yaml (Get-Content -LiteralPath $script:WorkflowPath -Raw)
}

Describe 'Workflow file structure' {

    It 'exists at the expected path' {
        Test-Path -LiteralPath $script:WorkflowPath | Should -BeTrue
    }

    It 'has a name' {
        $script:Workflow.name | Should -Be 'Test Results Aggregator'
    }

    It 'declares the expected trigger events' {
        # powershell-yaml preserves the literal "on" key.
        $triggers = $script:Workflow['on']
        $triggers.Keys | Should -Contain 'push'
        $triggers.Keys | Should -Contain 'pull_request'
        $triggers.Keys | Should -Contain 'workflow_dispatch'
        $triggers.Keys | Should -Contain 'schedule'
    }

    It 'requests read-only contents permission' {
        $script:Workflow.permissions.contents | Should -Be 'read'
    }

    It 'defines the aggregate job running on ubuntu-latest' {
        $script:Workflow.jobs.Keys | Should -Contain 'aggregate'
        $script:Workflow.jobs.aggregate['runs-on'] | Should -Be 'ubuntu-latest'
    }

    It 'checks out the repository with actions/checkout@v4' {
        $uses = $script:Workflow.jobs.aggregate.steps | ForEach-Object { $_.uses } | Where-Object { $_ }
        $uses | Should -Contain 'actions/checkout@v4'
    }

    It 'references the aggregator CLI and unit tests, and those files exist' {
        $runs = ($script:Workflow.jobs.aggregate.steps | ForEach-Object { $_.run }) -join "`n"
        $runs | Should -Match 'Invoke-Aggregator\.ps1'
        $runs | Should -Match 'tests/TestResultsAggregator\.Tests\.ps1'

        Test-Path -LiteralPath (Join-Path $script:RepoRoot 'Invoke-Aggregator.ps1')              | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:RepoRoot 'TestResultsAggregator.psm1')         | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:RepoRoot 'tests/TestResultsAggregator.Tests.ps1') | Should -BeTrue
    }

    It 'uses shell: pwsh for the steps that invoke the script' {
        $pwshSteps = $script:Workflow.jobs.aggregate.steps | Where-Object { $_.run -match 'Invoke-Aggregator' }
        $pwshSteps | Should -Not -BeNullOrEmpty
        foreach ($s in $pwshSteps) { $s.shell | Should -Be 'pwsh' }
    }
}

Describe 'actionlint validation' {

    It 'is installed' {
        Get-Command actionlint -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'passes with exit code 0' {
        $out = & actionlint $script:WorkflowPath 2>&1
        $code = $LASTEXITCODE
        if ($code -ne 0) { Write-Host ($out | Out-String) }
        $code | Should -Be 0
    }
}

Describe 'Workflow execution via act' -Tag 'Act' -Skip:(-not $HasActStack) {

    BeforeAll {
        # Start the artifact fresh each run, then append one block per case.
        Set-Content -Path $script:ActResultPath -Value "act-result.txt — generated $(Get-Date -Format 'o')" -Encoding utf8

        # Case 1: the committed comprehensive matrix (2x JUnit XML + 1x JSON,
        # with Math::div flaky and Str::split consistently failing).
        $script:Comprehensive = Invoke-WorkflowActCase `
            -CaseName 'comprehensive-matrix' `
            -FixtureSource (Join-Path $script:RepoRoot 'fixtures') `
            -RepoRoot $script:RepoRoot -ActResultPath $script:ActResultPath

        # Case 2: an all-passing set with no flaky tests (contrasting output).
        $script:Clean = Invoke-WorkflowActCase `
            -CaseName 'clean-all-passing' `
            -FixtureSource (Join-Path $script:RepoRoot 'tests/cases/clean') `
            -RepoRoot $script:RepoRoot -ActResultPath $script:ActResultPath
    }

    Context 'Case: comprehensive matrix (XML + JSON, one flaky test)' {
        It 'act exits with code 0' {
            $script:Comprehensive.ExitCode | Should -Be 0
        }
        It 'the job succeeds' {
            $script:Comprehensive.Output | Should -Match 'Job succeeded'
        }
        It 'runs the unit tests inside the pipeline' {
            $script:Comprehensive.Output | Should -Match 'unit tests passed'
        }
        It 'reports the exact aggregate totals' {
            $expected = 'AGGREGATE_STATS TOTAL=18 PASSED=10 FAILED=5 SKIPPED=3 FLAKY=1 FILES=3 DURATION=1.31'
            $script:Comprehensive.Output | Should -Match ([regex]::Escape($expected))
        }
        It 'identifies exactly the flaky test Math::div' {
            $script:Comprehensive.Output | Should -Match ([regex]::Escape('FLAKY_TEST Math::div'))
            # Str::split fails every run, so it must NOT be reported as flaky.
            $script:Comprehensive.Output | Should -Not -Match ([regex]::Escape('FLAKY_TEST Str::split'))
        }
    }

    Context 'Case: clean all-passing (no flaky tests)' {
        It 'act exits with code 0' {
            $script:Clean.ExitCode | Should -Be 0
        }
        It 'the job succeeds' {
            $script:Clean.Output | Should -Match 'Job succeeded'
        }
        It 'reports the exact aggregate totals' {
            $expected = 'AGGREGATE_STATS TOTAL=4 PASSED=4 FAILED=0 SKIPPED=0 FLAKY=0 FILES=2 DURATION=0.40'
            $script:Clean.Output | Should -Match ([regex]::Escape($expected))
        }
        It 'reports no flaky tests' {
            $script:Clean.Output | Should -Match 'No flaky tests detected'
            $script:Clean.Output | Should -Not -Match 'FLAKY_TEST '
        }
    }

    It 'wrote the act-result.txt artifact' {
        Test-Path -LiteralPath $script:ActResultPath | Should -BeTrue
        (Get-Content -LiteralPath $script:ActResultPath -Raw) | Should -Match 'ACT CASE: comprehensive-matrix'
        (Get-Content -LiteralPath $script:ActResultPath -Raw) | Should -Match 'ACT CASE: clean-all-passing'
    }
}
