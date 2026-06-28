#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
    Unit tests for the Test Results Aggregator library.

    Written red/green TDD style: each block describes one piece of behaviour of
    the functions in TestResultsAggregator.ps1. They call the library functions
    directly so the red/green cycle stays fast. The end-to-end pipeline (script
    + GitHub Actions workflow) is exercised separately through `act` in
    Workflow.Tests.ps1.
#>

BeforeAll {
    $script:RepoRoot    = Split-Path -Parent $PSScriptRoot
    . (Join-Path $RepoRoot 'TestResultsAggregator.ps1')
    $script:FixturesDir = Join-Path $RepoRoot 'fixtures'

    # The three matrix-run fixtures aggregate to known totals (see fixtures/*):
    #   passed=12 failed=3 skipped=3 total=18 runs=3 duration=3.61
    #   flaky=3 (Calculator.Divide, Calculator.Multiply, Network.Connect)
    $script:AllResults = Import-TestResultSet -Path $FixturesDir
}

Describe 'Import-JUnitResult' {
    BeforeAll {
        $script:R1 = Import-JUnitResult -Path (Join-Path $FixturesDir 'run1.junit.xml')
    }

    It 'parses every testcase across all testsuite elements' {
        $R1.Count | Should -Be 6
    }

    It 'marks a testcase with a failure child as Failed' {
        ($R1 | Where-Object FullName -eq 'Network.Connect').Status | Should -Be 'Failed'
    }

    It 'marks a testcase with a skipped child as Skipped' {
        ($R1 | Where-Object FullName -eq 'Network.Timeout').Status | Should -Be 'Skipped'
    }

    It 'marks a plain testcase as Passed' {
        ($R1 | Where-Object FullName -eq 'Calculator.Add').Status | Should -Be 'Passed'
    }

    It 'reads the time attribute as a numeric duration in seconds' {
        ($R1 | Where-Object FullName -eq 'Calculator.Divide').Duration | Should -Be 0.30
    }

    It 'uses the testcase classname as the suite component of FullName' {
        ($R1 | Where-Object Name -eq 'Add').FullName | Should -Be 'Calculator.Add'
    }

    It 'throws a meaningful error when the file does not exist' {
        { Import-JUnitResult -Path (Join-Path $FixturesDir 'nope.xml') } |
            Should -Throw '*not found*'
    }
}

Describe 'Import-JsonResult' {
    BeforeAll {
        $script:R3 = Import-JsonResult -Path (Join-Path $FixturesDir 'run3.json')
    }

    It 'parses every entry from the tests array' {
        $R3.Count | Should -Be 6
    }

    It 'normalizes the status field' {
        ($R3 | Where-Object FullName -eq 'Calculator.Multiply').Status | Should -Be 'Failed'
    }

    It 'honours the file-level run name override' {
        ($R3 | Select-Object -First 1).Run | Should -Be 'ubuntu-py3.12'
    }

    It 'throws when a JSON file is malformed' {
        $bad = Join-Path $TestDrive 'bad.json'
        Set-Content -LiteralPath $bad -Value '{ not valid json'
        { Import-JsonResult -Path $bad } | Should -Throw '*Failed to parse JSON*'
    }

    It 'throws when a test entry lacks a required field' {
        $bad = Join-Path $TestDrive 'nofield.json'
        Set-Content -LiteralPath $bad -Value '{ "tests": [ { "name": "x" } ] }'
        { Import-JsonResult -Path $bad } | Should -Throw '*missing the required*'
    }
}

Describe 'Import-TestResultFile' {
    It 'dispatches .xml files to the JUnit parser' {
        (Import-TestResultFile -Path (Join-Path $FixturesDir 'run1.junit.xml')).Count | Should -Be 6
    }

    It 'dispatches .json files to the JSON parser' {
        (Import-TestResultFile -Path (Join-Path $FixturesDir 'run3.json')).Count | Should -Be 6
    }

    It 'throws on an unsupported extension' {
        $bad = Join-Path $TestDrive 'results.txt'
        Set-Content -LiteralPath $bad -Value 'nope'
        { Import-TestResultFile -Path $bad } | Should -Throw '*Unsupported test result file type*'
    }
}

