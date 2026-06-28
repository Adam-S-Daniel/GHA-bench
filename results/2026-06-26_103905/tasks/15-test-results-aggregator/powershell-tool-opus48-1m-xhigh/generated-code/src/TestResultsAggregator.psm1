#Requires -Version 7.0
<#
    TestResultsAggregator.psm1

    A small toolkit for aggregating software test results across a matrix build.
    It can:
      * parse JUnit XML and JSON test reports into a single normalized shape,
      * aggregate many reports (one per matrix leg) into combined totals,
      * detect flaky tests (passed in some runs, failed in others),
      * render a Markdown summary suitable for a GitHub Actions job summary.

    Every function is written defensively: invalid paths, malformed documents
    and unknown formats raise clear, actionable error messages rather than
    leaking raw parser exceptions.
#>

Set-StrictMode -Version Latest

# Culture used for ALL number parsing/formatting. Test reports always encode
# durations with a '.' decimal separator; forcing InvariantCulture keeps the
# tool correct on machines/containers configured with a comma decimal locale.
$script:Invariant = [System.Globalization.CultureInfo]::InvariantCulture

#region Private helpers

function Get-NormalizedStatus {
    <#
        Maps the many status spellings found across tools/formats onto the three
        canonical buckets used throughout this module: Passed, Failed, Skipped.
        Unknown values are treated as failures so problems are never hidden.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Status
    )

    switch -Regex ($Status.Trim().ToLowerInvariant()) {
        '^(passed|pass|success|succeeded|ok)$'              { return 'Passed' }
        '^(failed|fail|failure|error|errored|broken)$'      { return 'Failed' }
        '^(skipped|skip|ignored|ignore|pending|disabled)$'  { return 'Skipped' }
        default                                             { return 'Failed' }
    }
}

function ConvertTo-InvariantDouble {
    <#
        Parses a duration string into a [double] using InvariantCulture. Empty
        or absent values become 0. Anything non-numeric raises a clear error.
    #>
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) { return [double] 0 }

    [double] $parsed = 0
    if (-not [double]::TryParse($Value, [System.Globalization.NumberStyles]::Float, $script:Invariant, [ref] $parsed)) {
        throw "Cannot interpret '$Value' as a numeric duration."
    }
    return $parsed
}

#endregion Private helpers

function ConvertFrom-JUnitXml {
    <#
        .SYNOPSIS
            Parses a JUnit-style XML report into normalized result objects.
        .DESCRIPTION
            Handles documents rooted at either <testsuites> or a single
            <testsuite>, and treats <failure>/<error> child elements as failures
            and <skipped> as skipped. Test names are qualified with their
            classname (e.g. "Calc.add") so identical method names in different
            classes do not collide during aggregation.
        .PARAMETER Path
            Path to the JUnit XML file.
        .OUTPUTS
            One PSCustomObject per testcase with Name, Status, Duration, Suite.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.List[object]])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string] $Path
    )

    process {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            throw "JUnit XML file not found: '$Path'."
        }

        try {
            [xml] $doc = Get-Content -LiteralPath $Path -Raw
        }
        catch {
            throw "Failed to parse '$Path' as XML: $($_.Exception.Message)"
        }

        # Find every <testsuite>, whether wrapped in <testsuites> or standalone.
        $suites = $doc.SelectNodes('//testsuite')
        if ($null -eq $suites -or $suites.Count -eq 0) {
            throw "No <testsuite> elements found in '$Path'; is this a JUnit report?"
        }

        $results = [System.Collections.Generic.List[object]]::new()

        foreach ($suite in $suites) {
            $suiteName = if ($suite.HasAttribute('name')) { $suite.GetAttribute('name') } else { 'suite' }

            foreach ($case in $suite.SelectNodes('testcase')) {
                # Qualify the test name with its class when available.
                $classname = if ($case.HasAttribute('classname')) { $case.GetAttribute('classname') } else { '' }
                $caseName  = if ($case.HasAttribute('name')) { $case.GetAttribute('name') } else { 'test' }
                $fullName  = if ([string]::IsNullOrWhiteSpace($classname)) { $caseName } else { "$classname.$caseName" }

                # Determine status from child elements (JUnit encodes outcome as
                # the presence of <failure>, <error> or <skipped> children).
                $status = 'Passed'
                if ($case.SelectSingleNode('failure') -or $case.SelectSingleNode('error')) {
                    $status = 'Failed'
                }
                elseif ($case.SelectSingleNode('skipped')) {
                    $status = 'Skipped'
                }

                $time = if ($case.HasAttribute('time')) { $case.GetAttribute('time') } else { '0' }

                $results.Add([pscustomobject]@{
                    Name     = $fullName
                    Status   = $status
                    Duration = ConvertTo-InvariantDouble -Value $time
                    Suite    = $suiteName
                })
            }
        }

        return $results
    }
}

