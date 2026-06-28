# TestResultsAggregator.psm1
#
# Parses test result files (JUnit XML and JSON), aggregates them across many
# files (e.g. a CI matrix build), computes totals, identifies flaky tests, and
# renders a Markdown summary for a GitHub Actions job summary.
#
# Every public function emits/consumes a common "normalized test result" shape:
#
#   [PSCustomObject]@{
#       Name     = <string>   # the individual test/case name
#       Suite    = <string>   # the suite / classname it belongs to
#       Status   = <string>   # one of 'Passed', 'Failed', 'Skipped'
#       Duration = <double>   # execution time in seconds
#   }
#
# Keeping a single normalized shape lets us mix formats freely when aggregating.

Set-StrictMode -Version Latest

function ConvertFrom-JUnitXml {
    <#
    .SYNOPSIS
        Parse JUnit-style XML into normalized test result objects.
    .DESCRIPTION
        Accepts the XML as a string. A <testcase> is considered Failed if it
        contains a <failure> or <error> child, Skipped if it contains a
        <skipped> child, and Passed otherwise.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Xml
    )

    # Fail loudly with a meaningful message rather than emitting a raw parser error.
    try {
        [xml] $doc = $Xml
    }
    catch {
        throw "Failed to parse JUnit XML: $($_.Exception.Message)"
    }

    # A document may be <testsuites> wrapping many <testsuite>, or a single
    # top-level <testsuite>. SelectNodes handles both by searching anywhere.
    $cases = $doc.SelectNodes('//testcase')

    foreach ($case in $cases) {
        $status = 'Passed'
        if ($case.SelectSingleNode('failure') -or $case.SelectSingleNode('error')) {
            $status = 'Failed'
        }
        elseif ($case.SelectSingleNode('skipped')) {
            $status = 'Skipped'
        }

        # classname is the conventional JUnit attribute for the owning suite.
        $suite = $case.GetAttribute('classname')
        if ([string]::IsNullOrEmpty($suite)) {
            # Fall back to the parent <testsuite>'s name attribute.
            $suite = $case.ParentNode.GetAttribute('name')
        }

        $time = 0.0
        $rawTime = $case.GetAttribute('time')
        if (-not [string]::IsNullOrEmpty($rawTime)) {
            # Always parse with invariant culture so "0.50" is read consistently.
            [double]::TryParse($rawTime, [System.Globalization.NumberStyles]::Float,
                [System.Globalization.CultureInfo]::InvariantCulture, [ref] $time) | Out-Null
        }

        [PSCustomObject]@{
            Name     = $case.GetAttribute('name')
            Suite    = $suite
            Status   = $status
            Duration = $time
        }
    }
}

function ConvertTo-NormalizedStatus {
    <#
    .SYNOPSIS
        Map an arbitrary status string onto Passed/Failed/Skipped.
    .DESCRIPTION
        Different tools spell statuses differently (pass/passed/ok,
        fail/failed/error, skip/skipped/ignored/disabled). This collapses the
        common spellings to our three canonical values.
    #>
    [CmdletBinding()]
    param([string] $Status)

    switch -Regex ($Status.Trim().ToLowerInvariant()) {
        '^(passed|pass|ok|success|succeeded)$' { 'Passed';  break }
        '^(failed|fail|error|broken)$'         { 'Failed';  break }
        '^(skipped|skip|ignored|disabled|pending|not_?run)$' { 'Skipped'; break }
        default { throw "Unrecognized test status: '$Status'" }
    }
}

function ConvertFrom-TestResultJson {
    <#
    .SYNOPSIS
        Parse a JSON test report into normalized test result objects.
    .DESCRIPTION
        Expects a document with a top-level "tests" array, each element having
        name, suite, status and duration fields. Status spellings are
        normalized via ConvertTo-NormalizedStatus.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Json
    )

    try {
        $doc = $Json | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Failed to parse test result JSON: $($_.Exception.Message)"
    }

    if ($null -eq $doc.PSObject.Properties['tests']) {
        throw "Failed to parse test result JSON: missing top-level 'tests' array."
    }

    foreach ($t in $doc.tests) {
        $duration = 0.0
        if ($null -ne $t.PSObject.Properties['duration'] -and $null -ne $t.duration) {
            $duration = [double] $t.duration
        }

        [PSCustomObject]@{
            Name     = [string] $t.name
            Suite    = [string] $t.suite
            Status   = ConvertTo-NormalizedStatus -Status ([string] $t.status)
            Duration = $duration
        }
    }
}

function Import-TestResultFile {
    <#
    .SYNOPSIS
        Read a single test result file and return normalized results.
    .DESCRIPTION
        Dispatches to the right parser based on file extension (.xml -> JUnit,
        .json -> JSON). Each result is tagged with a Source property naming the
        file it came from, which is useful when aggregating a matrix of runs.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Test result file not found: '$Path'"
    }

    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    $content   = Get-Content -LiteralPath $Path -Raw
    $fileName  = Split-Path -Path $Path -Leaf

    $results = switch ($extension) {
        '.xml'  { ConvertFrom-JUnitXml      -Xml  $content }
        '.json' { ConvertFrom-TestResultJson -Json $content }
        default {
            throw "Unsupported test result file type '$extension' for file '$fileName'. Expected .xml or .json."
        }
    }

    # Tag the originating file so downstream reporting/flaky-detection can refer
    # back to which run produced each result.
    foreach ($r in $results) {
        $r | Add-Member -NotePropertyName Source -NotePropertyValue $fileName -Force
        $r
    }
}

