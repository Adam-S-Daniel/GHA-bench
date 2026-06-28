#requires -Modules Pester

# Unit tests for the Test Results Aggregator module.
#
# Written red/green TDD style. These are the SAME tests the GitHub Actions workflow
# runs inside the container (see .github/workflows/test-results-aggregator.yml), so
# "every test case runs through the pipeline". They locate the module + fixtures
# relative to this file ($PSScriptRoot) and therefore pass from any working directory.

BeforeAll {
    $script:ModulePath   = Join-Path $PSScriptRoot '..' 'TestResultsAggregator.psm1'
    $script:UnitFixtures = Join-Path $PSScriptRoot 'fixtures'             # tiny edge-case fixtures
    # Stable copy of the "Case A" matrix build. This lives under tests/ (never swapped)
    # so the assertions stay valid even though the workflow's input dir (root fixtures/)
    # is swapped per act test case by the end-to-end harness.
    $script:MatrixDir    = Join-Path $PSScriptRoot 'fixtures' 'matrix'
    Import-Module $script:ModulePath -Force
}

AfterAll {
    Remove-Module TestResultsAggregator -Force -ErrorAction SilentlyContinue
}

Describe 'ConvertFrom-JUnitXml' {
    BeforeAll {
        $script:res = ConvertFrom-JUnitXml -Path (Join-Path $script:UnitFixtures 'simple-junit.xml')
    }

    It 'parses a bare <testsuite> root into one object per testcase' {
        $script:res.Count | Should -Be 3
    }

    It 'classifies pass / fail / skip correctly' {
        ($script:res | Where-Object Status -eq 'passed').Count  | Should -Be 1
        ($script:res | Where-Object Status -eq 'failed').Count  | Should -Be 1
        ($script:res | Where-Object Status -eq 'skipped').Count | Should -Be 1
    }

    It 'extracts duration from the time attribute (InvariantCulture)' {
        $alpha = $script:res | Where-Object Name -eq 'alpha'
        $alpha.Duration | Should -Be 1.0
    }

    It 'builds a stable TestId of ClassName.Name' {
        ($script:res | Where-Object Name -eq 'beta').TestId | Should -Be 'Sample.beta'
    }

    It 'captures the failure message' {
        ($script:res | Where-Object Name -eq 'beta').Message | Should -Be 'boom'
    }

    It 'also handles the nested <testsuites> root with multiple suites' {
        $r = ConvertFrom-JUnitXml -Path (Join-Path $script:MatrixDir 'run-ubuntu.xml')
        $r.Count | Should -Be 5
        ($r | Where-Object Name -eq 'fetch').Status | Should -Be 'passed'
    }

    It 'throws a meaningful error on a missing file' {
        { ConvertFrom-JUnitXml -Path (Join-Path $script:UnitFixtures 'does-not-exist.xml') } |
            Should -Throw '*not found*'
    }

    It 'throws a file-scoped error on malformed XML' {
        { ConvertFrom-JUnitXml -Path (Join-Path $script:UnitFixtures 'malformed.xml') } |
            Should -Throw '*Failed to parse JUnit XML*'
    }
}

Describe 'ConvertFrom-TestResultJson' {
    BeforeAll {
        $script:res = ConvertFrom-TestResultJson -Path (Join-Path $script:UnitFixtures 'simple.json')
    }

    It 'parses the tests array' {
        $script:res.Count | Should -Be 3
    }

    It 'normalizes alternate status spellings (pass/fail/error)' {
        ($script:res | Where-Object Name -eq 'alpha').Status | Should -Be 'passed'
        ($script:res | Where-Object Name -eq 'beta').Status  | Should -Be 'failed'
        ($script:res | Where-Object Name -eq 'delta').Status | Should -Be 'failed'  # 'error' -> failed
    }

    It 'reads duration values' {
        ($script:res | Where-Object Name -eq 'alpha').Duration | Should -Be 0.5
    }

    It 'throws a file-scoped error on malformed JSON' {
        { ConvertFrom-TestResultJson -Path (Join-Path $script:UnitFixtures 'malformed.json') } |
            Should -Throw '*Failed to parse JSON*'
    }

    It 'throws on an unrecognized status value' {
        $content = '{ "tests": [ { "name": "x", "status": "weird" } ] }'
        { ConvertFrom-TestResultJson -Content $content } | Should -Throw '*Unrecognized test status*'
    }
}

Describe 'Import-TestResultFile (dispatch)' {
    It 'routes .xml to the JUnit parser' {
        (Import-TestResultFile -Path (Join-Path $script:UnitFixtures 'simple-junit.xml')).Count | Should -Be 3
    }

    It 'routes .json to the JSON parser' {
        (Import-TestResultFile -Path (Join-Path $script:UnitFixtures 'simple.json')).Count | Should -Be 3
    }

    It 'throws on an unsupported extension' {
        $tmp = New-TemporaryFile
        Rename-Item -Path $tmp.FullName -NewName ($tmp.Name + '.txt')
        $txt = "$($tmp.FullName).txt"
        try {
            { Import-TestResultFile -Path $txt } | Should -Throw '*Unsupported test result file extension*'
        }
        finally { Remove-Item -LiteralPath $txt -ErrorAction SilentlyContinue }
    }
}

