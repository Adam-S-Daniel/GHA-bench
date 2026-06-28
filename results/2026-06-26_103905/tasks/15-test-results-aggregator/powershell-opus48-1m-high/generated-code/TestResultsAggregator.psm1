# TestResultsAggregator.psm1
#
# A small library for aggregating software test results across multiple result
# files (as produced by a CI matrix build), computing totals, detecting flaky
# tests, and rendering a GitHub-Actions-friendly markdown summary.
#
# Design notes
# ------------
# Every parser normalizes its input into a common "test case record" shape so the
# rest of the pipeline never has to care about the source format:
#
#   [pscustomobject]@{
#       Suite    = <string>   # test suite / class name ('' if unknown)
#       Name     = <string>   # test case name
#       Status   = <string>   # one of 'Passed' | 'Failed' | 'Skipped'
#       Duration = <double>   # seconds
#       File     = <string>   # source file the record came from (set by Import-TestResults)
#   }
#
# Keeping a single normalized shape is what makes aggregation and flaky-test
# detection format-agnostic.

Set-StrictMode -Version Latest

# Canonical status values. We normalize many synonyms onto these three.
$script:StatusPassed  = 'Passed'
$script:StatusFailed  = 'Failed'
$script:StatusSkipped = 'Skipped'

function ConvertTo-NormalizedStatus {
    <#
    .SYNOPSIS
        Maps a variety of status strings used by different test frameworks onto
        the canonical Passed/Failed/Skipped vocabulary.
    #>
    [CmdletBinding()]
    param([string]$Status)

    switch -Regex ($Status) {
        '^(pass(ed)?|ok|success(ful)?)$' { return $script:StatusPassed }
        '^(fail(ed|ure)?|error(ed)?|broken)$' { return $script:StatusFailed }
        '^(skip(ped)?|ignored?|disabled|pending|notrun)$' { return $script:StatusSkipped }
        default {
            throw "Unrecognized test status '$Status'. Expected a passed/failed/skipped synonym."
        }
    }
}

function ConvertFrom-JUnitXml {
    <#
    .SYNOPSIS
        Parses a JUnit-style XML file into normalized test case records.
    .DESCRIPTION
        Supports both a top-level <testsuites> wrapper and a bare <testsuite>.
        A <testcase> is Failed if it contains a <failure> or <error> child,
        Skipped if it contains a <skipped> child, otherwise Passed.
    .PARAMETER Path
        Path to the JUnit XML file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "JUnit XML file not found: '$Path'."
    }

    try {
        [xml]$doc = Get-Content -LiteralPath $Path -Raw
    }
    catch {
        throw "Failed to parse '$Path' as XML: $($_.Exception.Message)"
    }

    # Collect every <testcase> regardless of nesting depth.
    $testcaseNodes = $doc.SelectNodes('//testcase')
    if ($null -eq $testcaseNodes -or $testcaseNodes.Count -eq 0) {
        # An empty-but-valid file is allowed; just yields no records.
        return @()
    }

    $records = foreach ($tc in $testcaseNodes) {
        # Determine status from child elements.
        $status = $script:StatusPassed
        if ($tc.SelectSingleNode('failure') -or $tc.SelectSingleNode('error')) {
            $status = $script:StatusFailed
        }
        elseif ($tc.SelectSingleNode('skipped')) {
            $status = $script:StatusSkipped
        }

        # classname is the conventional JUnit suite identifier; fall back to the
        # parent <testsuite name=...> if classname is absent.
        $suite = $tc.classname
        if ([string]::IsNullOrEmpty($suite)) {
            $parent = $tc.ParentNode
            if ($parent -and $parent.name) { $suite = [string]$parent.name }
        }

        $duration = 0.0
        if ($tc.time) {
            # JUnit times are seconds, locale-invariant ('.' decimal separator).
            [double]::TryParse([string]$tc.time, [System.Globalization.NumberStyles]::Float,
                [System.Globalization.CultureInfo]::InvariantCulture, [ref]$duration) | Out-Null
        }

        [pscustomobject]@{
            Suite    = [string]$suite
            Name     = [string]$tc.name
            Status   = $status
            Duration = $duration
            File     = $Path
        }
    }

    return @($records)
}

