# Test Results Aggregator
# Parses JUnit XML and JSON test result files, aggregates them across
# multiple runs (e.g. a GitHub Actions matrix build), computes totals,
# detects flaky tests, and renders a Markdown summary for GITHUB_STEP_SUMMARY.

function Parse-JUnitXmlResult {
    <#
        .SYNOPSIS
        Parses a JUnit-style XML test result file into a normalized run object.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$RunName
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Test result file not found: $Path"
    }

    try {
        [xml]$xml = Get-Content -LiteralPath $Path -Raw
    } catch {
        throw "Failed to parse JUnit XML file '$Path': $($_.Exception.Message)"
    }

    $suite = $xml.testsuite
    if (-not $suite) {
        throw "File '$Path' does not contain a <testsuite> root element"
    }

    $tests = foreach ($case in $suite.testcase) {
        $status = 'passed'
        $failureMessage = $null

        if ($case.failure) {
            $status = 'failed'
            $failureMessage = $case.failure.message
        } elseif ($case.error) {
            $status = 'failed'
            $failureMessage = $case.error.message
        } elseif ($case.PSObject.Properties.Match('skipped').Count -gt 0 -and $null -ne $case.skipped) {
            $status = 'skipped'
        }

        [PSCustomObject]@{
            Name           = $case.name
            ClassName      = $case.classname
            Status         = $status
            Duration       = [double]$case.time
            FailureMessage = $failureMessage
        }
    }

    [PSCustomObject]@{
        RunName   = $RunName
        SuiteName = $suite.name
        Tests     = @($tests)
    }
}

function Parse-JsonResult {
    <#
        .SYNOPSIS
        Parses a JSON test result file into a normalized run object.

        .DESCRIPTION
        Expected schema:
        {
          "suiteName": "...",
          "tests": [
            { "name": "...", "classname": "...", "status": "passed|failed|skipped", "duration": 0.1, "failureMessage": "..." }
          ]
        }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$RunName
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Test result file not found: $Path"
    }

    try {
        $data = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Failed to parse JSON file '$Path': $($_.Exception.Message)"
    }

    if (-not $data.tests) {
        throw "File '$Path' does not contain a 'tests' array"
    }

    $tests = foreach ($case in $data.tests) {
        [PSCustomObject]@{
            Name           = $case.name
            ClassName      = $case.classname
            Status         = $case.status
            Duration       = [double]$case.duration
            FailureMessage = $case.failureMessage
        }
    }

    [PSCustomObject]@{
        RunName   = $RunName
        SuiteName = $data.suiteName
        Tests     = @($tests)
    }
}

function Merge-TestResults {
    <#
        .SYNOPSIS
        Aggregates totals (passed/failed/skipped/duration) across multiple parsed runs.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Runs
    )

    $allTests = $Runs | ForEach-Object { $_.Tests }

    [PSCustomObject]@{
        Runs       = @($Runs)
        TotalTests = @($allTests).Count
        Passed     = @($allTests | Where-Object { $_.Status -eq 'passed' }).Count
        Failed     = @($allTests | Where-Object { $_.Status -eq 'failed' }).Count
        Skipped    = @($allTests | Where-Object { $_.Status -eq 'skipped' }).Count
        Duration   = ($allTests | Measure-Object -Property Duration -Sum).Sum
    }
}

function Find-FlakyTests {
    <#
        .SYNOPSIS
        Identifies tests that passed in at least one run and failed in at least one other run.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Runs
    )

    $byName = @{}
    foreach ($run in $Runs) {
        foreach ($test in $run.Tests) {
            if (-not $byName.ContainsKey($test.Name)) {
                $byName[$test.Name] = [PSCustomObject]@{
                    Name     = $test.Name
                    PassedIn = [System.Collections.Generic.List[string]]::new()
                    FailedIn = [System.Collections.Generic.List[string]]::new()
                }
            }
            if ($test.Status -eq 'passed') {
                $byName[$test.Name].PassedIn.Add($run.RunName)
            } elseif ($test.Status -eq 'failed') {
                $byName[$test.Name].FailedIn.Add($run.RunName)
            }
        }
    }

    @($byName.Values | Where-Object { $_.PassedIn.Count -gt 0 -and $_.FailedIn.Count -gt 0 } | Sort-Object Name)
}

