#Requires -Version 7.0
<#
.SYNOPSIS
    TestResultsAggregator - parse, aggregate and summarise test results.

.DESCRIPTION
    Parses test result files in JUnit XML and JSON formats, aggregates
    results across multiple files (simulating a CI matrix build), computes
    totals, detects flaky tests (tests that both passed and failed across
    runs) and renders a markdown summary suitable for $GITHUB_STEP_SUMMARY.

    Every parser normalises test cases into a common record shape:

        [pscustomobject]@{
            Suite      # logical suite / classname
            Name       # test case name
            Result     # 'passed' | 'failed' | 'skipped'
            Duration   # seconds, [double]
            SourceFile # file the record came from (one file ~= one matrix run)
        }

    Built test-first with Pester (see tests/).
#>

Set-StrictMode -Version Latest

# Internal helper: build one normalised test record.
function New-TestRecord {
    param(
        [string]$Suite,
        [string]$Name,
        [string]$Result,
        [double]$Duration,
        [string]$SourceFile
    )
    [pscustomobject]@{
        Suite      = $Suite
        Name       = $Name
        Result     = $Result
        Duration   = $Duration
        SourceFile = $SourceFile
    }
}

function ConvertFrom-JUnitXml {
    <#
    .SYNOPSIS
        Parses a JUnit XML report into normalised test records.
    .DESCRIPTION
        Supports both a <testsuites> root wrapping multiple <testsuite>
        elements and a bare <testsuite> root. A <failure> or <error> child
        marks a test failed; a <skipped> child marks it skipped; otherwise
        it passed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "JUnit XML file not found: '$Path'"
    }

    try {
        [xml]$doc = Get-Content -LiteralPath $Path -Raw
    }
    catch {
        throw "Failed to parse JUnit XML in '$Path': $($_.Exception.Message)"
    }

    $fileName = Split-Path -Leaf $Path

    # Normalise to a list of <testsuite> nodes regardless of root element.
    $suites = $doc.SelectNodes('//testsuite')

    foreach ($suite in $suites) {
        foreach ($case in $suite.SelectNodes('testcase')) {
            # Prefer classname for the suite; fall back to the suite's name.
            $suiteName = if ($case.HasAttribute('classname') -and $case.GetAttribute('classname')) {
                $case.GetAttribute('classname')
            } elseif ($suite.HasAttribute('name')) {
                $suite.GetAttribute('name')
            } else {
                '(unnamed suite)'
            }

            $result =
                if ($case.SelectSingleNode('failure') -or $case.SelectSingleNode('error')) { 'failed' }
                elseif ($case.SelectSingleNode('skipped')) { 'skipped' }
                else { 'passed' }

            $duration = 0.0
            if ($case.HasAttribute('time')) {
                # JUnit time attributes are invariant-culture decimals.
                [void][double]::TryParse(
                    $case.GetAttribute('time'),
                    [System.Globalization.NumberStyles]::Float,
                    [System.Globalization.CultureInfo]::InvariantCulture,
                    [ref]$duration)
            }

            New-TestRecord -Suite $suiteName -Name $case.GetAttribute('name') `
                -Result $result -Duration $duration -SourceFile $fileName
        }
    }
}

function ConvertFrom-TestResultJson {
    <#
    .SYNOPSIS
        Parses a JSON test results file into normalised test records.
    .DESCRIPTION
        Expected shape:
            { "tests": [ { "suite", "name", "result", "duration" }, ... ] }
        'result' must be passed|failed|skipped (case-insensitive).
        'suite' and 'duration' are optional.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "JSON results file not found: '$Path'"
    }

    try {
        $doc = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    }
    catch {
        throw "Failed to parse JSON in '$Path': $($_.Exception.Message)"
    }

    if (-not ($doc.PSObject.Properties.Name -contains 'tests') -or $null -eq $doc.tests) {
        throw "JSON file '$Path' does not contain a 'tests' array"
    }

    $fileName = Split-Path -Leaf $Path
    $validResults = @('passed', 'failed', 'skipped')

    foreach ($test in @($doc.tests)) {
        $result = [string]$test.result
        if ($result.ToLowerInvariant() -notin $validResults) {
            throw "Test '$($test.name)' in '$Path' has an invalid result '$result' (expected: $($validResults -join ', '))"
        }

        $suite = if ($test.PSObject.Properties.Name -contains 'suite' -and $test.suite) {
            [string]$test.suite
        } else {
            '(unnamed suite)'
        }

        $duration = 0.0
        if ($test.PSObject.Properties.Name -contains 'duration' -and $null -ne $test.duration) {
            $duration = [double]$test.duration
        }

        New-TestRecord -Suite $suite -Name ([string]$test.name) `
            -Result $result.ToLowerInvariant() -Duration $duration -SourceFile $fileName
    }
}

function Import-TestResultFile {
    <#
    .SYNOPSIS
        Parses one test result file, choosing the parser by file extension.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    switch ([System.IO.Path]::GetExtension($Path).ToLowerInvariant()) {
        '.xml'  { ConvertFrom-JUnitXml -Path $Path }
        '.json' { ConvertFrom-TestResultJson -Path $Path }
        default { throw "Unsupported test result format for '$Path' (expected .xml or .json)" }
    }
}

