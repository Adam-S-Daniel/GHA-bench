<#
.SYNOPSIS
    Pester tests for the TestResultsAggregator module.

.DESCRIPTION
    Built with red/green TDD. Each Describe block corresponds to one
    red/green cycle:
      1. Parsers (JUnit XML + JSON) and format dispatch  -> written first, failed, then implemented
      2. Aggregation (totals + flaky detection)          -> written next, failed, then implemented
      3. Markdown summary generation                     -> written last, failed, then implemented
    Unit fixtures live in tests/fixtures and are independent from the
    workflow input fixtures in ./fixtures, so swapping workflow inputs
    (as the act harness does) never breaks these tests.
#>

BeforeAll {
    $script:ModulePath = Join-Path $PSScriptRoot '..' 'src' 'TestResultsAggregator.psm1'
    Import-Module $script:ModulePath -Force
    $script:FixtureDir = Join-Path $PSScriptRoot 'fixtures'
}

Describe 'ConvertFrom-JUnitXml' {
    BeforeAll {
        $script:results = ConvertFrom-JUnitXml -Path (Join-Path $FixtureDir 'junit-basic.xml')
    }

    It 'parses every testcase in the file' {
        $results | Should -HaveCount 4
    }

    It 'maps a testcase with no child element to Passed' {
        ($results | Where-Object Name -eq 'test_add').Status | Should -Be 'Passed'
    }

    It 'maps a <failure> element to Failed' {
        ($results | Where-Object Name -eq 'test_sub').Status | Should -Be 'Failed'
    }

    It 'maps an <error> element to Failed as well' {
        ($results | Where-Object Name -eq 'test_div').Status | Should -Be 'Failed'
    }

    It 'maps a <skipped> element to Skipped' {
        ($results | Where-Object Name -eq 'test_mul').Status | Should -Be 'Skipped'
    }

    It 'captures classname and duration' {
        $add = $results | Where-Object Name -eq 'test_add'
        $add.ClassName | Should -Be 'Calc'
        $add.Duration | Should -Be 0.10
    }

    It 'records the source file on every result' {
        $results.SourceFile | Should -Not -Contain $null
        ($results.SourceFile | Select-Object -Unique) | Should -Match 'junit-basic\.xml$'
    }

    It 'throws a meaningful error for a missing file' {
        { ConvertFrom-JUnitXml -Path (Join-Path $FixtureDir 'does-not-exist.xml') } |
            Should -Throw '*not found*'
    }

    It 'throws a meaningful error for malformed XML' {
        { ConvertFrom-JUnitXml -Path (Join-Path $FixtureDir 'malformed.xml') } |
            Should -Throw '*malformed.xml*not valid JUnit XML*'
    }
}

Describe 'ConvertFrom-JsonTestResult' {
    BeforeAll {
        $script:results = ConvertFrom-JsonTestResult -Path (Join-Path $FixtureDir 'results-basic.json')
    }

    It 'parses every test entry in the file' {
        $results | Should -HaveCount 3
    }

    It 'normalizes lowercase status strings to canonical casing' {
        ($results | Where-Object Name -eq 'test_get').Status | Should -BeExactly 'Passed'
        ($results | Where-Object Name -eq 'test_post').Status | Should -BeExactly 'Failed'
        ($results | Where-Object Name -eq 'test_delete').Status | Should -BeExactly 'Skipped'
    }

    It 'captures classname and duration' {
        $get = $results | Where-Object Name -eq 'test_get'
        $get.ClassName | Should -Be 'Api'
        $get.Duration | Should -Be 0.25
    }

    It 'throws a meaningful error for a missing file' {
        { ConvertFrom-JsonTestResult -Path (Join-Path $FixtureDir 'nope.json') } |
            Should -Throw '*not found*'
    }

    It 'throws a meaningful error for malformed JSON' {
        { ConvertFrom-JsonTestResult -Path (Join-Path $FixtureDir 'malformed.json') } |
            Should -Throw '*malformed.json*not valid JSON*'
    }
}

Describe 'Import-TestResultFile (format dispatch)' {
    It 'dispatches .xml files to the JUnit parser' {
        $r = Import-TestResultFile -Path (Join-Path $FixtureDir 'junit-basic.xml')
        $r | Should -HaveCount 4
    }

    It 'dispatches .json files to the JSON parser' {
        $r = Import-TestResultFile -Path (Join-Path $FixtureDir 'results-basic.json')
        $r | Should -HaveCount 3
    }

    It 'throws a meaningful error for unsupported extensions' {
        { Import-TestResultFile -Path 'results.csv' } |
            Should -Throw '*Unsupported test result format*.csv*'
    }
}

