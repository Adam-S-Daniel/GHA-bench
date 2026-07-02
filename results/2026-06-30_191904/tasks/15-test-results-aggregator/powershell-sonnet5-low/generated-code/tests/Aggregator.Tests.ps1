# Pester tests for the Test Results Aggregator module.
# TDD: each Describe/It block below was written before the corresponding
# implementation in ../src/Aggregator.psm1.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'src' 'Aggregator.psm1') -Force
    $FixturesPath = Join-Path $PSScriptRoot '..' 'fixtures'
}

Describe 'Get-JUnitTestResults' {
    It 'parses passed, failed, and skipped test cases from a JUnit XML file' {
        $results = Get-JUnitTestResults -Path (Join-Path $FixturesPath 'junit-run1.xml') -RunName 'run1'

        $results.Count | Should -Be 4

        $add = $results | Where-Object { $_.Name -eq 'TestAdd' }
        $add.Status | Should -Be 'Passed'
        $add.RunName | Should -Be 'run1'
        $add.ClassName | Should -Be 'Sample.Tests'

        $sub = $results | Where-Object { $_.Name -eq 'TestSubtract' }
        $sub.Status | Should -Be 'Failed'

        $div = $results | Where-Object { $_.Name -eq 'TestDivide' }
        $div.Status | Should -Be 'Skipped'
    }

    It 'throws a meaningful error when the file does not exist' {
        { Get-JUnitTestResults -Path (Join-Path $FixturesPath 'does-not-exist.xml') -RunName 'run1' } |
            Should -Throw '*not found*'
    }
}

Describe 'Get-JsonTestResults' {
    It 'parses passed and skipped test cases from a JSON file' {
        $results = Get-JsonTestResults -Path (Join-Path $FixturesPath 'results-run3.json') -RunName 'run3'

        $results.Count | Should -Be 4

        $add = $results | Where-Object { $_.Name -eq 'TestAdd' }
        $add.Status | Should -Be 'Passed'
        $add.RunName | Should -Be 'run3'

        $div = $results | Where-Object { $_.Name -eq 'TestDivide' }
        $div.Status | Should -Be 'Skipped'
    }

    It 'throws a meaningful error when the file does not exist' {
        { Get-JsonTestResults -Path (Join-Path $FixturesPath 'does-not-exist.json') -RunName 'run3' } |
            Should -Throw '*not found*'
    }
}

Describe 'Merge-TestResults' {
    BeforeAll {
        $run1 = Get-JUnitTestResults -Path (Join-Path $FixturesPath 'junit-run1.xml') -RunName 'run1'
        $run2 = Get-JUnitTestResults -Path (Join-Path $FixturesPath 'junit-run2.xml') -RunName 'run2'
        $run3 = Get-JsonTestResults -Path (Join-Path $FixturesPath 'results-run3.json') -RunName 'run3'
        $script:Merged = Merge-TestResults -Results ($run1 + $run2 + $run3)
    }

    It 'computes totals across all runs' {
        $Merged.TotalPassed | Should -Be 7
        $Merged.TotalFailed | Should -Be 2
        $Merged.TotalSkipped | Should -Be 3
    }

    It 'identifies flaky tests that pass in some runs and fail in others' {
        $Merged.FlakyTests.Count | Should -Be 2
        ($Merged.FlakyTests.Name | Sort-Object) | Should -Be @('TestMultiply', 'TestSubtract')
    }

    It 'does not mark consistently passing or skipped tests as flaky' {
        $add = $Merged.Tests | Where-Object { $_.Name -eq 'TestAdd' }
        $add.IsFlaky | Should -Be $false
        $add.FinalStatus | Should -Be 'Passed'

        $div = $Merged.Tests | Where-Object { $_.Name -eq 'TestDivide' }
        $div.IsFlaky | Should -Be $false
        $div.FinalStatus | Should -Be 'Skipped'
    }
}

Describe 'New-MarkdownSummary' {
    BeforeAll {
        $run1 = Get-JUnitTestResults -Path (Join-Path $FixturesPath 'junit-run1.xml') -RunName 'run1'
        $run2 = Get-JUnitTestResults -Path (Join-Path $FixturesPath 'junit-run2.xml') -RunName 'run2'
        $run3 = Get-JsonTestResults -Path (Join-Path $FixturesPath 'results-run3.json') -RunName 'run3'
        $merged = Merge-TestResults -Results ($run1 + $run2 + $run3)
        $script:Summary = New-MarkdownSummary -Aggregated $merged
    }

    It 'includes a markdown heading and totals table' {
        $Summary | Should -Match '# Test Results Summary'
        $Summary | Should -Match '\| 7 \| 2 \| 3 \|'
    }

    It 'includes a flaky tests section listing flaky test names' {
        $Summary | Should -Match ':warning: Flaky Tests'
        $Summary | Should -Match 'TestSubtract'
        $Summary | Should -Match 'TestMultiply'
    }
}
