#
# Pester tests for the Test Results Aggregator.
#
# TDD approach: each Describe block below was written BEFORE the corresponding
# function existed in TestResultsAggregator.psm1, run once to confirm it failed
# (red), then the minimum implementation was added to make it pass (green).
#
BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'TestResultsAggregator.psm1'
    Import-Module $ModulePath -Force

    $FixturesPath = Join-Path $PSScriptRoot '..' 'fixtures'
    # Valid matrix-build result files live in their own subfolder so the
    # aggregator script can glob a clean directory without tripping over the
    # malformed/unsupported fixtures used for error-handling tests.
    $MatrixFixturesPath = Join-Path $FixturesPath 'matrix-build'
}

Describe 'ConvertFrom-JUnitXml' {
    Context 'Parsing a well-formed JUnit XML file with a mix of statuses' {
        BeforeAll {
            $result = ConvertFrom-JUnitXml -Path (Join-Path $MatrixFixturesPath 'junit-ubuntu-node18.xml')
        }

        It 'Reports the suite name' {
            $result.SuiteName | Should -Be 'auth-service'
        }

        It 'Reports the source file' {
            $result.SourceFile | Should -Be 'junit-ubuntu-node18.xml'
        }

        It 'Parses the correct number of test cases' {
            $result.Tests.Count | Should -Be 5
        }

        It 'Marks a passing test as Passed' {
            ($result.Tests | Where-Object Name -eq 'login_succeeds').Status | Should -Be 'Passed'
        }

        It 'Marks a test with a <failure> element as Failed and captures the message' {
            $failing = $result.Tests | Where-Object Name -eq 'rate_limit_blocks_after_5_attempts'
            $failing.Status | Should -Be 'Failed'
            $failing.Message | Should -Be 'Expected HTTP 429 but got 200'
        }

        It 'Marks a test with a <skipped> element as Skipped' {
            ($result.Tests | Where-Object Name -eq 'token_refresh_works').Status | Should -Be 'Skipped'
        }

        It 'Computes correct summary totals' {
            $result.Summary.Total | Should -Be 5
            $result.Summary.Passed | Should -Be 3
            $result.Summary.Failed | Should -Be 1
            $result.Summary.Skipped | Should -Be 1
            $result.Summary.Duration | Should -Be 0.75
        }
    }

    Context 'Error handling' {
        It 'Throws a meaningful error for a missing file' {
            { ConvertFrom-JUnitXml -Path (Join-Path $FixturesPath 'does-not-exist.xml') } |
                Should -Throw '*does-not-exist.xml*not found*'
        }

        It 'Throws a meaningful error for malformed XML' {
            { ConvertFrom-JUnitXml -Path (Join-Path $FixturesPath 'malformed.xml') } |
                Should -Throw '*malformed.xml*'
        }
    }
}

Describe 'ConvertFrom-JsonTestResults' {
    Context 'Parsing a well-formed JSON result file with a mix of statuses' {
        BeforeAll {
            $result = ConvertFrom-JsonTestResults -Path (Join-Path $MatrixFixturesPath 'json-ubuntu-node20.json')
        }

        It 'Reports the suite name' {
            $result.SuiteName | Should -Be 'payments-service'
        }

        It 'Reports the source file' {
            $result.SourceFile | Should -Be 'json-ubuntu-node20.json'
        }

        It 'Parses the correct number of test cases' {
            $result.Tests.Count | Should -Be 4
        }

        It 'Marks a passing test as Passed' {
            ($result.Tests | Where-Object Name -eq 'charge_card_succeeds').Status | Should -Be 'Passed'
        }

        It 'Marks a failed test as Failed and captures the message' {
            $failing = $result.Tests | Where-Object Name -eq 'refund_processes'
            $failing.Status | Should -Be 'Failed'
            $failing.Message | Should -Be 'AssertionError: expected 200 got 500'
        }

        It 'Marks a skipped test as Skipped' {
            ($result.Tests | Where-Object Name -eq 'webhook_retries_on_failure').Status | Should -Be 'Skipped'
        }

        It 'Computes correct summary totals' {
            $result.Summary.Total | Should -Be 4
            $result.Summary.Passed | Should -Be 2
            $result.Summary.Failed | Should -Be 1
            $result.Summary.Skipped | Should -Be 1
            $result.Summary.Duration | Should -Be 1.30
        }
    }

    Context 'Error handling' {
        It 'Throws a meaningful error for a missing file' {
            { ConvertFrom-JsonTestResults -Path (Join-Path $FixturesPath 'does-not-exist.json') } |
                Should -Throw '*does-not-exist.json*not found*'
        }

        It 'Throws a meaningful error for malformed JSON' {
            { ConvertFrom-JsonTestResults -Path (Join-Path $FixturesPath 'malformed.json') } |
                Should -Throw '*malformed.json*'
        }
    }
}

Describe 'Get-TestResultFile' {
    It 'Dispatches .xml files to the JUnit parser' {
        $result = Get-TestResultFile -Path (Join-Path $MatrixFixturesPath 'junit-ubuntu-node18.xml')
        $result.Format | Should -Be 'JUnit'
        $result.SuiteName | Should -Be 'auth-service'
    }

    It 'Dispatches .json files to the JSON parser' {
        $result = Get-TestResultFile -Path (Join-Path $MatrixFixturesPath 'json-ubuntu-node20.json')
        $result.Format | Should -Be 'JSON'
        $result.SuiteName | Should -Be 'payments-service'
    }

    It 'Throws a meaningful error for an unsupported extension' {
        { Get-TestResultFile -Path (Join-Path $FixturesPath 'unsupported.txt') } |
            Should -Throw '*unsupported.txt*Unsupported*'
    }
}