function New-MarkdownSummary {
    <#
        .SYNOPSIS
        Renders an aggregate result and flaky-test list as Markdown suitable
        for a GitHub Actions job summary (GITHUB_STEP_SUMMARY).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Aggregate,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$FlakyTests
    )

    $lines = [System.Collections.Generic.List[string]]::new()

    $lines.Add('# Test Results Summary')
    $lines.Add('')
    $lines.Add('## Totals')
    $lines.Add('')
    $lines.Add('| Metric | Value |')
    $lines.Add('| --- | --- |')
    $lines.Add("| Total | $($Aggregate.TotalTests) |")
    $lines.Add("| Passed | $($Aggregate.Passed) |")
    $lines.Add("| Failed | $($Aggregate.Failed) |")
    $lines.Add("| Skipped | $($Aggregate.Skipped) |")
    $lines.Add("| Duration (s) | $([Math]::Round($Aggregate.Duration, 2)) |")
    $lines.Add('')

    $lines.Add('## Runs')
    $lines.Add('')
    $lines.Add('| Run | Total | Passed | Failed | Skipped | Duration (s) |')
    $lines.Add('| --- | --- | --- | --- | --- | --- |')
    foreach ($run in $Aggregate.Runs) {
        $total = $run.Tests.Count
        $passed = @($run.Tests | Where-Object { $_.Status -eq 'passed' }).Count
        $failed = @($run.Tests | Where-Object { $_.Status -eq 'failed' }).Count
        $skipped = @($run.Tests | Where-Object { $_.Status -eq 'skipped' }).Count
        $duration = [Math]::Round(($run.Tests | Measure-Object -Property Duration -Sum).Sum, 2)
        $lines.Add("| $($run.RunName) | $total | $passed | $failed | $skipped | $duration |")
    }
    $lines.Add('')

    $lines.Add('## Flaky Tests')
    $lines.Add('')
    if ($FlakyTests.Count -eq 0) {
        $lines.Add('No flaky tests detected.')
    } else {
        $lines.Add('| Test | Passed In | Failed In |')
        $lines.Add('| --- | --- | --- |')
        foreach ($flaky in $FlakyTests) {
            $passedIn = ($flaky.PassedIn -join ', ')
            $failedIn = ($flaky.FailedIn -join ', ')
            $lines.Add("| $($flaky.Name) | $passedIn | $failedIn |")
        }
    }
    $lines.Add('')

    return ($lines -join "`n")
}

function Invoke-TestResultsAggregation {
    <#
        .SYNOPSIS
        Discovers test result files (.xml = JUnit, .json) in a directory,
        aggregates them across runs, detects flaky tests, writes a Markdown
        summary to -OutputPath, and returns the aggregate + flaky test data.

        .DESCRIPTION
        Each file's base name (without extension) is used as its run name,
        mirroring how a matrix build might name artifacts like
        "junit-run1-ubuntu.xml" or "results-run3-macos.json".
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$InputDirectory,
        [Parameter(Mandatory)][string]$OutputPath,
        [string[]]$Include
    )

    if (-not (Test-Path -LiteralPath $InputDirectory)) {
        throw "Input directory not found: $InputDirectory"
    }

    if ($Include) {
        $files = $Include | ForEach-Object { Join-Path $InputDirectory $_ } | Sort-Object
    } else {
        $files = Get-ChildItem -LiteralPath $InputDirectory -File |
            Select-Object -ExpandProperty FullName |
            Sort-Object
    }

    if (-not $files -or @($files).Count -eq 0) {
        throw "No test result files (.xml or .json) found in: $InputDirectory"
    }

    $runs = foreach ($file in $files) {
        $runName = [System.IO.Path]::GetFileNameWithoutExtension($file)
        $extension = [System.IO.Path]::GetExtension($file).ToLowerInvariant()

        switch ($extension) {
            '.xml' { Parse-JUnitXmlResult -Path $file -RunName $runName }
            '.json' { Parse-JsonResult -Path $file -RunName $runName }
            default { throw "Unsupported test result file extension '$extension' for file: $file" }
        }
    }
    $runs = @($runs)

    $aggregate = Merge-TestResults -Runs $runs
    $flakyTests = Find-FlakyTests -Runs $runs
    $markdown = New-MarkdownSummary -Aggregate $aggregate -FlakyTests $flakyTests

    Set-Content -LiteralPath $OutputPath -Value $markdown -NoNewline

    [PSCustomObject]@{
        Aggregate  = $aggregate
        FlakyTests = $flakyTests
        Markdown   = $markdown
    }
}
