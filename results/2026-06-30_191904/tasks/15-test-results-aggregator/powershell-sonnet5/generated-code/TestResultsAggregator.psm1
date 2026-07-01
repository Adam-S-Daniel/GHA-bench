#
# TestResultsAggregator.psm1
#
# Parses JUnit XML and JSON test result files, aggregates results across
# multiple files (e.g. the legs of a GitHub Actions matrix build), computes
# totals, detects flaky tests, and renders a Markdown summary suitable for
# $env:GITHUB_STEP_SUMMARY.
#
Set-StrictMode -Version Latest

function ConvertFrom-JUnitXml {
    <#
    .SYNOPSIS
        Parses a JUnit-format XML test result file into a normalized result object.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "JUnit result file '$Path' not found."
    }

    $fileName = Split-Path -Path $Path -Leaf

    try {
        [xml]$xml = Get-Content -LiteralPath $Path -Raw
    } catch {
        throw "Failed to parse JUnit XML file '$fileName': $($_.Exception.Message)"
    }

    $suiteNode = $xml.SelectSingleNode('//testsuite')
    if (-not $suiteNode) {
        throw "JUnit XML file '$fileName' does not contain a <testsuite> element."
    }

    $tests = [System.Collections.Generic.List[object]]::new()

    foreach ($caseNode in $suiteNode.SelectNodes('testcase')) {
        $status = 'Passed'
        $message = $null

        $failureNode = $caseNode.SelectSingleNode('failure')
        $errorNode = $caseNode.SelectSingleNode('error')
        $skippedNode = $caseNode.SelectSingleNode('skipped')

        if ($failureNode -or $errorNode) {
            $status = 'Failed'
            $node = if ($failureNode) { $failureNode } else { $errorNode }
            $message = $node.GetAttribute('message')
        } elseif ($skippedNode) {
            $status = 'Skipped'
        }

        $tests.Add([PSCustomObject]@{
            Name      = $caseNode.GetAttribute('name')
            ClassName = $caseNode.GetAttribute('classname')
            Status    = $status
            Duration  = [double]($caseNode.GetAttribute('time'))
            Message   = $message
        })
    }

    $summary = [PSCustomObject]@{
        Total    = $tests.Count
        Passed   = @($tests | Where-Object Status -eq 'Passed').Count
        Failed   = @($tests | Where-Object Status -eq 'Failed').Count
        Skipped  = @($tests | Where-Object Status -eq 'Skipped').Count
        Duration = [Math]::Round((($tests | Measure-Object -Property Duration -Sum).Sum), 4)
    }

    [PSCustomObject]@{
        SourceFile = $fileName
        SuiteName  = $suiteNode.GetAttribute('name')
        Format     = 'JUnit'
        Tests      = $tests
        Summary    = $summary
    }
}

function ConvertFrom-JsonTestResults {
    <#
    .SYNOPSIS
        Parses a JSON test result file into a normalized result object.

    .DESCRIPTION
        Expects the shape:
        {
          "suiteName": "...",
          "tests": [ { "name": "...", "status": "passed|failed|skipped", "duration": 0.1, "message": "..." } ]
        }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "JSON result file '$Path' not found."
    }

    $fileName = Split-Path -Path $Path -Leaf

    try {
        $raw = Get-Content -LiteralPath $Path -Raw
        $data = $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Failed to parse JSON test result file '$fileName': $($_.Exception.Message)"
    }

    if (-not $data.tests) {
        throw "JSON test result file '$fileName' does not contain a 'tests' array."
    }

    $tests = [System.Collections.Generic.List[object]]::new()

    foreach ($t in $data.tests) {
        $status = switch ($t.status) {
            'passed'  { 'Passed' }
            'failed'  { 'Failed' }
            'skipped' { 'Skipped' }
            default   { throw "JSON test result file '$fileName' has test '$($t.name)' with unrecognized status '$($t.status)'." }
        }

        $tests.Add([PSCustomObject]@{
            Name      = $t.name
            ClassName = $null
            Status    = $status
            Duration  = [double]$t.duration
            Message   = if ($t.PSObject.Properties.Name -contains 'message') { $t.message } else { $null }
        })
    }

    $summary = [PSCustomObject]@{
        Total    = $tests.Count
        Passed   = @($tests | Where-Object Status -eq 'Passed').Count
        Failed   = @($tests | Where-Object Status -eq 'Failed').Count
        Skipped  = @($tests | Where-Object Status -eq 'Skipped').Count
        Duration = [Math]::Round((($tests | Measure-Object -Property Duration -Sum).Sum), 4)
    }

    [PSCustomObject]@{
        SourceFile = $fileName
        SuiteName  = $data.suiteName
        Format     = 'JSON'
        Tests      = $tests
        Summary    = $summary
    }
}

function Get-TestResultFile {
    <#
    .SYNOPSIS
        Parses a single test result file, dispatching to the correct parser
        based on its file extension (.xml -> JUnit, .json -> JSON).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()

    switch ($extension) {
        '.xml'  { return ConvertFrom-JUnitXml -Path $Path }
        '.json' { return ConvertFrom-JsonTestResults -Path $Path }
        default {
            $fileName = Split-Path -Path $Path -Leaf
            throw "'$fileName' has an unsupported test result file format. Supported extensions: .xml, .json"
        }
    }
}

