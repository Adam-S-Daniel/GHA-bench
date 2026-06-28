<#
.SYNOPSIS
    Library of functions for aggregating test results from multiple CI runs.

.DESCRIPTION
    This file only DEFINES functions; it performs no work when dot-sourced.
    Dot-source it from a driver script (Invoke-Aggregator.ps1) or from tests.

    The pipeline is:
        Import-TestResultSet  -> reads many JUnit XML / JSON files into a flat
                                 list of normalized test-result records.
        Get-AggregateSummary  -> totals (passed/failed/skipped/duration) plus
                                 flaky-test detection across the matrix of runs.
        Format-MarkdownSummary-> renders the summary object as GitHub-flavoured
                                 markdown suitable for a job summary.

    A "test result record" is a [pscustomobject] with these properties:
        Run      - name of the run/file the result came from (a matrix leg)
        Suite    - test suite / class name (may be $null)
        Name     - test case name
        FullName - "Suite.Name" (or just "Name") - the flaky-grouping key
        Status   - one of 'Passed', 'Failed', 'Skipped'
        Duration - execution time in seconds ([double])
        Message  - failure/skip message, if any
#>

Set-StrictMode -Version Latest

# --- Private helpers ---------------------------------------------------------

# Parse a value into a [double] using the invariant culture so that JUnit/JSON
# decimal points ('.') are honoured regardless of the host's locale.
function ConvertTo-Double {
    param($Value)
    if ($null -eq $Value -or $Value -eq '') { return 0.0 }
    if ($Value -is [double] -or $Value -is [int] -or $Value -is [long] -or $Value -is [decimal]) {
        return [double]$Value
    }
    $parsed = 0.0
    $ok = [double]::TryParse(
        [string]$Value,
        [System.Globalization.NumberStyles]::Float,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [ref]$parsed)
    if ($ok) { return $parsed }
    return 0.0
}

# Map the many status spellings found across test frameworks onto our three
# canonical states. Throws on anything unrecognized so bad data is loud.
function ConvertTo-NormalizedStatus {
    param([string]$Raw)
    $value = ("$Raw").Trim().ToLowerInvariant()
    switch -Regex ($value) {
        '^(pass|passed|success|succeeded|ok)$'              { return 'Passed' }
        '^(fail|failed|failure|error|errored|broken)$'      { return 'Failed' }
        '^(skip|skipped|ignored|pending|disabled|notrun)$'  { return 'Skipped' }
        default { throw "Unrecognized test status '$Raw'." }
    }
}

# Build a normalized record. Named ConvertTo-* (not New-*) so PSScriptAnalyzer
# does not (rightly) ask a New- function to support -WhatIf/-Confirm.
function ConvertTo-TestResultRecord {
    param($Name, $Suite, $Status, $Duration, $Run, $Message)
    $fullName = if ($Suite) { "$Suite.$Name" } else { "$Name" }
    [pscustomobject]@{
        Run      = $Run
        Suite    = $Suite
        Name     = $Name
        FullName = $fullName
        Status   = $Status
        Duration = [double]$Duration
        Message  = $Message
    }
}

# --- Parsers -----------------------------------------------------------------

<#
.SYNOPSIS
    Parse a single JUnit XML file into normalized test-result records.
#>
function Import-JUnitResult {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "JUnit result file not found: '$Path'."
    }

    try {
        [xml]$doc = Get-Content -LiteralPath $Path -Raw
    } catch {
        throw "Failed to parse JUnit XML '$Path': $($_.Exception.Message)"
    }

    $run = [System.IO.Path]::GetFileName($Path)
    # '//testsuite' matches both <testsuites><testsuite> and a bare <testsuite> root.
    $records = foreach ($suite in @($doc.SelectNodes('//testsuite'))) {
        $suiteName = $suite.GetAttribute('name')
        foreach ($tc in @($suite.SelectNodes('testcase'))) {
            $status  = 'Passed'
            $message = $null

            $failNode = $tc.SelectSingleNode('failure')
            if (-not $failNode) { $failNode = $tc.SelectSingleNode('error') }
            $skipNode = $tc.SelectSingleNode('skipped')

            if ($failNode) {
                $status  = 'Failed'
                $message = $failNode.GetAttribute('message')
            } elseif ($skipNode) {
                $status  = 'Skipped'
                $message = $skipNode.GetAttribute('message')
            }

            # classname (per-testcase) is more specific than the suite name.
            $className = $tc.GetAttribute('classname')
            $recordSuite = if ($className) { $className } else { $suiteName }

            ConvertTo-TestResultRecord `
                -Name     $tc.GetAttribute('name') `
                -Suite    $recordSuite `
                -Status   $status `
                -Duration (ConvertTo-Double $tc.GetAttribute('time')) `
                -Run      $run `
                -Message  $message
        }
    }
    return @($records)
}

