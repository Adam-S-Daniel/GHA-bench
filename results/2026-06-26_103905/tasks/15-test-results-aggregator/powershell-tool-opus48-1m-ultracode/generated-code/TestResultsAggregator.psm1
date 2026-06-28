<#
.SYNOPSIS
    Test Results Aggregator — parses test result files (JUnit XML and JSON),
    aggregates them across a matrix of runs, computes totals, detects flaky
    tests, and renders a GitHub-Actions-ready markdown summary.

.DESCRIPTION
    The design centres on a single *normalized* test-result object that every
    parser emits and every consumer reads:

        Suite    [string]  logical grouping (JUnit classname / JSON suite)
        Name     [string]  test case name
        Status   [string]  one of: passed | failed | skipped
        Duration [double]  seconds spent in the test case
        Source   [string]  file the result was read from

    Keeping every format funnelled through this one shape means totals, flaky
    detection, and markdown rendering never need to know which on-disk format a
    result came from. Each function validates its inputs and throws a clear,
    actionable error rather than failing obscurely later.
#>

Set-StrictMode -Version Latest

# Canonical statuses used everywhere downstream.
$script:STATUS_PASSED  = 'passed'
$script:STATUS_FAILED  = 'failed'
$script:STATUS_SKIPPED = 'skipped'

# Map the many synonyms real-world tools emit onto our canonical statuses.
$script:StatusMap = @{
    'passed'  = $script:STATUS_PASSED;  'pass'    = $script:STATUS_PASSED
    'ok'      = $script:STATUS_PASSED;   'success' = $script:STATUS_PASSED
    'succeeded' = $script:STATUS_PASSED
    'failed'  = $script:STATUS_FAILED;  'fail'    = $script:STATUS_FAILED
    'failure' = $script:STATUS_FAILED;  'error'   = $script:STATUS_FAILED
    'errored' = $script:STATUS_FAILED;  'broken'  = $script:STATUS_FAILED
    'skipped' = $script:STATUS_SKIPPED; 'skip'    = $script:STATUS_SKIPPED
    'pending' = $script:STATUS_SKIPPED; 'ignored' = $script:STATUS_SKIPPED
    'disabled' = $script:STATUS_SKIPPED; 'notrun' = $script:STATUS_SKIPPED
}

function New-NormalizedResult {
    # Small factory so every parser produces an identically-shaped object.
    param(
        [string]$Suite,
        [string]$Name,
        [string]$Status,
        [double]$Duration,
        [string]$Source
    )
    [PSCustomObject]@{
        Suite    = $Suite
        Name     = $Name
        Status   = $Status
        Duration = $Duration
        Source   = $Source
    }
}

function ConvertTo-CanonicalStatus {
    <#
    .SYNOPSIS Normalize an arbitrary status string to passed/failed/skipped.
    .DESCRIPTION Throws with a helpful message listing valid values when the
                 status is not recognised, so a malformed fixture fails loudly.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Status)

    $key = ($Status ?? '').Trim().ToLowerInvariant()
    if ($script:StatusMap.ContainsKey($key)) {
        return $script:StatusMap[$key]
    }
    throw "Unrecognized test status '$Status'. Expected one of: passed, failed, skipped (or a known synonym)."
}

function ConvertTo-Seconds {
    # Parse a duration string as a culture-invariant double so "0.10" never
    # becomes 10 (comma-decimal locales) and a missing value becomes 0.
    param([AllowNull()][AllowEmptyString()]$Value)
    if ($null -eq $Value -or "$Value".Trim() -eq '') { return [double]0 }
    [double]$out = 0
    if ([double]::TryParse("$Value", [System.Globalization.NumberStyles]::Float,
            [System.Globalization.CultureInfo]::InvariantCulture, [ref]$out)) {
        return $out
    }
    return [double]0
}