function Get-AggregatedResults {
    <#
    .SYNOPSIS
        Aggregates normalised test records from multiple files/runs.
    .DESCRIPTION
        Computes totals (passed/failed/skipped/duration), detects flaky
        tests -- tests (keyed by Suite + Name) that passed in at least one
        run and failed in at least one other -- and collects the distinct
        list of failed tests.
    #>
    [CmdletBinding()]
    param(
        # Allow empty: aggregating zero results is valid (all-skipped runs etc.).
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Results
    )

    $passed  = @($Results | Where-Object Result -eq 'passed')
    $failed  = @($Results | Where-Object Result -eq 'failed')
    $skipped = @($Results | Where-Object Result -eq 'skipped')

    $duration = 0.0
    foreach ($r in $Results) { $duration += $r.Duration }

    # Group by test identity across runs to spot flaky tests.
    $flaky = @(
        $Results |
            Group-Object -Property Suite, Name |
            ForEach-Object {
                $passCount = @($_.Group | Where-Object Result -eq 'passed').Count
                $failCount = @($_.Group | Where-Object Result -eq 'failed').Count
                if ($passCount -gt 0 -and $failCount -gt 0) {
                    [pscustomobject]@{
                        Suite     = $_.Group[0].Suite
                        Name      = $_.Group[0].Name
                        PassCount = $passCount
                        FailCount = $failCount
                    }
                }
            }
    )

    # Distinct failed tests (a test failing in every run appears once).
    $failedDistinct = @(
        $failed |
            Group-Object -Property Suite, Name |
            ForEach-Object {
                [pscustomobject]@{
                    Suite     = $_.Group[0].Suite
                    Name      = $_.Group[0].Name
                    FailCount = $_.Count
                    Runs      = @($_.Group.SourceFile)
                }
            }
    )

    [pscustomobject]@{
        Total       = $Results.Count
        Passed      = $passed.Count
        Failed      = $failed.Count
        Skipped     = $skipped.Count
        Duration    = $duration
        FlakyTests  = $flaky
        FailedTests = $failedDistinct
    }
}

function New-MarkdownSummary {
    <#
    .SYNOPSIS
        Renders an aggregate result as GitHub-flavoured markdown.
    .DESCRIPTION
        Produces a summary suitable for appending to $GITHUB_STEP_SUMMARY:
        totals table, flaky-test table, failed-test table and an overall
        PASSING/FAILING status line.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Aggregate,

        # Number of result files aggregated (matrix runs), for context.
        [int]$FileCount = 0
    )

    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $durationText = [string]::Format($inv, '{0:0.00}s', $Aggregate.Duration)

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('# 🧪 Test Results Summary')
    $lines.Add('')
    if ($FileCount -gt 0) {
        $lines.Add("Aggregated from **$FileCount** result file(s) (matrix runs).")
        $lines.Add('')
    }
    $lines.Add('| Metric | Value |')
    $lines.Add('| ------ | ----- |')
    $lines.Add("| Total tests | $($Aggregate.Total) |")
    $lines.Add("| Passed | $($Aggregate.Passed) |")
    $lines.Add("| Failed | $($Aggregate.Failed) |")
    $lines.Add("| Skipped | $($Aggregate.Skipped) |")
    $lines.Add("| Duration | $durationText |")
    $lines.Add('')

    if ($Aggregate.FlakyTests.Count -gt 0) {
        $lines.Add("## ⚠️ Flaky Tests ($($Aggregate.FlakyTests.Count))")
        $lines.Add('')
        $lines.Add('Passed in some runs but failed in others:')
        $lines.Add('')
        $lines.Add('| Suite | Test | Passed | Failed |')
        $lines.Add('| ----- | ---- | ------ | ------ |')
        foreach ($t in $Aggregate.FlakyTests) {
            $lines.Add("| $($t.Suite) | $($t.Name) | $($t.PassCount) | $($t.FailCount) |")
        }
        $lines.Add('')
    }
    else {
        $lines.Add('No flaky tests detected. 🎉')
        $lines.Add('')
    }

    if ($Aggregate.FailedTests.Count -gt 0) {
        $lines.Add("## ❌ Failed Tests ($($Aggregate.FailedTests.Count))")
        $lines.Add('')
        $lines.Add('| Suite | Test | Failures | Runs |')
        $lines.Add('| ----- | ---- | -------- | ---- |')
        foreach ($t in $Aggregate.FailedTests) {
            $lines.Add("| $($t.Suite) | $($t.Name) | $($t.FailCount) | $($t.Runs -join ', ') |")
        }
        $lines.Add('')
    }

    $status = if ($Aggregate.Failed -gt 0) { '❌ FAILING' } else { '✅ PASSING' }
    $lines.Add("**Overall status:** $status")

    ($lines -join [Environment]::NewLine)
}

Export-ModuleMember -Function ConvertFrom-JUnitXml, ConvertFrom-TestResultJson,
    Import-TestResultFile, Get-AggregatedResults, New-MarkdownSummary
