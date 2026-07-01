#!/usr/bin/env pwsh
<#
    Test Results Aggregator

    Parses test result files in JUnit XML and JSON formats, aggregates results
    across multiple files (simulating matrix build legs), computes totals, flags
    flaky tests (tests that pass in some runs and fail in others), and renders a
    markdown summary suitable for $env:GITHUB_STEP_SUMMARY.

    Can be dot-sourced (to reuse the functions from Pester tests) or invoked
    directly as a CLI entry point.
#>

param(
    # Directory to scan for *.xml / *.json test result files (one per matrix leg).
    [string]$ResultsPath = (Join-Path $PSScriptRoot 'fixtures'),

    # Where to append the rendered markdown summary. Defaults to the GitHub
    # Actions job summary file when running in a workflow.
    [string]$OutputPath = $env:GITHUB_STEP_SUMMARY
)

function Import-JUnitXmlResult {
    <#
        Parses a JUnit-style XML test result file into a flat array of
        PSCustomObjects: { Suite, Name, Status, Duration }.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Test result file not found: '$Path'"
    }

    try {
        [xml]$xml = Get-Content -Raw -LiteralPath $Path
    } catch {
        throw "Failed to parse JUnit XML file '$Path': $($_.Exception.Message)"
    }

    if ($xml.testsuites) {
        $suites = @($xml.testsuites.testsuite)
    } elseif ($xml.testsuite) {
        $suites = @($xml.testsuite)
    } else {
        throw "File '$Path' does not contain a <testsuite> element"
    }

    $cases = @()
    foreach ($suite in $suites) {
        foreach ($testcase in @($suite.testcase)) {
            if (-not $testcase) { continue }

            if ($testcase.failure -or $testcase.error) {
                $status = 'Failed'
            } elseif ($testcase.PSObject.Properties.Name -contains 'skipped') {
                $status = 'Skipped'
            } else {
                $status = 'Passed'
            }

            $cases += [PSCustomObject]@{
                Suite    = $suite.name
                Name     = $testcase.name
                Status   = $status
                Duration = if ($testcase.time) { [double]$testcase.time } else { 0.0 }
            }
        }
    }

    return $cases
}

function Import-JsonTestResult {
    <#
        Parses a JSON test result file (custom schema: { suiteName, tests: [...] })
        into a flat array of PSCustomObjects: { Suite, Name, Status, Duration }.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Test result file not found: '$Path'"
    }

    try {
        $json = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Failed to parse JSON test result file '$Path': $($_.Exception.Message)"
    }

    if (-not $json.tests) {
        throw "File '$Path' does not contain a 'tests' array"
    }

    $cases = @()
    foreach ($test in $json.tests) {
        switch -Regex ($test.status) {
            '^(?i)(passed|pass)$'   { $status = 'Passed'; break }
            '^(?i)(failed|fail)$'   { $status = 'Failed'; break }
            '^(?i)(skipped|skip)$'  { $status = 'Skipped'; break }
            default { throw "Unknown test status '$($test.status)' for test '$($test.name)' in '$Path'" }
        }

        $cases += [PSCustomObject]@{
            Suite    = $json.suiteName
            Name     = $test.name
            Status   = $status
            Duration = if ($test.duration) { [double]$test.duration } else { 0.0 }
        }
    }

    return $cases
}

function Import-TestResultFile {
    <#
        Dispatches a test result file to the correct parser based on its extension.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Test result file not found: '$Path'"
    }

    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    switch ($extension) {
        '.xml'  { return Import-JUnitXmlResult -Path $Path }
        '.json' { return Import-JsonTestResult -Path $Path }
        default { throw "Unsupported test result file format '$extension' (file: '$Path'). Expected .xml or .json." }
    }
}