function Import-TestResultDirectory {
    <#
    .SYNOPSIS
        Read every supported test result file in a directory into one set.
    .DESCRIPTION
        Globs *.xml and *.json (sorted for deterministic ordering) and returns
        the combined, normalized results. Throws if the directory contains no
        recognized result files.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Test result directory not found: '$Path'"
    }

    $files = Get-ChildItem -LiteralPath $Path -File |
        Where-Object { $_.Extension -in '.xml', '.json' } |
        Sort-Object Name

    if (-not $files) {
        throw "No test result files (*.xml, *.json) found in '$Path'."
    }

    foreach ($file in $files) {
        Import-TestResultFile -Path $file.FullName
    }
}

function Measure-TestResults {
    <#
    .SYNOPSIS
        Aggregate totals across a set of normalized test results.
    .DESCRIPTION
        Returns an object with Passed/Failed/Skipped/Total counts and the summed
        Duration (seconds). Safe on an empty input set (all zeros).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Results
    )

    $passed = 0; $failed = 0; $skipped = 0; $duration = 0.0
    foreach ($r in $Results) {
        switch ($r.Status) {
            'Passed'  { $passed++ }
            'Failed'  { $failed++ }
            'Skipped' { $skipped++ }
        }
        $duration += [double] $r.Duration
    }

    [PSCustomObject]@{
        Passed   = $passed
        Failed   = $failed
        Skipped  = $skipped
        Total    = $passed + $failed + $skipped
        Duration = $duration
    }
}

function Find-FlakyTest {
    <#
    .SYNOPSIS
        Identify flaky tests across multiple runs.
    .DESCRIPTION
        A test is "flaky" when, grouped by Suite+Name across all runs, it has at
        least one Passed result AND at least one Failed result. Returns one
        object per flaky test with its pass/fail counts.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Results
    )

    # Group by the (Suite, Name) identity so the same test name in different
    # suites is tracked independently.
    $groups = $Results | Group-Object -Property { "$($_.Suite)`u{241F}$($_.Name)" }

    foreach ($g in $groups) {
        $passed = @($g.Group | Where-Object Status -eq 'Passed').Count
        $failed = @($g.Group | Where-Object Status -eq 'Failed').Count

        if ($passed -gt 0 -and $failed -gt 0) {
            $first = $g.Group[0]
            [PSCustomObject]@{
                Suite       = $first.Suite
                Name        = $first.Name
                PassedCount = $passed
                FailedCount = $failed
            }
        }
    }
}

function New-MarkdownSummary {
    <#
    .SYNOPSIS
        Render a Markdown summary of aggregated test results.
    .DESCRIPTION
        Produces a GitHub-flavored Markdown report with a totals table and a
        flaky-tests table (or an explicit "no flaky tests" note). Suitable for
        writing straight to $GITHUB_STEP_SUMMARY.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Results
    )

    $totals = Measure-TestResults -Results $Results
    $flaky  = @(Find-FlakyTest -Results $Results)

    # Format the summed duration with two decimals using invariant culture so
    # the output is stable regardless of the runner's locale (e.g. never "3,00").
    $durationText = ([double] $totals.Duration).ToString('0.00', [System.Globalization.CultureInfo]::InvariantCulture) + 's'

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('# Test Results Summary')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('| Metric | Count |')
    [void]$sb.AppendLine('| --- | --- |')
    [void]$sb.AppendLine("| Passed | $($totals.Passed) |")
    [void]$sb.AppendLine("| Failed | $($totals.Failed) |")
    [void]$sb.AppendLine("| Skipped | $($totals.Skipped) |")
    [void]$sb.AppendLine("| Total | $($totals.Total) |")
    [void]$sb.AppendLine("| Duration | $durationText |")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('## Flaky Tests')
    [void]$sb.AppendLine()

    if ($flaky.Count -gt 0) {
        [void]$sb.AppendLine('The following tests passed in some runs and failed in others:')
        [void]$sb.AppendLine()
        [void]$sb.AppendLine('| Suite | Test | Passed | Failed |')
        [void]$sb.AppendLine('| --- | --- | --- | --- |')
        foreach ($f in ($flaky | Sort-Object Suite, Name)) {
            [void]$sb.AppendLine("| $($f.Suite) | $($f.Name) | $($f.PassedCount) | $($f.FailedCount) |")
        }
    }
    else {
        [void]$sb.AppendLine('No flaky tests detected.')
    }

    $sb.ToString()
}

Export-ModuleMember -Function ConvertFrom-JUnitXml, ConvertFrom-TestResultJson,
    ConvertTo-NormalizedStatus, Import-TestResultFile, Import-TestResultDirectory,
    Measure-TestResults, Find-FlakyTest, New-MarkdownSummary