<#
.SYNOPSIS
    Parse a single JSON file into normalized test-result records.

.DESCRIPTION
    Accepts either a bare JSON array of test objects, or an object of the form
    { "run": "<name>", "tests": [ ... ] }. Each test object supports:
        name      (required)  - test case name
        status    (required)  - passed/failed/skipped (any common spelling)
        suite     (optional)  - suite/class name (alias: classname)
        duration  (optional)  - seconds (number or numeric string)
        message   (optional)  - failure/skip detail
#>
function Import-JsonResult {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "JSON result file not found: '$Path'."
    }

    try {
        $data = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    } catch {
        throw "Failed to parse JSON '$Path': $($_.Exception.Message)"
    }

    $run = [System.IO.Path]::GetFileName($Path)
    $isArray = $data -is [System.Array]

    if ($isArray) {
        $tests = $data
    } elseif ($data.PSObject.Properties.Name -contains 'tests') {
        $tests = $data.tests
        if ($data.PSObject.Properties.Name -contains 'run' -and $data.run) {
            $run = [string]$data.run
        }
    } else {
        throw "JSON '$Path' must be an array of tests or an object with a 'tests' array."
    }

    $records = foreach ($t in @($tests)) {
        $names = $t.PSObject.Properties.Name
        if ($names -notcontains 'name')   { throw "JSON '$Path': a test entry is missing the required 'name' field." }
        if ($names -notcontains 'status') { throw "JSON '$Path': test '$($t.name)' is missing the required 'status' field." }

        $suite = $null
        if ($names -contains 'suite' -and $t.suite)         { $suite = [string]$t.suite }
        elseif ($names -contains 'classname' -and $t.classname) { $suite = [string]$t.classname }

        $message = $null
        if ($names -contains 'message') { $message = [string]$t.message }

        $duration = 0.0
        if ($names -contains 'duration') { $duration = ConvertTo-Double $t.duration }

        ConvertTo-TestResultRecord `
            -Name     ([string]$t.name) `
            -Suite    $suite `
            -Status   (ConvertTo-NormalizedStatus -Raw ([string]$t.status)) `
            -Duration $duration `
            -Run      $run `
            -Message  $message
    }
    return @($records)
}

<#
.SYNOPSIS
    Parse one test result file, dispatching on its extension.
#>
function Import-TestResultFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Test result file not found: '$Path'."
    }

    $ext = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    switch ($ext) {
        '.xml'  { return Import-JUnitResult -Path $Path }
        '.json' { return Import-JsonResult  -Path $Path }
        default {
            throw "Unsupported test result file type '$ext' for '$Path'. Supported: .xml (JUnit), .json."
        }
    }
}

<#
.SYNOPSIS
    Load every result file under one or more paths (files, directories, or globs).

.DESCRIPTION
    Directories are searched recursively for *.xml and *.json. The combined,
    flat list of records is returned. Files are processed in a stable, sorted
    order so output is deterministic.
#>
function Import-TestResultSet {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Path)

    $files = [System.Collections.Generic.List[string]]::new()
    foreach ($p in $Path) {
        if (Test-Path -LiteralPath $p -PathType Container) {
            Get-ChildItem -LiteralPath $p -File -Recurse |
                Where-Object { $_.Extension -in '.xml', '.json' } |
                Sort-Object FullName |
                ForEach-Object { $files.Add($_.FullName) }
        } elseif (Test-Path -LiteralPath $p -PathType Leaf) {
            $files.Add((Resolve-Path -LiteralPath $p).Path)
        } else {
            # Treat anything else as a wildcard/glob pattern.
            $matched = @(Get-ChildItem -Path $p -File -ErrorAction SilentlyContinue | Sort-Object FullName)
            if ($matched.Count -eq 0) { throw "No test result files matched '$p'." }
            $matched | ForEach-Object { $files.Add($_.FullName) }
        }
    }

    if ($files.Count -eq 0) {
        throw "No test result files (*.xml, *.json) found under: $($Path -join ', ')."
    }

    $all = foreach ($f in $files) { Import-TestResultFile -Path $f }
    return @($all)
}

