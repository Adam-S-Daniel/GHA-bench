# Pester tests for the Test Results Aggregator.
# Written red/green: each Describe block starts with a failing assertion
# against not-yet-implemented functions in TestResultsAggregator.ps1.

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestResultsAggregator.ps1')
    $script:FixturesDir = Join-Path $PSScriptRoot 'fixtures'
    $script:WorkflowPath = Join-Path $PSScriptRoot '.github/workflows/test-results-aggregator.yml'
}

Describe 'Parse-JUnitXmlResult' {
    It 'parses testcases, statuses, and durations from a JUnit XML file' {
        $result = Parse-JUnitXmlResult -Path (Join-Path $FixturesDir 'junit-run1-ubuntu.xml') -RunName 'ubuntu'

        $result.RunName | Should -Be 'ubuntu'
        $result.SuiteName | Should -Be 'MathTests'
        $result.Tests.Count | Should -Be 4

        $divide = $result.Tests | Where-Object { $_.Name -eq 'TestDivide' }
        $divide.Status | Should -Be 'failed'
        $divide.FailureMessage | Should -Be 'Expected 2 but got 3'
        $divide.Duration | Should -Be 0.500

        $modulo = $result.Tests | Where-Object { $_.Name -eq 'TestModulo' }
        $modulo.Status | Should -Be 'skipped'

        $add = $result.Tests | Where-Object { $_.Name -eq 'TestAdd' }
        $add.Status | Should -Be 'passed'
    }

    It 'throws a meaningful error for a missing file' {
        { Parse-JUnitXmlResult -Path (Join-Path $FixturesDir 'does-not-exist.xml') -RunName 'x' } |
            Should -Throw '*not found*'
    }

    It 'throws a meaningful error for malformed XML' {
        { Parse-JUnitXmlResult -Path (Join-Path $FixturesDir 'malformed.xml') -RunName 'x' } |
            Should -Throw '*Failed to parse*'
    }
}

Describe 'Parse-JsonResult' {
    It 'parses testcases, statuses, and durations from a JSON result file' {
        $result = Parse-JsonResult -Path (Join-Path $FixturesDir 'results-run3-macos.json') -RunName 'macos'

        $result.RunName | Should -Be 'macos'
        $result.SuiteName | Should -Be 'MathTests'
        $result.Tests.Count | Should -Be 5

        $multiply = $result.Tests | Where-Object { $_.Name -eq 'TestMultiply' }
        $multiply.Status | Should -Be 'passed'
        $multiply.Duration | Should -Be 0.050

        $modulo = $result.Tests | Where-Object { $_.Name -eq 'TestModulo' }
        $modulo.Status | Should -Be 'skipped'
    }

    It 'throws a meaningful error for a missing file' {
        { Parse-JsonResult -Path (Join-Path $FixturesDir 'does-not-exist.json') -RunName 'x' } |
            Should -Throw '*not found*'
    }

    It 'throws a meaningful error for malformed JSON' {
        { Parse-JsonResult -Path (Join-Path $FixturesDir 'malformed.json') -RunName 'x' } |
            Should -Throw '*Failed to parse*'
    }
}

Describe 'Merge-TestResults' {
    BeforeAll {
        $script:Run1 = Parse-JUnitXmlResult -Path (Join-Path $FixturesDir 'junit-run1-ubuntu.xml') -RunName 'ubuntu'
        $script:Run2 = Parse-JUnitXmlResult -Path (Join-Path $FixturesDir 'junit-run2-windows.xml') -RunName 'windows'
        $script:Run3 = Parse-JsonResult -Path (Join-Path $FixturesDir 'results-run3-macos.json') -RunName 'macos'
        $script:Aggregate = Merge-TestResults -Runs @($Run1, $Run2, $Run3)
    }

    It 'computes total test executions across all runs' {
        $Aggregate.TotalTests | Should -Be 13
    }

    It 'computes passed/failed/skipped totals across all runs' {
        $Aggregate.Passed | Should -Be 9
        $Aggregate.Failed | Should -Be 1
        $Aggregate.Skipped | Should -Be 3
    }

    It 'sums duration across all runs' {
        [Math]::Round($Aggregate.Duration, 2) | Should -Be 1.95
    }

    It 'retains the individual run results' {
        $Aggregate.Runs.Count | Should -Be 3
    }
}