function Merge-TestResults {
    <#
    .SYNOPSIS
        Aggregates a collection of normalized test result objects (as returned
        by Get-TestResultFile) into grand totals, keeping the per-file
        breakdown for reporting.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Results
    )

    if ($Results.Count -eq 0) {
        throw 'Merge-TestResults requires at least one parsed test result.'
    }

    $summary = [PSCustomObject]@{
        Total    = ($Results | Measure-Object -Property { $_.Summary.Total } -Sum).Sum
        Passed   = ($Results | Measure-Object -Property { $_.Summary.Passed } -Sum).Sum
        Failed   = ($Results | Measure-Object -Property { $_.Summary.Failed } -Sum).Sum
        Skipped  = ($Results | Measure-Object -Property { $_.Summary.Skipped } -Sum).Sum
        Duration = [Math]::Round((($Results | Measure-Object -Property { $_.Summary.Duration } -Sum).Sum), 4)
    }

    [PSCustomObject]@{
        Files   = $Results
        Summary = $summary
    }
}

function Find-FlakyTests {
    <#
    .SYNOPSIS
        Identifies tests that passed in at least one file and failed in at
        least one other file, keyed by "<suite>/<test name>" so that a
        matrix build's legs (same suite, different OS/version) are compared
        against each other. Skipped-only results are not considered flaky.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Results
    )

    $byKey = @{}

    foreach ($fileResult in $Results) {
        foreach ($test in $fileResult.Tests) {
            $key = "$($fileResult.SuiteName)/$($test.Name)"

            if (-not $byKey.ContainsKey($key)) {
                $byKey[$key] = [PSCustomObject]@{
                    SuiteName = $fileResult.SuiteName
                    Name      = $test.Name
                    PassedIn  = [System.Collections.Generic.List[string]]::new()
                    FailedIn  = [System.Collections.Generic.List[string]]::new()
                }
            }

            switch ($test.Status) {
                'Passed' { $byKey[$key].PassedIn.Add($fileResult.SourceFile) }
                'Failed' { $byKey[$key].FailedIn.Add($fileResult.SourceFile) }
            }
        }
    }

    @($byKey.Values | Where-Object { $_.PassedIn.Count -gt 0 -and $_.FailedIn.Count -gt 0 })
}

function New-TestResultsMarkdownSummary {
    <#
    .SYNOPSIS
        Renders an aggregate test result plus flaky-test list as Markdown,
        suitable for writing to $env:GITHUB_STEP_SUMMARY.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Aggregate,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$FlakyTests
    )

    $status = if ($Aggregate.Summary.Failed -gt 0) { ':x: Failed' } else { ':white_check_mark: Passed' }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('## Test Results Summary')
    $lines.Add('')
    $lines.Add("**Overall status:** $status")
    $lines.Add('')
    $lines.Add('| Metric | Count |')
    $lines.Add('| --- | --- |')
    $lines.Add("| Total | $($Aggregate.Summary.Total) |")
    $lines.Add("| Passed | $($Aggregate.Summary.Passed) |")
    $lines.Add("| Failed | $($Aggregate.Summary.Failed) |")
    $lines.Add("| Skipped | $($Aggregate.Summary.Skipped) |")
    $lines.Add("| Duration (s) | $($Aggregate.Summary.Duration) |")
    $lines.Add('')
    $lines.Add('### Per-File Breakdown')
    $lines.Add('')
    $lines.Add('| File | Suite | Format | Total | Passed | Failed | Skipped | Duration (s) |')
    $lines.Add('| --- | --- | --- | --- | --- | --- | --- | --- |')
    foreach ($file in $Aggregate.Files) {
        $s = $file.Summary
        $lines.Add("| $($file.SourceFile) | $($file.SuiteName) | $($file.Format) | $($s.Total) | $($s.Passed) | $($s.Failed) | $($s.Skipped) | $($s.Duration) |")
    }
    $lines.Add('')
    $lines.Add('### Flaky Tests')
    $lines.Add('')

    if ($FlakyTests.Count -eq 0) {
        $lines.Add('No flaky tests detected.')
    } else {
        $lines.Add('| Suite | Test | Passed In | Failed In |')
        $lines.Add('| --- | --- | --- | --- |')
        foreach ($flaky in $FlakyTests) {
            $passedIn = ($flaky.PassedIn -join ', ')
            $failedIn = ($flaky.FailedIn -join ', ')
            $lines.Add("| $($flaky.SuiteName) | $($flaky.Name) | $passedIn | $failedIn |")
        }
    }

    $lines -join [Environment]::NewLine
}

Export-ModuleMember -Function ConvertFrom-JUnitXml, ConvertFrom-JsonTestResults, Get-TestResultFile, Merge-TestResults, Find-FlakyTests, New-TestResultsMarkdownSummary