function ConvertFrom-TestJson {
    <#
    .SYNOPSIS
        Parses a JSON test-result file into normalized test case records.
    .DESCRIPTION
        Accepts either an object with a 'tests' array, or a bare top-level array
        of test case objects. Each test case object should have 'name',
        optionally 'suite', 'status', and 'duration'. Status synonyms are
        normalized via ConvertTo-NormalizedStatus.
    .PARAMETER Path
        Path to the JSON file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "JSON file not found: '$Path'."
    }

    try {
        $data = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    }
    catch {
        throw "Failed to parse '$Path' as JSON: $($_.Exception.Message)"
    }

    # Support both { "tests": [...] } and a bare [...] top-level array.
    if ($data -is [System.Array]) {
        $tests = $data
        $topSuite = ''
    }
    elseif ($data.PSObject.Properties.Name -contains 'tests') {
        $tests = $data.tests
        $topSuite = if ($data.PSObject.Properties.Name -contains 'name') { [string]$data.name } else { '' }
    }
    elseif ($data.PSObject.Properties.Name -contains 'name') {
        # A single bare test-case object (pipeline-unwrapped one-element array).
        $tests = @($data)
        $topSuite = ''
    }
    else {
        throw "JSON file '$Path' must contain a 'tests' array or be a top-level array of test cases."
    }

    if ($null -eq $tests) { return @() }

    $records = foreach ($t in $tests) {
        $props = $t.PSObject.Properties.Name

        # Suite falls back to the document-level name when not set per-case.
        $suite = if ($props -contains 'suite' -and $t.suite) { [string]$t.suite } else { $topSuite }

        # Status defaults to Passed when omitted (common for terse formats).
        $rawStatus = if ($props -contains 'status' -and $t.status) { [string]$t.status } else { 'passed' }

        $duration = 0.0
        if ($props -contains 'duration' -and $null -ne $t.duration) {
            [double]::TryParse([string]$t.duration, [System.Globalization.NumberStyles]::Float,
                [System.Globalization.CultureInfo]::InvariantCulture, [ref]$duration) | Out-Null
        }

        [pscustomobject]@{
            Suite    = $suite
            Name     = [string]$t.name
            Status   = ConvertTo-NormalizedStatus $rawStatus
            Duration = $duration
            File     = $Path
        }
    }

    return @($records)
}

function Import-TestResults {
    <#
    .SYNOPSIS
        Loads all supported test-result files from a directory (or a single
        file) and returns a flat list of normalized test case records.
    .DESCRIPTION
        Dispatches each file to the appropriate parser based on its extension:
        .xml -> ConvertFrom-JUnitXml, .json -> ConvertFrom-TestJson. Each file
        represents one run of a CI matrix. Unsupported file types are ignored.
    .PARAMETER Path
        A directory containing result files, or a single result file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Result path not found: '$Path'."
    }

    # Resolve the set of candidate files.
    if (Test-Path -LiteralPath $Path -PathType Container) {
        $files = Get-ChildItem -LiteralPath $Path -File |
            Where-Object { $_.Extension -in '.xml', '.json' } |
            Sort-Object Name
    }
    else {
        $files = @(Get-Item -LiteralPath $Path)
    }

    if (-not $files -or $files.Count -eq 0) {
        throw "Found no .xml or .json result files in '$Path'."
    }

    $all = foreach ($f in $files) {
        switch ($f.Extension.ToLowerInvariant()) {
            '.xml'  { ConvertFrom-JUnitXml -Path $f.FullName }
            '.json' { ConvertFrom-TestJson -Path $f.FullName }
        }
    }

    return @($all)
}