function ConvertFrom-JUnitXml {
    <#
    .SYNOPSIS Read a JUnit XML file into normalized test-result objects.
    .DESCRIPTION Accepts either a <testsuites> root or a bare <testsuite> root,
                 at any nesting depth. A <testcase> is 'failed' when it carries
                 a <failure> or <error> child, 'skipped' for a <skipped> child,
                 otherwise 'passed'.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "JUnit XML file not found: '$Path'"
    }

    try {
        [xml]$doc = Get-Content -LiteralPath $Path -Raw
    } catch {
        throw "Failed to parse JUnit XML '$Path': $($_.Exception.Message)"
    }

    $source = Split-Path -Leaf $Path
    $cases = $doc.SelectNodes('//testcase')
    if ($null -eq $cases) { return @() }

    $results = foreach ($tc in $cases) {
        # classname is the conventional JUnit suite; fall back to the enclosing
        # <testsuite name="...">, then to 'default' so a key is always present.
        $suite = $tc.GetAttribute('classname')
        if ([string]::IsNullOrEmpty($suite)) {
            $parent = $tc.ParentNode
            if ($parent -and $parent.Attributes -and $parent.Attributes['name']) {
                $suite = $parent.GetAttribute('name')
            }
        }
        if ([string]::IsNullOrEmpty($suite)) { $suite = 'default' }

        if     ($tc['failure'] -or $tc['error']) { $status = $script:STATUS_FAILED }
        elseif ($tc['skipped'])                  { $status = $script:STATUS_SKIPPED }
        else                                     { $status = $script:STATUS_PASSED }

        New-NormalizedResult -Suite $suite -Name $tc.GetAttribute('name') `
            -Status $status -Duration (ConvertTo-Seconds $tc.GetAttribute('time')) `
            -Source $source
    }

    # Always return an array even for a single case (foreach can unwrap to scalar).
    return @($results)
}

function ConvertFrom-TestJson {
    <#
    .SYNOPSIS Read a JSON test-result file into normalized test-result objects.
    .DESCRIPTION Supported shapes:
                   { "suite": "S", "tests": [ {name,status,duration,suite?} ] }
                   [ {name,status,duration,suite} ]   (bare array of cases)
                 Per-case "suite" overrides the document-level suite; duration
                 defaults to 0; status is normalized via ConvertTo-CanonicalStatus.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "JSON test file not found: '$Path'"
    }

    try {
        $data = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    } catch {
        throw "Failed to parse JSON '$Path': $($_.Exception.Message)"
    }

    $source = Split-Path -Leaf $Path

    # Resolve the test-case array and any document-level suite default.
    $defaultSuite = 'default'
    if ($data -is [System.Array]) {
        $cases = $data
    } elseif ($null -ne $data -and ($data.PSObject.Properties.Name -contains 'tests')) {
        $cases = $data.tests
        if ($data.PSObject.Properties.Name -contains 'suite' -and $data.suite) {
            $defaultSuite = [string]$data.suite
        } elseif ($data.PSObject.Properties.Name -contains 'name' -and $data.name) {
            $defaultSuite = [string]$data.name
        }
    } else {
        throw "JSON '$Path' is not a recognised test-result document (expected an array of cases or an object with a 'tests' array)."
    }

    if ($null -eq $cases) { return @() }

    $results = foreach ($c in $cases) {
        $names = $c.PSObject.Properties.Name
        if ($names -notcontains 'name') {
            throw "JSON '$Path' contains a test case with no 'name' field."
        }
        if ($names -notcontains 'status') {
            throw "JSON '$Path' test case '$($c.name)' has no 'status' field."
        }

        $suite = $defaultSuite
        if ($names -contains 'suite' -and $c.suite) { $suite = [string]$c.suite }

        $duration = 0
        if ($names -contains 'duration') { $duration = ConvertTo-Seconds $c.duration }

        New-NormalizedResult -Suite $suite -Name ([string]$c.name) `
            -Status (ConvertTo-CanonicalStatus ([string]$c.status)) `
            -Duration $duration -Source $source
    }

    return @($results)
}