Describe 'Get-TestResultFile (enumeration)' {
    It 'finds all supported files in a directory' {
        (Get-TestResultFile -Path $script:MatrixDir).Count | Should -Be 3
    }

    It 'throws a meaningful error for an empty directory' {
        $empty = Join-Path ([System.IO.Path]::GetTempPath()) ("trf-empty-" + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $empty | Out-Null
        try {
            { Get-TestResultFile -Path $empty } | Should -Throw '*No test result files*'
        }
        finally { Remove-Item -LiteralPath $empty -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Describe 'Get-TestResultSummary (totals + flaky)' {
    BeforeAll {
        # Aggregate the full Case A matrix (ubuntu.xml + windows.xml + macos.json).
        $script:agg = Invoke-TestResultsAggregator -Path $script:MatrixDir
        $script:sum = $script:agg.Summary
    }

    It 'computes exact totals across the matrix' {
        $script:sum.Total   | Should -Be 15
        $script:sum.Passed  | Should -Be 8
        $script:sum.Failed  | Should -Be 4
        $script:sum.Skipped | Should -Be 3
    }

    It 'sums duration across all runs (rounded to 2 dp)' {
        $script:sum.Duration     | Should -Be 2.46
        $script:sum.DurationText | Should -Be '2.46'
    }

    It 'reports the overall verdict as FAILED when any test failed' {
        $script:sum.Overall | Should -Be 'FAILED'
    }

    It 'identifies exactly the flaky test (passed in some runs, failed in others)' {
        $script:sum.FlakyCount | Should -Be 1
        $script:sum.Flaky[0].TestId    | Should -Be 'Net.fetch'
        $script:sum.Flaky[0].PassCount | Should -Be 2
        $script:sum.Flaky[0].FailCount | Should -Be 1
    }

    It 'does NOT flag a consistently-failing test as flaky' {
        ($script:sum.Flaky | Where-Object TestId -eq 'Calc.divide') | Should -BeNullOrEmpty
    }

    It 'counts the number of files aggregated' {
        $script:sum.Files | Should -Be 3
    }
}

Describe 'New-MarkdownSummary (rendering)' {
    BeforeAll {
        $script:md = (Invoke-TestResultsAggregator -Path $script:MatrixDir).Markdown
    }

    It 'renders a heading and a totals table' {
        $script:md | Should -Match '# .*Test Results Summary'
        $script:md | Should -Match '\| .*Passed \| 8 \|'
        $script:md | Should -Match '\| .*Failed \| 4 \|'
        $script:md | Should -Match '\| .*Total \| 15 \|'
    }

    It 'renders the overall verdict' {
        $script:md | Should -Match '\*\*FAILED\*\*'
    }

    It 'lists the flaky test in its own section' {
        $script:md | Should -Match '## .*Flaky Tests'
        $script:md | Should -Match '\| Net\.fetch \| 2 \| 1 \|'
    }

    It 'shows "_None detected._" when there are no flaky tests' {
        $content = '{ "tests": [ { "name": "a", "status": "passed" } ] }'
        $res = ConvertFrom-TestResultJson -Content $content
        $sum = Get-TestResultSummary -Results $res -FileCount 1
        (New-MarkdownSummary -Summary $sum) | Should -Match '_None detected\._'
    }
}

Describe 'Format-MetricsBlock (machine-readable output)' {
    BeforeAll {
        $script:metrics = (Invoke-TestResultsAggregator -Path $script:MatrixDir).MetricsText
    }

    It 'emits exact KEY=VALUE lines used by the CI assertions' {
        $script:metrics | Should -Match 'TOTAL_TESTS=15'
        $script:metrics | Should -Match 'PASSED=8'
        $script:metrics | Should -Match 'FAILED=4'
        $script:metrics | Should -Match 'SKIPPED=3'
        $script:metrics | Should -Match 'DURATION_SECONDS=2.46'
        $script:metrics | Should -Match 'FLAKY_COUNT=1'
        $script:metrics | Should -Match 'FLAKY_TESTS=Net.fetch'
        $script:metrics | Should -Match 'OVERALL=FAILED'
    }
}

Describe 'Invoke-TestResultsAggregator (end-to-end)' {
    It 'aggregates a mixed XML+JSON directory into a complete result object' {
        $agg = Invoke-TestResultsAggregator -Path $script:MatrixDir
        $agg.Files.Count      | Should -Be 3
        $agg.Results.Count    | Should -Be 15
        $agg.Summary.FlakyCount | Should -Be 1
        $agg.Markdown         | Should -Not -BeNullOrEmpty
        $agg.MetricsText      | Should -Match 'OVERALL=FAILED'
    }

    It 'throws a meaningful error when the input path does not exist' {
        { Invoke-TestResultsAggregator -Path (Join-Path $script:UnitFixtures 'nope-dir') } |
            Should -Throw '*not found*'
    }
}