Describe 'Import-TestResultSet' {
    It 'loads and flattens every result file in a directory' {
        $AllResults.Count | Should -Be 18
    }

    It 'throws when no result files are found' {
        $empty = Join-Path $TestDrive 'empty'
        New-Item -ItemType Directory -Path $empty | Out-Null
        { Import-TestResultSet -Path $empty } | Should -Throw '*No test result files*'
    }
}

Describe 'Get-AggregateSummary' {
    BeforeAll {
        $script:Summary = Get-AggregateSummary -Result $AllResults
    }

    It 'counts passed results across all runs'  { $Summary.Passed  | Should -Be 12 }
    It 'counts failed results across all runs'  { $Summary.Failed  | Should -Be 3 }
    It 'counts skipped results across all runs' { $Summary.Skipped | Should -Be 3 }
    It 'counts the grand total'                 { $Summary.Total   | Should -Be 18 }
    It 'counts the distinct runs'               { $Summary.Runs    | Should -Be 3 }

    It 'sums the duration across all runs' {
        [math]::Round($Summary.Duration, 2) | Should -Be 3.61
    }

    It 'computes pass rate excluding skipped tests' {
        # 12 passed / (12 passed + 3 failed) = 80.0%
        $Summary.PassRate | Should -Be 80.0
    }

    It 'reports passrate of 100 when there are no decided tests' {
        $onlySkipped = @([pscustomobject]@{ FullName = 'a'; Status = 'Skipped'; Duration = 0.0; Run = 'r' })
        (Get-AggregateSummary -Result $onlySkipped).PassRate | Should -Be 100.0
    }
}

Describe 'Get-FlakyTest' {
    BeforeAll {
        $script:Flaky = Get-FlakyTest -Result $AllResults
    }

    It 'finds exactly the tests that both passed and failed across runs' {
        $Flaky.Count | Should -Be 3
    }

    It 'identifies each flaky test by full name' {
        ($Flaky.FullName | Sort-Object) | Should -Be @('Calculator.Divide', 'Calculator.Multiply', 'Network.Connect')
    }

    It 'records the pass and fail tallies for a flaky test' {
        $divide = $Flaky | Where-Object FullName -eq 'Calculator.Divide'
        $divide.Passed | Should -Be 2
        $divide.Failed | Should -Be 1
    }

    It 'does not flag an always-passing test as flaky' {
        ($Flaky.FullName -contains 'Calculator.Add') | Should -BeFalse
    }

    It 'does not flag an always-skipped test as flaky' {
        ($Flaky.FullName -contains 'Network.Timeout') | Should -BeFalse
    }
}

Describe 'Format-MarkdownSummary' {
    BeforeAll {
        $script:Md = Format-MarkdownSummary -Summary (Get-AggregateSummary -Result $AllResults)
    }

    It 'renders a top-level heading' {
        $Md | Should -Match '# Test Results Summary'
    }

    It 'renders the totals table with exact counts' {
        $Md | Should -Match '\| Passed \| 12 \|'
        $Md | Should -Match '\| Failed \| 3 \|'
        $Md | Should -Match '\| Skipped \| 3 \|'
        $Md | Should -Match '\| Total \| 18 \|'
    }

    It 'renders the total duration formatted to two decimals' {
        $Md | Should -Match 'Total duration: \*\*3\.61s\*\*'
    }

    It 'lists each flaky test in the flaky table' {
        $Md | Should -Match '\| Calculator\.Divide \| 2 \| 1 \|'
        $Md | Should -Match '\| Calculator\.Multiply \| 2 \| 1 \|'
        $Md | Should -Match '\| Network\.Connect \| 2 \| 1 \|'
    }

    It 'reports "No flaky tests detected." when there are none' {
        $clean = @(
            [pscustomobject]@{ FullName = 'A.one'; Status = 'Passed'; Duration = 0.1; Run = 'r1' },
            [pscustomobject]@{ FullName = 'A.one'; Status = 'Passed'; Duration = 0.1; Run = 'r2' }
        )
        $md2 = Format-MarkdownSummary -Summary (Get-AggregateSummary -Result $clean)
        $md2 | Should -Match 'No flaky tests detected\.'
    }
}
