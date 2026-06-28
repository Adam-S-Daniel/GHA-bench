#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
    Workflow tests for .github/workflows/test-results-aggregator.yml

    Two layers:
      1. Static structure tests (fast, no Docker): parse the YAML, assert the
         triggers/jobs/steps, verify referenced script paths exist, and assert
         that actionlint passes (exit 0).
      2. End-to-end tests through `act` (tagged 'Act'): for each fixture case,
         build a temp git repo, run `act push`, append the output to
         act-result.txt, and assert on EXACT expected values plus job success.

    Run static only:   Invoke-Pester ./tests/Workflow.Tests.ps1 -ExcludeTagFilter Act
    Run everything:     Invoke-Pester ./tests/Workflow.Tests.ps1
#>

BeforeAll {
    $script:RepoRoot      = Split-Path -Parent $PSScriptRoot
    $script:WorkflowPath  = Join-Path $RepoRoot '.github/workflows/test-results-aggregator.yml'
    $script:ActResultFile = Join-Path $RepoRoot 'act-result.txt'

    . (Join-Path $PSScriptRoot 'ActHarness.ps1')

    Import-Module powershell-yaml -ErrorAction Stop
    $script:Workflow = Get-Content -LiteralPath $WorkflowPath -Raw | ConvertFrom-Yaml

    # YAML 1.1 parsers may render the `on:` key as the boolean $true. Fetch it
    # robustly so trigger assertions don't depend on that quirk.
    $script:Triggers = if ($Workflow.Contains('on')) { $Workflow['on'] }
                       elseif ($Workflow.Contains($true)) { $Workflow[$true] }
                       else { $null }

    # Helper for counting non-overlapping literal occurrences in act output.
    function script:Get-MatchCount {
        param([string]$Text, [string]$Literal)
        return ([regex]::Matches($Text, [regex]::Escape($Literal))).Count
    }

    # NOTE: act-result.txt is reset inside the first 'Act'-tagged describe (not
    # here), so a static-only run (`-ExcludeTagFilter Act`) never truncates the
    # required artifact.
}

Describe 'Workflow file structure' {
    It 'exists at the conventional path' {
        Test-Path -LiteralPath $WorkflowPath | Should -BeTrue
    }

    It 'declares the workflow name' {
        $Workflow.name | Should -Be 'Test Results Aggregator'
    }

    It 'configures the expected trigger events' {
        $Triggers | Should -Not -BeNullOrEmpty
        $keys = @($Triggers.Keys | ForEach-Object { "$_" })
        $keys | Should -Contain 'push'
        $keys | Should -Contain 'pull_request'
        $keys | Should -Contain 'schedule'
        $keys | Should -Contain 'workflow_dispatch'
    }

    It 'declares least-privilege contents:read permissions' {
        $Workflow.permissions.contents | Should -Be 'read'
    }

    It 'defines a RESULTS_DIR environment variable' {
        $Workflow.env.RESULTS_DIR | Should -Be 'fixtures'
    }

    It 'defines both the aggregate and report jobs' {
        $Workflow.jobs.Keys | Should -Contain 'aggregate'
        $Workflow.jobs.Keys | Should -Contain 'report'
    }

    It 'makes the report job depend on the aggregate job' {
        $Workflow.jobs.report.needs | Should -Be 'aggregate'
    }

    It 'runs the aggregator through a pwsh shell step' {
        $aggStep = $Workflow.jobs.aggregate.steps | Where-Object { $_.id -eq 'agg' }
        $aggStep | Should -Not -BeNullOrEmpty
        $aggStep.shell | Should -Be 'pwsh'
        $aggStep.run | Should -Match 'Invoke-Aggregator\.ps1'
    }

    It 'checks out the repository with actions/checkout@v4' {
        $uses = @($Workflow.jobs.aggregate.steps | ForEach-Object { $_.uses })
        $uses | Should -Contain 'actions/checkout@v4'
    }

    It 'exposes aggregate totals as job outputs consumed by the report job' {
        $Workflow.jobs.aggregate.outputs.Keys | Should -Contain 'failed'
        $Workflow.jobs.aggregate.outputs.Keys | Should -Contain 'flaky'
        $reportStep = $Workflow.jobs.report.steps | Select-Object -First 1
        $reportStep.env.FLAKY | Should -Match 'needs\.aggregate\.outputs\.flaky'
    }
}