function ConvertFrom-TestJson {
    <#
        .SYNOPSIS
            Parses a JSON test report into normalized result objects.
        .DESCRIPTION
            Accepts either an object with a "tests" array or a bare top-level
            array. Each test entry may name its status under any of
            status/result/outcome and its duration under duration/time/elapsed,
            making the parser tolerant of the many JSON conventions in the wild.
        .PARAMETER Path
            Path to the JSON file.
        .OUTPUTS
            One PSCustomObject per test with Name, Status, Duration, Suite.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.List[object]])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string] $Path
    )

    process {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            throw "JSON file not found: '$Path'."
        }

        try {
            # -NoEnumerate keeps a top-level JSON array intact instead of letting
            # the pipeline unwrap a single-element array into a lone object.
            $raw  = Get-Content -LiteralPath $Path -Raw
            $data = ConvertFrom-Json -InputObject $raw -NoEnumerate -ErrorAction Stop
        }
        catch {
            throw "Failed to parse '$Path' as JSON: $($_.Exception.Message)"
        }

        # Accept both {"tests":[...]} and a bare [...] array.
        $suiteName = 'suite'
        if ($data -is [System.Array] -or $data -is [System.Collections.IList]) {
            $tests = $data
        }
        elseif ($null -ne $data.PSObject.Properties['tests']) {
            $tests = $data.tests
            if ($null -ne $data.PSObject.Properties['suite']) { $suiteName = [string] $data.suite }
            elseif ($null -ne $data.PSObject.Properties['name']) { $suiteName = [string] $data.name }
        }
        else {
            throw "JSON report '$Path' has no 'tests' array and is not itself an array."
        }

        $results = [System.Collections.Generic.List[object]]::new()

        foreach ($t in $tests) {
            # Tolerate several spellings for the name, status and duration keys.
            $name = $null
            foreach ($k in 'name', 'test', 'title', 'fullName') {
                if ($null -ne $t.PSObject.Properties[$k] -and -not [string]::IsNullOrWhiteSpace([string] $t.$k)) {
                    $name = [string] $t.$k; break
                }
            }
            if ([string]::IsNullOrWhiteSpace($name)) { $name = 'test' }

            $rawStatus = ''
            foreach ($k in 'status', 'result', 'outcome', 'state') {
                if ($null -ne $t.PSObject.Properties[$k]) { $rawStatus = [string] $t.$k; break }
            }

            $rawDuration = ''
            foreach ($k in 'duration', 'time', 'elapsed', 'durationSeconds') {
                if ($null -ne $t.PSObject.Properties[$k]) { $rawDuration = [string] $t.$k; break }
            }

            $thisSuite = $suiteName
            if ($null -ne $t.PSObject.Properties['suite'] -and -not [string]::IsNullOrWhiteSpace([string] $t.suite)) {
                $thisSuite = [string] $t.suite
            }

            $results.Add([pscustomobject]@{
                Name     = $name
                Status   = Get-NormalizedStatus -Status $rawStatus
                Duration = ConvertTo-InvariantDouble -Value $rawDuration
                Suite    = $thisSuite
            })
        }

        return $results
    }
}