Describe 'Find-FlakyTests' {
    It 'identifies tests that passed in some runs and failed in others' {
        $run1 = Parse-JUnitXmlResult -Path (Join-Path $FixturesDir 'junit-run1-ubuntu.xml') -RunName 'ubuntu'
        $run2 = Parse-JUnitXmlResult -Path (Join-Path $FixturesDir 'junit-run2-windows.xml') -RunName 'windows'
        $run3 = Parse-JsonResult -Path (Join-Path $FixturesDir 'results-run3-macos.json') -RunName 'macos'

        $flaky = Find-FlakyTests -Runs @($run1, $run2, $run3)

        $flaky.Count | Should -Be 1
        $flaky[0].Name | Should -Be 'TestDivide'
        $flaky[0].PassedIn | Should -Contain 'windows'
        $flaky[0].PassedIn | Should -Contain 'macos'
        $flaky[0].FailedIn | Should -Contain 'ubuntu'
    }

    It 'returns an empty list when no test is flaky' {
        $run1 = Parse-JUnitXmlResult -Path (Join-Path $FixturesDir 'junit-run1-ubuntu.xml') -RunName 'ubuntu'
        $flaky = Find-FlakyTests -Runs @($run1)
        $flaky.Count | Should -Be 0
    }
}

Describe 'New-MarkdownSummary' {
    BeforeAll {
        $script:Run1 = Parse-JUnitXmlResult -Path (Join-Path $FixturesDir 'junit-run1-ubuntu.xml') -RunName 'ubuntu'
        $script:Run2 = Parse-JUnitXmlResult -Path (Join-Path $FixturesDir 'junit-run2-windows.xml') -RunName 'windows'
        $script:Run3 = Parse-JsonResult -Path (Join-Path $FixturesDir 'results-run3-macos.json') -RunName 'macos'
        $script:Aggregate = Merge-TestResults -Runs @($Run1, $Run2, $Run3)
        $script:Flaky = Find-FlakyTests -Runs @($Run1, $Run2, $Run3)
        $script:Markdown = New-MarkdownSummary -Aggregate $Aggregate -FlakyTests $Flaky
    }

    It 'includes a totals table with the correct counts' {
        $Markdown | Should -Match '\| Total \| 13 \|'
        $Markdown | Should -Match '\| Passed \| 9 \|'
        $Markdown | Should -Match '\| Failed \| 1 \|'
        $Markdown | Should -Match '\| Skipped \| 3 \|'
    }

    It 'includes a flaky tests section listing the flaky test' {
        $Markdown | Should -Match '(?m)^## Flaky Tests'
        $Markdown | Should -Match 'TestDivide'
    }

    It 'includes a per-run breakdown' {
        $Markdown | Should -Match 'ubuntu'
        $Markdown | Should -Match 'windows'
        $Markdown | Should -Match 'macos'
    }
}

