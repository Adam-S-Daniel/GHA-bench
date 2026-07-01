# Test Results Aggregator
#
# Parses JUnit XML and JSON test result files, aggregates them across
# multiple runs (e.g. matrix build legs), computes totals, detects flaky
# tests (tests whose status differs across runs), and renders a markdown
# summary suitable for $GITHUB_STEP_SUMMARY.

function Get-JUnitTestResults {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $RunName
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "JUnit results file not found: $Path"
    }

    [xml]$xml = Get-Content -LiteralPath $Path -Raw

    $suite = $xml.testsuite
    if (-not $suite) {
        throw "Invalid JUnit XML (missing <testsuite>): $Path"
    }

    $results = @()
    foreach ($case in $suite.testcase) {
        $status = 'Passed'
        if ($case.failure) { $status = 'Failed' }
        elseif ($case.PSObject.Properties['skipped']) { $status = 'Skipped' }

        $results += [PSCustomObject]@{
            Name      = $case.name
            ClassName = $case.classname
            Status    = $status
            Duration  = [double]$case.time
            RunName   = $RunName
        }
    }

    return $results
}

function Get-JsonTestResults {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $RunName
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "JSON results file not found: $Path"
    }

    $data = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json

    if (-not $data.tests) {
        throw "Invalid JSON test results (missing 'tests' array): $Path"
    }

    $results = @()
    foreach ($t in $data.tests) {
        $status = switch ($t.status.ToLowerInvariant()) {
            'passed'  { 'Passed' }
            'failed'  { 'Failed' }
            'skipped' { 'Skipped' }
            default   { throw "Unknown test status '$($t.status)' for test '$($t.name)' in $Path" }
        }

        $results += [PSCustomObject]@{
            Name      = $t.name
            ClassName = $t.classname
            Status    = $status
            Duration  = [double]$t.duration
            RunName   = $RunName
        }
    }

    return $results
}

function Merge-TestResults {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [array] $Results
    )

    $grouped = $Results | Group-Object -Property ClassName, Name

    $tests = @()
    foreach ($group in $grouped) {
        $statuses = @($group.Group.Status | Select-Object -Unique)
        $isFlaky = $statuses.Count -gt 1

        $tests += [PSCustomObject]@{
            ClassName   = $group.Group[0].ClassName
            Name        = $group.Group[0].Name
            IsFlaky     = $isFlaky
            Runs        = $group.Group
            FinalStatus = if ($isFlaky) { 'Flaky' } else { $statuses[0] }
        }
    }

    $totalPassed  = ($Results | Where-Object { $_.Status -eq 'Passed' }).Count
    $totalFailed  = ($Results | Where-Object { $_.Status -eq 'Failed' }).Count
    $totalSkipped = ($Results | Where-Object { $_.Status -eq 'Skipped' }).Count
    $totalDuration = ($Results | Measure-Object -Property Duration -Sum).Sum

    return [PSCustomObject]@{
        Tests         = $tests
        TotalPassed   = $totalPassed
        TotalFailed   = $totalFailed
        TotalSkipped  = $totalSkipped
        TotalDuration = [math]::Round($totalDuration, 3)
        FlakyTests    = $tests | Where-Object { $_.IsFlaky }
        RunNames      = ($Results.RunName | Select-Object -Unique)
    }
}

function New-MarkdownSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Aggregated
    )

    $lines = @()
    $lines += '# Test Results Summary'
    $lines += ''
    $lines += "Runs: $($Aggregated.RunNames -join ', ')"
    $lines += ''
    $lines += '| Passed | Failed | Skipped | Duration (s) |'
    $lines += '|--------|--------|---------|--------------|'
    $lines += "| $($Aggregated.TotalPassed) | $($Aggregated.TotalFailed) | $($Aggregated.TotalSkipped) | $($Aggregated.TotalDuration) |"
    $lines += ''

    if ($Aggregated.FlakyTests.Count -gt 0) {
        $lines += '## :warning: Flaky Tests'
        $lines += ''
        $lines += '| Class | Test | Statuses by Run |'
        $lines += '|-------|------|------------------|'
        foreach ($t in $Aggregated.FlakyTests) {
            $statusByRun = ($t.Runs | ForEach-Object { "$($_.RunName)=$($_.Status)" }) -join ', '
            $lines += "| $($t.ClassName) | $($t.Name) | $statusByRun |"
        }
        $lines += ''
    } else {
        $lines += 'No flaky tests detected.'
        $lines += ''
    }

    $failedTests = $Aggregated.Tests | Where-Object { $_.FinalStatus -eq 'Failed' }
    if ($failedTests.Count -gt 0) {
        $lines += '## :x: Failed Tests'
        $lines += ''
        foreach ($t in $failedTests) {
            $lines += "- $($t.ClassName).$($t.Name)"
        }
        $lines += ''
    }

    return ($lines -join "`n")
}

Export-ModuleMember -Function Get-JUnitTestResults, Get-JsonTestResults, Merge-TestResults, New-MarkdownSummary