# --- Aggregation -------------------------------------------------------------

<#
.SYNOPSIS
    Identify flaky tests: those that PASSED in at least one run and FAILED in at
    least one other run across the aggregated set.
#>
function Get-FlakyTest {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Result)

    $flaky = foreach ($group in ($Result | Group-Object -Property FullName)) {
        $passed  = @($group.Group | Where-Object { $_.Status -eq 'Passed' }).Count
        $failed  = @($group.Group | Where-Object { $_.Status -eq 'Failed' }).Count
        $skipped = @($group.Group | Where-Object { $_.Status -eq 'Skipped' }).Count
        if ($passed -gt 0 -and $failed -gt 0) {
            [pscustomobject]@{
                FullName = $group.Name
                Passed   = $passed
                Failed   = $failed
                Skipped  = $skipped
                Runs     = $group.Count
            }
        }
    }
    return @($flaky | Sort-Object FullName)
}

<#
.SYNOPSIS
    Compute aggregate totals and flaky tests over all result records.
#>
function Get-AggregateSummary {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Result)

    $passed  = @($Result | Where-Object { $_.Status -eq 'Passed' }).Count
    $failed  = @($Result | Where-Object { $_.Status -eq 'Failed' }).Count
    $skipped = @($Result | Where-Object { $_.Status -eq 'Skipped' }).Count
    $total   = @($Result).Count

    $sum = ($Result | Measure-Object -Property Duration -Sum).Sum
    $duration = if ($null -eq $sum) { 0.0 } else { [double]$sum }

    $runs = @($Result | Select-Object -ExpandProperty Run -Unique).Count

    # Pass rate excludes skipped tests (the conventional CI definition).
    $decided  = $passed + $failed
    $passRate = if ($decided -gt 0) { [math]::Round(($passed / $decided) * 100, 1) } else { 100.0 }

    [pscustomobject]@{
        Passed   = $passed
        Failed   = $failed
        Skipped  = $skipped
        Total    = $total
        Duration = $duration
        Runs     = $runs
        PassRate = $passRate
        Flaky    = (Get-FlakyTest -Result $Result)
    }
}

# --- Rendering ---------------------------------------------------------------

<#
.SYNOPSIS
    Render an aggregate summary object as GitHub-flavoured markdown.
#>
function Format-MarkdownSummary {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Summary)

    $durationText = '{0:F2}s' -f $Summary.Duration
    $passRateText = '{0:F1}%' -f $Summary.PassRate

    # NOTE: each '-f' expression is wrapped in its own parentheses. Without them
    # the comma in `.Add('...{0}...{1}...' -f $a, $b)` would bind to the method
    # call (two arguments) instead of the -f operator's argument list.
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('# Test Results Summary')
    $lines.Add('')
    $lines.Add(('Aggregated **{0}** test result(s) across **{1}** run(s).' -f $Summary.Total, $Summary.Runs))
    $lines.Add('')
    $lines.Add('| Result | Count |')
    $lines.Add('| --- | --- |')
    $lines.Add(('| Passed | {0} |'  -f $Summary.Passed))
    $lines.Add(('| Failed | {0} |'  -f $Summary.Failed))
    $lines.Add(('| Skipped | {0} |' -f $Summary.Skipped))
    $lines.Add(('| Total | {0} |'   -f $Summary.Total))
    $lines.Add('')
    $lines.Add(('Total duration: **{0}**' -f $durationText))
    $lines.Add(('Pass rate: **{0}**' -f $passRateText))
    $lines.Add('')
    $lines.Add('## Flaky Tests')
    $lines.Add('')

    $flaky = @($Summary.Flaky)
    if ($flaky.Count -eq 0) {
        $lines.Add('No flaky tests detected.')
    } else {
        $lines.Add(('{0} test(s) passed in some runs and failed in others:' -f $flaky.Count))
        $lines.Add('')
        $lines.Add('| Test | Passed | Failed | Skipped | Runs |')
        $lines.Add('| --- | --- | --- | --- | --- |')
        foreach ($f in $flaky) {
            $lines.Add(('| {0} | {1} | {2} | {3} | {4} |' -f $f.FullName, $f.Passed, $f.Failed, $f.Skipped, $f.Runs))
        }
    }

    return ($lines -join "`n")
}