Describe 'Referenced files exist' {
    It 'references Invoke-Aggregator.ps1 which exists in the repo' {
        $Workflow.jobs.aggregate.steps.run -join "`n" | Should -Match 'Invoke-Aggregator\.ps1'
        Test-Path -LiteralPath (Join-Path $RepoRoot 'Invoke-Aggregator.ps1') | Should -BeTrue
    }

    It 'ships the library the entry point dot-sources' {
        Test-Path -LiteralPath (Join-Path $RepoRoot 'TestResultsAggregator.ps1') | Should -BeTrue
    }

    It 'ships the default fixtures directory the workflow reads' {
        Test-Path -LiteralPath (Join-Path $RepoRoot 'fixtures') | Should -BeTrue
    }
}

Describe 'actionlint validation' {
    It 'passes actionlint with exit code 0' {
        $actionlint = Get-Command actionlint -ErrorAction SilentlyContinue
        $actionlint | Should -Not -BeNullOrEmpty -Because 'actionlint is pre-installed'
        $out = & actionlint $WorkflowPath 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($out -join "`n")
    }
}

Describe 'End-to-end via act: matrix fixtures (case A)' -Tag 'Act' {
    BeforeAll {
        # Start a fresh act-result.txt for this run (the first act case owns the
        # reset, so static-only runs leave the artifact intact).
        Set-Content -LiteralPath $ActResultFile -Value "act push --rm output for test-results-aggregator`n"

        # The default fixtures/ directory holds the 3-leg matrix (case A).
        $script:CaseA = Invoke-ActCase `
            -CaseName 'case-a-matrix' `
            -RepoRoot $RepoRoot `
            -FixtureSource (Join-Path $RepoRoot 'fixtures') `
            -ActResultFile $ActResultFile
    }

    It 'act exits with code 0' {
        $CaseA.ExitCode | Should -Be 0 -Because $CaseA.Output
    }

    It 'shows both jobs succeeding' {
        (Get-MatchCount $CaseA.Output 'Job succeeded') | Should -BeGreaterOrEqual 2
    }

    It 'emits the exact aggregate summary line' {
        $CaseA.Output.Contains('[SUMMARY] passed=12 failed=3 skipped=3 total=18 runs=3 duration=3.61 passrate=80.0') |
            Should -BeTrue -Because $CaseA.Output
    }

    It 'reports exactly 3 flaky tests' {
        $CaseA.Output.Contains('[FLAKY] count=3') | Should -BeTrue
    }

    It 'identifies each flaky test with its exact pass/fail tally' {
        $CaseA.Output.Contains('[FLAKY] Calculator.Divide passed=2 failed=1 runs=3')   | Should -BeTrue
        $CaseA.Output.Contains('[FLAKY] Calculator.Multiply passed=2 failed=1 runs=3') | Should -BeTrue
        $CaseA.Output.Contains('[FLAKY] Network.Connect passed=2 failed=1 runs=3')     | Should -BeTrue
    }

    It 'renders the markdown totals table into the CI log' {
        $CaseA.Output.Contains('| Passed | 12 |') | Should -BeTrue
        $CaseA.Output.Contains('| Failed | 3 |')  | Should -BeTrue
    }

    It 'passes the totals across the job dependency to the report job' {
        $CaseA.Output.Contains('[GATE] passed=12 failed=3 skipped=3 total=18 flaky=3') |
            Should -BeTrue -Because $CaseA.Output
    }
}

Describe 'End-to-end via act: clean fixtures (case B)' -Tag 'Act' {
    BeforeAll {
        $script:CaseB = Invoke-ActCase `
            -CaseName 'case-b-clean' `
            -RepoRoot $RepoRoot `
            -FixtureSource (Join-Path $RepoRoot 'testcases/case-b') `
            -ActResultFile $ActResultFile
    }

    It 'act exits with code 0' {
        $CaseB.ExitCode | Should -Be 0 -Because $CaseB.Output
    }

    It 'shows both jobs succeeding' {
        (Get-MatchCount $CaseB.Output 'Job succeeded') | Should -BeGreaterOrEqual 2
    }

    It 'emits the exact aggregate summary line for an all-passing run' {
        $CaseB.Output.Contains('[SUMMARY] passed=3 failed=0 skipped=0 total=3 runs=1 duration=1.75 passrate=100.0') |
            Should -BeTrue -Because $CaseB.Output
    }

    It 'reports zero flaky tests' {
        $CaseB.Output.Contains('[FLAKY] count=0') | Should -BeTrue
    }

    It 'renders "No flaky tests detected." in the summary' {
        $CaseB.Output.Contains('No flaky tests detected.') | Should -BeTrue
    }

    It 'passes the clean totals across the job dependency' {
        $CaseB.Output.Contains('[GATE] passed=3 failed=0 skipped=0 total=3 flaky=0') |
            Should -BeTrue -Because $CaseB.Output
    }
}