function Import-TestResultFile {
    <#
        .SYNOPSIS
            Imports a single test report, choosing the parser by file extension.
        .DESCRIPTION
            Routes .xml/.junit files to ConvertFrom-JUnitXml and .json files to
            ConvertFrom-TestJson, then stamps every result with a 'Run' property
            (the file's leaf name) so aggregation can tell matrix legs apart and
            flaky-test detection can compare a test's outcome across runs.
        .PARAMETER Path
            Path to a single test report file.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.List[object]])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string] $Path
    )

    process {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            throw "Test result file not found: '$Path'."
        }

        $runName   = Split-Path -Path $Path -Leaf
        $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()

        switch ($extension) {
            { $_ -in '.xml', '.junit' } { $parsed = ConvertFrom-JUnitXml -Path $Path }
            '.json'                     { $parsed = ConvertFrom-TestJson -Path $Path }
            default {
                throw "Unsupported file extension '$extension' for '$Path'. Supported: .xml, .json."
            }
        }

        $results = [System.Collections.Generic.List[object]]::new()
        foreach ($r in $parsed) {
            # Add the Run column without mutating the parser's output shape.
            $results.Add([pscustomobject]@{
                Name     = $r.Name
                Status   = $r.Status
                Duration = $r.Duration
                Suite    = $r.Suite
                Run      = $runName
            })
        }
        return $results
    }
}

function Get-TestTotals {
    <#
        .SYNOPSIS
            Aggregates a flat list of results into combined matrix-build totals.
        .DESCRIPTION
            Each result instance (one test, one run) is counted independently, so
            totals reflect the full matrix the way GitHub's own summaries do:
            a test that ran in three legs contributes three instances. Duration
            is the sum of every instance's wall-clock time, in seconds.
        .PARAMETER Result
            The normalized result objects to aggregate.
        .OUTPUTS
            A PSCustomObject with Passed, Failed, Skipped, Total, Duration.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Result
    )

    $passed = 0; $failed = 0; $skipped = 0
    [double] $duration = 0

    foreach ($r in $Result) {
        switch ($r.Status) {
            'Passed'  { $passed++ }
            'Failed'  { $failed++ }
            'Skipped' { $skipped++ }
        }
        $duration += [double] $r.Duration
    }

    return [pscustomobject]@{
        Passed   = $passed
        Failed   = $failed
        Skipped  = $skipped
        Total    = $passed + $failed + $skipped
        # Round to millisecond precision so accumulated binary-float noise (e.g.
        # 0.1 + 0.2 = 0.30000000000000004) never leaks into reports or assertions.
        Duration = [Math]::Round($duration, 3)
    }
}

function Get-FlakyTest {
    <#
        .SYNOPSIS
            Identifies flaky tests across matrix runs.
        .DESCRIPTION
            A test is "flaky" when, grouped by its name, it both passed at least
            once and failed at least once across the aggregated runs. Tests that
            always pass, always fail (a stable failure), or only ever skip are
            NOT flaky. Results are returned sorted by name for stable reporting.
        .PARAMETER Result
            The normalized result objects to analyze.
        .OUTPUTS
            One PSCustomObject per flaky test: Name, PassedCount, FailedCount,
            SkippedCount, Runs.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.List[object]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Result
    )

    $flaky = [System.Collections.Generic.List[object]]::new()

    # Group every result instance by the test's fully-qualified name.
    $groups = $Result | Group-Object -Property Name

    foreach ($group in ($groups | Sort-Object Name)) {
        $passed  = @($group.Group | Where-Object Status -eq 'Passed').Count
        $failed  = @($group.Group | Where-Object Status -eq 'Failed').Count
        $skipped = @($group.Group | Where-Object Status -eq 'Skipped').Count

        # Flaky == observed both a pass AND a fail for the same test name.
        if ($passed -gt 0 -and $failed -gt 0) {
            $flaky.Add([pscustomobject]@{
                Name         = $group.Name
                PassedCount  = $passed
                FailedCount  = $failed
                SkippedCount = $skipped
                Runs         = $group.Count
            })
        }
    }

    return $flaky
}