function Get-AggregatedTestResults {
    <#
        Aggregates test results across multiple files (matrix build legs).
        Each input file is treated as one "run" (identified by its file name)
        for the purpose of flaky-test detection: a test is flaky if it has
        both a Passed and a Failed status across the runs it appeared in.
    #>
    param(
        [AllowEmptyCollection()]
        [string[]]$Path
    )

    if (-not $Path -or $Path.Count -eq 0) {
        throw 'No test result files were provided to aggregate.'
    }

    $allCases = @()
    foreach ($file in $Path) {
        $runId = [System.IO.Path]::GetFileNameWithoutExtension($file)
        foreach ($case in (Import-TestResultFile -Path $file)) {
            $allCases += [PSCustomObject]@{
                RunId    = $runId
                Suite    = $case.Suite
                Name     = $case.Name
                Status   = $case.Status
                Duration = $case.Duration
            }
        }
    }

    $passed   = @($allCases | Where-Object Status -eq 'Passed').Count
    $failed   = @($allCases | Where-Object Status -eq 'Failed').Count
    $skipped  = @($allCases | Where-Object Status -eq 'Skipped').Count
    $duration = ($allCases | Measure-Object -Property Duration -Sum).Sum
    if (-not $duration) { $duration = 0.0 }

    $flakyTests = @()
    foreach ($group in ($allCases | Group-Object -Property Name)) {
        $statuses = $group.Group.Status | Select-Object -Unique
        if (($statuses -contains 'Passed') -and ($statuses -contains 'Failed')) {
            $flakyTests += [PSCustomObject]@{
                Name = $group.Name
                Runs = @($group.Group | ForEach-Object {
                    [PSCustomObject]@{ RunId = $_.RunId; Status = $_.Status }
                })
            }
        }
    }

    return [PSCustomObject]@{
        TotalTests    = $allCases.Count
        TotalPassed   = $passed
        TotalFailed   = $failed
        TotalSkipped  = $skipped
        TotalDuration = [math]::Round($duration, 3)
        TestCases     = $allCases
        FlakyTests    = $flakyTests
    }
}

function New-MarkdownSummary {
    <#
        Renders an aggregated test result object as GitHub-flavored markdown,
        suitable for writing to $env:GITHUB_STEP_SUMMARY.
    #>
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Aggregate
    )

    $lines = @(
        '# Test Results Summary'
        ''
        '| Metric | Count |'
        '|---|---|'
        "| Total | $($Aggregate.TotalTests) |"
        "| Passed | $($Aggregate.TotalPassed) |"
        "| Failed | $($Aggregate.TotalFailed) |"
        "| Skipped | $($Aggregate.TotalSkipped) |"
        "| Duration (s) | $($Aggregate.TotalDuration) |"
        ''
    )

    if ($Aggregate.FlakyTests.Count -gt 0) {
        $lines += '## Flaky Tests'
        $lines += ''
        $lines += '| Test | Run Results |'
        $lines += '|---|---|'
        foreach ($flaky in $Aggregate.FlakyTests) {
            $runResults = ($flaky.Runs | ForEach-Object { "$($_.RunId): $($_.Status)" }) -join ', '
            $lines += "| $($flaky.Name) | $runResults |"
        }
        $lines += ''
    } else {
        $lines += 'No flaky tests detected.'
        $lines += ''
    }

    $overallStatus = if ($Aggregate.TotalFailed -gt 0) { 'FAILURE' } else { 'SUCCESS' }
    $lines += "**Overall Status:** $overallStatus"

    return ($lines -join [Environment]::NewLine)
}

# CLI entry point -- only runs when the script is executed directly, not when
# it's dot-sourced (e.g. by the Pester test suite).
if ($MyInvocation.InvocationName -ne '.') {
    if (-not (Test-Path -LiteralPath $ResultsPath)) {
        throw "Results path not found: '$ResultsPath'"
    }

    $files = Get-ChildItem -LiteralPath $ResultsPath -Include '*.xml', '*.json' -Recurse -File
    if (-not $files -or $files.Count -eq 0) {
        throw "No test result files (*.xml, *.json) found under '$ResultsPath'"
    }

    $aggregate = Get-AggregatedTestResults -Path $files.FullName
    $markdown = New-MarkdownSummary -Aggregate $aggregate

    Write-Host $markdown

    if ($OutputPath) {
        Add-Content -LiteralPath $OutputPath -Value $markdown
    }

    if ($aggregate.TotalFailed -gt 0) {
        exit 1
    }
}