Describe 'Get-TestResultSummary (aggregation across matrix runs)' {
    BeforeAll {
        # Helper to build normalized records without touching the parsers —
        # aggregation is tested in isolation from file I/O.
        function New-Result {
            param($Name, $Status, $Duration = 0.1, $File = 'run1.xml', $ClassName = 'Suite')
            [pscustomobject]@{
                Name       = $Name
                ClassName  = $ClassName
                Suite      = 'suite'
                Status     = $Status
                Duration   = $Duration
                SourceFile = $File
            }
        }

        # Simulated 2-run matrix: test_flaky flips between runs,
        # test_bad fails consistently, test_ok passes consistently.
        $script:matrix = @(
            New-Result 'test_ok'    'Passed'  0.5  'run1.xml'
            New-Result 'test_bad'   'Failed'  0.25 'run1.xml'
            New-Result 'test_flaky' 'Failed'  1.0  'run1.xml'
            New-Result 'test_skip'  'Skipped' 0.0  'run1.xml'
            New-Result 'test_ok'    'Passed'  0.5  'run2.json'
            New-Result 'test_bad'   'Failed'  0.25 'run2.json'
            New-Result 'test_flaky' 'Passed'  1.5  'run2.json'
        )
        $script:summary = Get-TestResultSummary -Results $matrix
    }

    It 'counts every executed test across all runs' {
        $summary.Total | Should -Be 7
    }

    It 'computes passed/failed/skipped totals' {
        $summary.Passed | Should -Be 3
        $summary.Failed | Should -Be 3
        $summary.Skipped | Should -Be 1
    }

    It 'sums duration across all runs' {
        $summary.Duration | Should -Be 4.0
    }

    It 'counts the number of distinct source files' {
        $summary.FileCount | Should -Be 2
    }

    It 'flags a test that both passed and failed as flaky' {
        $summary.FlakyTests | Should -HaveCount 1
        $summary.FlakyTests[0].Name | Should -Be 'Suite.test_flaky'
        $summary.FlakyTests[0].Passed | Should -Be 1
        $summary.FlakyTests[0].Failed | Should -Be 1
    }

    It 'does not flag consistent passes or consistent failures as flaky' {
        $summary.FlakyTests.Name | Should -Not -Contain 'Suite.test_ok'
        $summary.FlakyTests.Name | Should -Not -Contain 'Suite.test_bad'
    }

    It 'returns an empty flaky list when no test flip-flops' {
        $clean = Get-TestResultSummary -Results @(
            New-Result 'test_a' 'Passed' 0.1 'run1.xml'
            New-Result 'test_a' 'Passed' 0.1 'run2.xml'
        )
        $clean.FlakyTests | Should -HaveCount 0
    }

    It 'handles an empty result set gracefully' {
        $empty = Get-TestResultSummary -Results @()
        $empty.Total | Should -Be 0
        $empty.Duration | Should -Be 0
        $empty.FlakyTests | Should -HaveCount 0
    }
}

Describe 'Import-TestResultDirectory' {
    It 'aggregates every .xml and .json file in a directory' {
        $results = Import-TestResultDirectory -Path $FixtureDir -Include 'junit-basic.xml', 'results-basic.json'
        $results | Should -HaveCount 7   # 4 from XML + 3 from JSON
    }

    It 'throws a meaningful error when the directory does not exist' {
        { Import-TestResultDirectory -Path (Join-Path $FixtureDir 'no-such-dir') } |
            Should -Throw '*directory*not found*'
    }

    It 'throws a meaningful error when no result files are present' {
        $emptyDir = Join-Path ([System.IO.Path]::GetTempPath()) "tra-empty-$(New-Guid)"
        New-Item -ItemType Directory -Path $emptyDir | Out-Null
        try {
            { Import-TestResultDirectory -Path $emptyDir } |
                Should -Throw '*No test result files*'
        }
        finally {
            Remove-Item $emptyDir -Recurse -Force
        }
    }
}

Describe 'New-MarkdownSummary' {
    BeforeAll {
        # A pre-computed summary object (shape produced by Get-TestResultSummary).
        $script:withFlaky = [pscustomobject]@{
            Total      = 10
            Passed     = 6
            Failed     = 3
            Skipped    = 1
            Duration   = 4.25
            FileCount  = 3
            FlakyTests = @([pscustomobject]@{ Name = 'Suite.test_flaky'; Passed = 2; Failed = 1 })
        }
        $script:md = New-MarkdownSummary -Summary $withFlaky
    }

    It 'starts with a level-1 heading' {
        $md | Should -Match '(?m)^# 🧪 Test Results Summary'
    }

    It 'renders exact counts in the totals table' {
        $md | Should -Match ([regex]::Escape('| ✅ Passed | 6 |'))
        $md | Should -Match ([regex]::Escape('| ❌ Failed | 3 |'))
        $md | Should -Match ([regex]::Escape('| ⏭️ Skipped | 1 |'))
        $md | Should -Match ([regex]::Escape('| **Total** | **10** |'))
    }

    It 'renders duration and file count' {
        $md | Should -Match ([regex]::Escape('**Duration:** 4.25s across 3 result file(s)'))
    }

    It 'lists flaky tests with pass/fail counts' {
        $md | Should -Match '(?m)^## ⚠️ Flaky Tests'
        $md | Should -Match ([regex]::Escape('| Suite.test_flaky | 2 | 1 |'))
    }

    It 'reports when no flaky tests exist' {
        $clean = [pscustomobject]@{
            Total = 3; Passed = 3; Failed = 0; Skipped = 0
            Duration = 0.75; FileCount = 2; FlakyTests = @()
        }
        $cleanMd = New-MarkdownSummary -Summary $clean
        $cleanMd | Should -Match ([regex]::Escape('✨ No flaky tests detected.'))
        $cleanMd | Should -Not -Match '## ⚠️ Flaky Tests'
    }

    It 'formats duration with invariant culture (dot decimal separator)' {
        $md | Should -Match '4\.25s'
    }
}