function New-TestSummaryMarkdown {
    <#
        .SYNOPSIS
            Renders an aggregated test report as GitHub-flavored Markdown.
        .DESCRIPTION
            Produces a self-contained Markdown document with a totals table, the
            combined duration and run count, and a flaky-test section. The output
            is suitable for appending to $GITHUB_STEP_SUMMARY. (Plain text labels
            are used instead of emoji to keep the report portable and diffable.)
        .PARAMETER Result
            The normalized result objects to summarize.
        .OUTPUTS
            A single Markdown string.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Result
    )

    $totals = Get-TestTotals -Result $Result
    $flaky  = @(Get-FlakyTest -Result $Result)

    # Count distinct matrix legs by their Run (source file) tag.
    $runCount = @($Result | Where-Object { $_.Run } |
        Select-Object -ExpandProperty Run -Unique).Count

    $durationText = [string]::Format($script:Invariant, '{0:F2}', $totals.Duration)

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('# Test Results Summary')
    $lines.Add('')
    $lines.Add('| Result | Count |')
    $lines.Add('| ------- | ----- |')
    $lines.Add("| Passed | $($totals.Passed) |")
    $lines.Add("| Failed | $($totals.Failed) |")
    $lines.Add("| Skipped | $($totals.Skipped) |")
    $lines.Add("| **Total** | **$($totals.Total)** |")
    $lines.Add('')
    $lines.Add("- **Total duration:** ${durationText}s")
    $lines.Add("- **Runs aggregated:** $runCount")
    $lines.Add('')
    $lines.Add('## Flaky Tests')
    $lines.Add('')

    if ($flaky.Count -eq 0) {
        $lines.Add('No flaky tests detected.')
    }
    else {
        $lines.Add('These tests passed in some runs and failed in others:')
        $lines.Add('')
        $lines.Add('| Test | Passed | Failed | Skipped | Runs |')
        $lines.Add('| ---- | ------ | ------ | ------- | ---- |')
        foreach ($f in $flaky) {
            $lines.Add("| $($f.Name) | $($f.PassedCount) | $($f.FailedCount) | $($f.SkippedCount) | $($f.Runs) |")
        }
    }
    $lines.Add('')

    return ($lines -join "`n")
}

function Invoke-TestResultAggregation {
    <#
        .SYNOPSIS
            End-to-end aggregation: import many reports, total them, find flaky
            tests, and render the Markdown summary in one call.
        .DESCRIPTION
            -Path may be a single directory (all *.xml and *.json beneath it are
            imported) or an explicit list of files. The function is the engine
            behind Invoke-Aggregator.ps1 and returns a single report object so
            callers can both inspect the numbers and emit the Markdown.
        .PARAMETER Path
            A directory to scan, or one or more report file paths.
        .OUTPUTS
            A PSCustomObject: Results, Totals, Flaky, Markdown, RunCount, Files.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string[]] $Path
    )

    # Resolve the input set into a concrete list of files.
    $files = [System.Collections.Generic.List[string]]::new()

    if ($Path.Count -eq 1 -and (Test-Path -LiteralPath $Path[0] -PathType Container)) {
        # A directory: collect every supported report inside it (sorted so the
        # run order, and therefore the report, is deterministic).
        Get-ChildItem -LiteralPath $Path[0] -File -Recurse |
            Where-Object { $_.Extension -in '.xml', '.json', '.junit' } |
            Sort-Object FullName |
            ForEach-Object { $files.Add($_.FullName) }
    }
    else {
        foreach ($p in $Path) {
            if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
                throw "Test result file not found: '$p'."
            }
            $files.Add((Resolve-Path -LiteralPath $p).Path)
        }
    }

    if ($files.Count -eq 0) {
        throw "No test result files (.xml/.json) found under '$($Path -join ', ')'."
    }

    # Import and concatenate every leg of the matrix.
    $allResults = [System.Collections.Generic.List[object]]::new()
    foreach ($file in $files) {
        foreach ($r in (Import-TestResultFile -Path $file)) {
            $allResults.Add($r)
        }
    }

    $totals   = Get-TestTotals -Result $allResults
    $flaky    = @(Get-FlakyTest -Result $allResults)
    $markdown = New-TestSummaryMarkdown -Result $allResults
    $runCount = @($allResults | Where-Object { $_.Run } |
        Select-Object -ExpandProperty Run -Unique).Count

    return [pscustomobject]@{
        Results  = $allResults
        Totals   = $totals
        Flaky    = $flaky
        Markdown = $markdown
        RunCount = $runCount
        Files    = $files
    }
}

Export-ModuleMember -Function ConvertFrom-JUnitXml, ConvertFrom-TestJson, Import-TestResultFile, Get-TestTotals, Get-FlakyTest, New-TestSummaryMarkdown, Invoke-TestResultAggregation