function Import-TestResultFile {
    <#
    .SYNOPSIS Parse a single test-result file, dispatching on its extension.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Test result file not found: '$Path'"
    }

    switch -Regex ([System.IO.Path]::GetExtension($Path).ToLowerInvariant()) {
        '\.xml$|\.junit$' { return ConvertFrom-JUnitXml -Path $Path }
        '\.json$'         { return ConvertFrom-TestJson  -Path $Path }
        default {
            throw "Unsupported test result format for '$Path'. Supported extensions: .xml, .junit, .json"
        }
    }
}

function Get-TestResultSummary {
    <#
    .SYNOPSIS Compute totals (passed/failed/skipped/total/duration) over results.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Results)

    $passed  = @($Results | Where-Object Status -eq $script:STATUS_PASSED).Count
    $failed  = @($Results | Where-Object Status -eq $script:STATUS_FAILED).Count
    $skipped = @($Results | Where-Object Status -eq $script:STATUS_SKIPPED).Count
    $duration = ($Results | Measure-Object -Property Duration -Sum).Sum
    if ($null -eq $duration) { $duration = 0 }

    [PSCustomObject]@{
        Total    = $Results.Count
        Passed   = $passed
        Failed   = $failed
        Skipped  = $skipped
        Duration = [double]$duration
    }
}

function Get-FlakyTest {
    <#
    .SYNOPSIS Identify flaky tests — those that both passed and failed across runs.
    .DESCRIPTION Tests are identified by "Suite::Name". A test is flaky when, over
                 all aggregated runs, it has at least one 'passed' AND at least one
                 'failed' result. Skips alone never make a test flaky.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Results)

    $flaky = foreach ($group in ($Results | Group-Object { "$($_.Suite)::$($_.Name)" })) {
        $p = @($group.Group | Where-Object Status -eq $script:STATUS_PASSED).Count
        $f = @($group.Group | Where-Object Status -eq $script:STATUS_FAILED).Count
        $s = @($group.Group | Where-Object Status -eq $script:STATUS_SKIPPED).Count
        if ($p -gt 0 -and $f -gt 0) {
            [PSCustomObject]@{
                Key     = $group.Name
                Suite   = $group.Group[0].Suite
                Name    = $group.Group[0].Name
                Passed  = $p
                Failed  = $f
                Skipped = $s
                Runs    = $group.Count
            }
        }
    }

    return @($flaky | Sort-Object Key)
}

function Resolve-TestResultFile {
    <#
    .SYNOPSIS Expand a path (file, directory, or glob) into a sorted file list.
    #>
    param([Parameter(Mandatory)][string[]]$Path)

    $files = foreach ($p in $Path) {
        if (Test-Path -LiteralPath $p -PathType Container) {
            # A directory: pick up every supported result file inside it.
            Get-ChildItem -LiteralPath $p -File |
                Where-Object { $_.Extension -match '^\.(xml|junit|json)$' } |
                Select-Object -ExpandProperty FullName
        } elseif (Test-Path -LiteralPath $p) {
            (Resolve-Path -LiteralPath $p).Path
        } else {
            # Treat as a glob (Resolve-Path supports wildcards).
            $resolved = Resolve-Path -Path $p -ErrorAction SilentlyContinue
            if ($resolved) { $resolved.Path }
        }
    }

    return @($files | Sort-Object -Unique)
}

function Get-AggregatedTestResults {
    <#
    .SYNOPSIS Parse and aggregate every test result file under the given path(s).
    .DESCRIPTION Returns an object bundling the normalized results, overall
                 summary, flaky-test list, and a per-file breakdown — everything
                 the markdown renderer needs.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Path)

    # @() guarantees an array even when resolution finds zero or one file
    # (PowerShell otherwise unwraps these to $null / a scalar, which then has
    # no .Count under StrictMode).
    $files = @(Resolve-TestResultFile -Path $Path)
    if ($files.Count -eq 0) {
        throw "No test result files (.xml/.junit/.json) found at: $($Path -join ', ')"
    }

    $all = New-Object System.Collections.Generic.List[object]
    $perFile = foreach ($file in $files) {
        $parsed = @(Import-TestResultFile -Path $file)
        foreach ($r in $parsed) { $all.Add($r) }
        $fileSummary = Get-TestResultSummary -Results $parsed
        [PSCustomObject]@{
            File     = (Split-Path -Leaf $file)
            Total    = $fileSummary.Total
            Passed   = $fileSummary.Passed
            Failed   = $fileSummary.Failed
            Skipped  = $fileSummary.Skipped
            Duration = $fileSummary.Duration
        }
    }

    $allArray = $all.ToArray()
    # @() on every collection field keeps an empty result an empty array rather
    # than $null (PowerShell unwraps a zero-element pipeline return to $null).
    [PSCustomObject]@{
        Files   = @($perFile)
        Results = @($allArray)
        Summary = Get-TestResultSummary -Results $allArray
        Flaky   = @(Get-FlakyTest -Results $allArray)
    }
}