function Get-TestAggregate {
    <#
    .SYNOPSIS
        Aggregates normalized test case records into totals plus a flaky-test
        report.
    .DESCRIPTION
        A test is identified across runs by its Suite + Name. It is "flaky" when,
        across all runs, it has at least one Passed result AND at least one Failed
        result. Totals count every individual run of every test (so a test run in
        3 matrix jobs contributes 3 to Total).
    .PARAMETER Records
        Normalized test case records (as produced by Import-TestResults).
    .OUTPUTS
        A pscustomobject with Total, Passed, Failed, Skipped, Duration, RunCount,
        and Flaky (a list of @{ Suite; Name; PassCount; FailCount }).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Records
    )

    $passed = 0; $failed = 0; $skipped = 0; $duration = 0.0
    foreach ($r in $Records) {
        switch ($r.Status) {
            'Passed'  { $passed++ }
            'Failed'  { $failed++ }
            'Skipped' { $skipped++ }
        }
        $duration += [double]$r.Duration
    }

    # Group every record by its logical test identity to find flaky tests.
    $flaky = foreach ($g in ($Records | Group-Object -Property { "$($_.Suite)::$($_.Name)" })) {
        $pc = @($g.Group | Where-Object Status -eq 'Passed').Count
        $fc = @($g.Group | Where-Object Status -eq 'Failed').Count
        if ($pc -gt 0 -and $fc -gt 0) {
            [pscustomobject]@{
                Suite     = $g.Group[0].Suite
                Name      = $g.Group[0].Name
                PassCount = $pc
                FailCount = $fc
            }
        }
    }

    $runCount = @($Records | Select-Object -ExpandProperty File -Unique).Count

    [pscustomobject]@{
        Total    = $Records.Count
        Passed   = $passed
        Failed   = $failed
        Skipped  = $skipped
        Duration = [math]::Round($duration, 3)
        RunCount = $runCount
        Flaky    = @($flaky | Sort-Object Suite, Name)
    }
}

function New-MarkdownSummary {
    <#
    .SYNOPSIS
        Renders an aggregate into a markdown report suitable for a GitHub Actions
        job summary ($GITHUB_STEP_SUMMARY).
    .PARAMETER Aggregate
        The object returned by Get-TestAggregate.
    .OUTPUTS
        A single multi-line markdown string.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Aggregate
    )

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('# Test Results Summary')
    [void]$sb.AppendLine('')

    # A one-line status banner: failures take priority, then flakes, then green.
    if ($Aggregate.Failed -gt 0) {
        [void]$sb.AppendLine(":x: **$($Aggregate.Failed) of $($Aggregate.Total) test runs failed.**")
    }
    elseif ($Aggregate.Flaky.Count -gt 0) {
        [void]$sb.AppendLine(":warning: **All tests passed, but $($Aggregate.Flaky.Count) flaky test(s) detected.**")
    }
    else {
        [void]$sb.AppendLine(":white_check_mark: **All $($Aggregate.Total) tests passed.**")
    }
    [void]$sb.AppendLine('')

    # Totals table. Use invariant formatting so the decimal separator is stable
    # across CI locales (important for exact-value assertions).
    $dur = ([double]$Aggregate.Duration).ToString([System.Globalization.CultureInfo]::InvariantCulture)
    [void]$sb.AppendLine('| Metric | Value |')
    [void]$sb.AppendLine('| --- | --- |')
    [void]$sb.AppendLine("| Total | $($Aggregate.Total) |")
    [void]$sb.AppendLine("| Passed | $($Aggregate.Passed) |")
    [void]$sb.AppendLine("| Failed | $($Aggregate.Failed) |")
    [void]$sb.AppendLine("| Skipped | $($Aggregate.Skipped) |")
    [void]$sb.AppendLine("| Duration | ${dur}s |")
    [void]$sb.AppendLine("| Runs | $($Aggregate.RunCount) |")
    [void]$sb.AppendLine('')

    # Flaky tests section.
    [void]$sb.AppendLine('## Flaky Tests')
    [void]$sb.AppendLine('')
    if ($Aggregate.Flaky.Count -eq 0) {
        [void]$sb.AppendLine('No flaky tests detected.')
    }
    else {
        [void]$sb.AppendLine('| Suite | Test | Passes | Failures |')
        [void]$sb.AppendLine('| --- | --- | --- | --- |')
        foreach ($f in $Aggregate.Flaky) {
            [void]$sb.AppendLine("| $($f.Suite) | $($f.Name) | $($f.PassCount) | $($f.FailCount) |")
        }
    }

    return $sb.ToString().TrimEnd()
}

Export-ModuleMember -Function ConvertFrom-JUnitXml, ConvertFrom-TestJson, ConvertTo-NormalizedStatus, Import-TestResults, Get-TestAggregate, New-MarkdownSummary