Describe 'Invoke-TestResultsAggregation' {
    It 'discovers .xml and .json result files in a directory, aggregates them, and writes a summary' {
        $outputPath = Join-Path ([System.IO.Path]::GetTempPath()) "trs-summary-$([Guid]::NewGuid()).md"
        try {
            $summary = Invoke-TestResultsAggregation -InputDirectory $FixturesDir -OutputPath $outputPath -Include 'junit-run1-ubuntu.xml', 'junit-run2-windows.xml', 'results-run3-macos.json'

            $summary.Aggregate.TotalTests | Should -Be 13
            $summary.FlakyTests.Count | Should -Be 1
            Test-Path -LiteralPath $outputPath | Should -Be $true
            (Get-Content -LiteralPath $outputPath -Raw) | Should -Match '\| Total \| 13 \|'
        } finally {
            Remove-Item -LiteralPath $outputPath -ErrorAction SilentlyContinue
        }
    }

    It 'throws a meaningful error for an unsupported file extension' {
        $badDir = Join-Path ([System.IO.Path]::GetTempPath()) "trs-bad-$([Guid]::NewGuid())"
        New-Item -ItemType Directory -Path $badDir | Out-Null
        try {
            Set-Content -LiteralPath (Join-Path $badDir 'results.txt') -Value 'not a result file'
            { Invoke-TestResultsAggregation -InputDirectory $badDir -OutputPath (Join-Path $badDir 'out.md') } |
                Should -Throw '*Unsupported*'
        } finally {
            Remove-Item -LiteralPath $badDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'throws a meaningful error when the input directory does not exist' {
        { Invoke-TestResultsAggregation -InputDirectory '/no/such/dir' -OutputPath '/tmp/out.md' } |
            Should -Throw '*not found*'
    }
}

Describe 'GitHub Actions workflow structure' {
    BeforeAll {
        if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
            Install-Module -Name powershell-yaml -Force -Scope CurrentUser -SkipPublisherCheck
        }
        Import-Module powershell-yaml -ErrorAction Stop
        $script:WorkflowYaml = ConvertFrom-Yaml (Get-Content -LiteralPath $WorkflowPath -Raw)
    }

    It 'exists on disk' {
        Test-Path -LiteralPath $WorkflowPath | Should -Be $true
    }

    It 'declares push, pull_request, workflow_dispatch and schedule triggers' {
        $triggers = $WorkflowYaml['on']
        $triggers.Keys | Should -Contain 'push'
        $triggers.Keys | Should -Contain 'pull_request'
        $triggers.Keys | Should -Contain 'workflow_dispatch'
        $triggers.Keys | Should -Contain 'schedule'
    }

    It 'declares a test job and an aggregate job that depends on it' {
        $WorkflowYaml.jobs.Keys | Should -Contain 'test'
        $WorkflowYaml.jobs.Keys | Should -Contain 'aggregate'
        $WorkflowYaml.jobs.aggregate.needs | Should -Be 'test'
    }

    It 'references the aggregator script and test files that exist on disk' {
        $yamlText = Get-Content -LiteralPath $WorkflowPath -Raw
        $yamlText | Should -Match 'TestResultsAggregator\.ps1'
        $yamlText | Should -Match 'TestResultsAggregator\.Tests\.ps1'

        Test-Path -LiteralPath (Join-Path $PSScriptRoot 'TestResultsAggregator.ps1') | Should -Be $true
        Test-Path -LiteralPath (Join-Path $PSScriptRoot 'TestResultsAggregator.Tests.ps1') | Should -Be $true
    }

    It 'declares read-only top-level permissions' {
        $WorkflowYaml.permissions.contents | Should -Be 'read'
    }

    It 'passes actionlint validation' {
        $actionlint = Get-Command actionlint -ErrorAction SilentlyContinue
        if (-not $actionlint) {
            Set-ItResult -Skipped -Because 'actionlint is not installed on this machine'
            return
        }
        & actionlint $WorkflowPath
        $LASTEXITCODE | Should -Be 0
    }
}

Describe 'Workflow execution via act' {
    # This exercises the mandatory workflow-execution test: Invoke-ActTest.ps1
    # sets up an isolated temp git repo, runs `act push --rm`, and writes the
    # full output to act-result.txt. These assertions read that artifact and
    # check exact expected values -- they do not re-run act.
    BeforeAll {
        $script:ActResultPath = Join-Path $PSScriptRoot 'act-result.txt'
    }

    It 'produced the act-result.txt artifact' {
        Test-Path -LiteralPath $ActResultPath | Should -Be $true
    }

    It 'ran act push with a successful exit code' {
        (Get-Content -LiteralPath $ActResultPath -Raw) | Should -Match 'exit code 0'
    }

    It 'ran the "Run Pester unit tests" job successfully' {
        (Get-Content -LiteralPath $ActResultPath -Raw) |
            Should -Match '(?s)Run Pester unit tests\].*?🏁\s+Job succeeded'
    }

    It 'ran the "Aggregate test results" job successfully' {
        (Get-Content -LiteralPath $ActResultPath -Raw) |
            Should -Match '(?s)Aggregate test results\].*?🏁\s+Job succeeded'
    }

    It 'aggregated the fixture data to the exact expected totals' {
        $content = Get-Content -LiteralPath $ActResultPath -Raw
        $content | Should -Match 'Total: 13'
        $content | Should -Match 'Passed: 9'
        $content | Should -Match 'Failed: 1'
        $content | Should -Match 'Skipped: 3'
        $content | Should -Match 'FlakyCount: 1'
    }

    It 'includes the exact flaky test name in the job summary' {
        $content = Get-Content -LiteralPath $ActResultPath -Raw
        $content | Should -Match '\| TestDivide \| junit-run2-windows, results-run3-macos \| junit-run1-ubuntu \|'
    }
}