function Format-Seconds {
    # Culture-invariant 2-decimal seconds, used for every duration we print.
    param([double]$Seconds)
    return $Seconds.ToString('F2', [System.Globalization.CultureInfo]::InvariantCulture) + 's'
}

function Format-TestResultMarkdown {
    <#
    .SYNOPSIS Render an aggregated-results object as a GitHub job-summary markdown.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][PSObject]$Aggregate)

    $s = $Aggregate.Summary
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('# Test Results Summary')
    [void]$sb.AppendLine('')

    # A one-glance verdict line.
    $verdict = if ($s.Failed -gt 0) { ':x: **Failing**' }
               elseif ($s.Total -eq 0) { ':warning: **No tests**' }
               else { ':white_check_mark: **Passing**' }
    [void]$sb.AppendLine("$verdict — $($s.Total) tests across $(@($Aggregate.Files).Count) run(s)")
    [void]$sb.AppendLine('')

    # Totals table.
    [void]$sb.AppendLine('| Metric | Count |')
    [void]$sb.AppendLine('| --- | --- |')
    [void]$sb.AppendLine("| :white_check_mark: Passed | $($s.Passed) |")
    [void]$sb.AppendLine("| :x: Failed | $($s.Failed) |")
    [void]$sb.AppendLine("| :fast_forward: Skipped | $($s.Skipped) |")
    [void]$sb.AppendLine("| :1234: Total | $($s.Total) |")
    [void]$sb.AppendLine("| :stopwatch: Duration | $(Format-Seconds $s.Duration) |")
    [void]$sb.AppendLine('')

    # Per-file (per-matrix-run) breakdown.
    [void]$sb.AppendLine('## Per-file breakdown')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('| File | Passed | Failed | Skipped | Total | Duration |')
    [void]$sb.AppendLine('| --- | --- | --- | --- | --- | --- |')
    foreach ($f in $Aggregate.Files) {
        [void]$sb.AppendLine("| $($f.File) | $($f.Passed) | $($f.Failed) | $($f.Skipped) | $($f.Total) | $(Format-Seconds $f.Duration) |")
    }
    [void]$sb.AppendLine('')

    # Flaky tests.
    [void]$sb.AppendLine('## Flaky Tests')
    [void]$sb.AppendLine('')
    if (@($Aggregate.Flaky).Count -eq 0) {
        [void]$sb.AppendLine('No flaky tests detected. :tada:')
    } else {
        [void]$sb.AppendLine("$($Aggregate.Flaky.Count) test(s) passed in some runs and failed in others:")
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('| Test | Passed | Failed | Skipped | Runs |')
        [void]$sb.AppendLine('| --- | --- | --- | --- | --- |')
        foreach ($t in $Aggregate.Flaky) {
            [void]$sb.AppendLine("| $($t.Key) | $($t.Passed) | $($t.Failed) | $($t.Skipped) | $($t.Runs) |")
        }
    }
    [void]$sb.AppendLine('')

    return $sb.ToString().TrimEnd() + "`n"
}

Export-ModuleMember -Function `
    ConvertFrom-JUnitXml, ConvertFrom-TestJson, Import-TestResultFile, `
    Get-TestResultSummary, Get-FlakyTest, Get-AggregatedTestResults, `
    Format-TestResultMarkdown, ConvertTo-CanonicalStatus, Resolve-TestResultFile