Describe 'Merge-TestResults' {
    BeforeAll {
        $files = @(
            'junit-ubuntu-node18.xml',
            'junit-windows-node18.xml',
            'json-ubuntu-node20.json',
            'json-macos-node20.json'
        ) | ForEach-Object { Get-TestResultFile -Path (Join-Path $MatrixFixturesPath $_) }

        $aggregate = Merge-TestResults -Results $files
    }

    It 'Sums total tests across all files' {
        $aggregate.Summary.Total | Should -Be 18
    }

    It 'Sums passed tests across all files' {
        $aggregate.Summary.Passed | Should -Be 12
    }

    It 'Sums failed tests across all files' {
        $aggregate.Summary.Failed | Should -Be 2
    }

    It 'Sums skipped tests across all files' {
        $aggregate.Summary.Skipped | Should -Be 4
    }

    It 'Sums total duration across all files' {
        $aggregate.Summary.Duration | Should -Be 3.73
    }

    It 'Retains the per-file breakdown' {
        $aggregate.Files.Count | Should -Be 4
        ($aggregate.Files | Where-Object SourceFile -eq 'junit-ubuntu-node18.xml').Summary.Failed | Should -Be 1
    }
}

Describe 'Find-FlakyTests' {
    BeforeAll {
        $files = @(
            'junit-ubuntu-node18.xml',
            'junit-windows-node18.xml',
            'json-ubuntu-node20.json',
            'json-macos-node20.json'
        ) | ForEach-Object { Get-TestResultFile -Path (Join-Path $MatrixFixturesPath $_) }

        $flaky = Find-FlakyTests -Results $files
    }

    It 'Finds exactly two flaky tests' {
        $flaky.Count | Should -Be 2
    }

    It 'Identifies the JUnit test that flipped from failed to passed' {
        $test = $flaky | Where-Object Name -eq 'rate_limit_blocks_after_5_attempts'
        $test | Should -Not -BeNullOrEmpty
        $test.SuiteName | Should -Be 'auth-service'
        $test.PassedIn | Should -Contain 'junit-windows-node18.xml'
        $test.FailedIn | Should -Contain 'junit-ubuntu-node18.xml'
    }

    It 'Identifies the JSON test that flipped from failed to passed' {
        $test = $flaky | Where-Object Name -eq 'refund_processes'
        $test | Should -Not -BeNullOrEmpty
        $test.SuiteName | Should -Be 'payments-service'
        $test.PassedIn | Should -Contain 'json-macos-node20.json'
        $test.FailedIn | Should -Contain 'json-ubuntu-node20.json'
    }

    It 'Does not flag consistently passing tests as flaky' {
        $flaky | Where-Object Name -eq 'login_succeeds' | Should -BeNullOrEmpty
    }

    It 'Does not flag a test that is only skipped and never passed/failed' {
        $flaky | Where-Object Name -eq 'webhook_retries_on_failure' | Should -BeNullOrEmpty
    }

    It 'Returns an empty collection when there is nothing flaky' {
        $single = @(Get-TestResultFile -Path (Join-Path $MatrixFixturesPath 'junit-ubuntu-node18.xml'))
        @(Find-FlakyTests -Results $single).Count | Should -Be 0
    }
}

Describe 'New-TestResultsMarkdownSummary' {
    BeforeAll {
        $files = @(
            'junit-ubuntu-node18.xml',
            'junit-windows-node18.xml',
            'json-ubuntu-node20.json',
            'json-macos-node20.json'
        ) | ForEach-Object { Get-TestResultFile -Path (Join-Path $MatrixFixturesPath $_) }

        $aggregate = Merge-TestResults -Results $files
        $flaky = Find-FlakyTests -Results $files
        $markdown = New-TestResultsMarkdownSummary -Aggregate $aggregate -FlakyTests $flaky
    }

    It 'Includes a top-level heading' {
        $markdown | Should -Match '(?m)^## Test Results Summary'
    }

    It 'Includes the grand totals' {
        $markdown | Should -Match '\| Total \| 18 \|'
        $markdown | Should -Match '\| Passed \| 12 \|'
        $markdown | Should -Match '\| Failed \| 2 \|'
        $markdown | Should -Match '\| Skipped \| 4 \|'
        $markdown | Should -Match '\| Duration \(s\) \| 3\.73 \|'
    }

    It 'Includes a per-file breakdown row for every input file' {
        $markdown | Should -Match 'junit-ubuntu-node18\.xml'
        $markdown | Should -Match 'junit-windows-node18\.xml'
        $markdown | Should -Match 'json-ubuntu-node20\.json'
        $markdown | Should -Match 'json-macos-node20\.json'
    }

    It 'Lists both flaky tests by name' {
        $markdown | Should -Match 'rate_limit_blocks_after_5_attempts'
        $markdown | Should -Match 'refund_processes'
    }

    It 'Reports no flaky tests with a friendly message when there are none' {
        $noFlakyMarkdown = New-TestResultsMarkdownSummary -Aggregate $aggregate -FlakyTests @()
        $noFlakyMarkdown | Should -Match 'No flaky tests detected'
    }
}
