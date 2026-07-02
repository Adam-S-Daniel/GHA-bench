#Requires -Version 7.0
<#
.SYNOPSIS
    Parses, aggregates and summarizes test results from matrix builds.

.DESCRIPTION
    Supports two input formats:
      * JUnit XML  (<testsuites>/<testsuite>/<testcase> with <failure>/<error>/<skipped>)
      * JSON       ({ "suite": "...", "tests": [ { name, classname, status, duration } ] })

    Every parser normalizes results to a single record shape so the
    aggregation and reporting layers never care where a result came from:

        [pscustomobject] @{ Name; ClassName; Suite; Status; Duration; SourceFile }

    Status is one of: Passed, Failed, Skipped. JUnit <error> elements are
    treated as failures (a crashed test is a failed test for reporting).
#>

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# Parsers
# ---------------------------------------------------------------------------

function Assert-FileExists {
    # Shared guard so every parser fails with the same clear message.
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Test result file not found: '$Path'."
    }
}

function ConvertFrom-JUnitXml {
    <#
    .SYNOPSIS
        Parses a JUnit XML report into normalized test result records.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    Assert-FileExists $Path

    try {
        [xml]$doc = Get-Content -LiteralPath $Path -Raw
    }
    catch {
        throw "File '$Path' is not valid JUnit XML: $($_.Exception.Message)"
    }

    # A report may use <testsuites> as root or a single bare <testsuite>.
    $suites = $doc.SelectNodes('//testsuite')
    if ($suites.Count -eq 0) {
        throw "File '$Path' is not valid JUnit XML: no <testsuite> element found."
    }

    foreach ($suite in $suites) {
        foreach ($case in $suite.SelectNodes('testcase')) {
            # Outcome is determined by the child element: none = passed.
            $status = 'Passed'
            if ($case.SelectSingleNode('failure') -or $case.SelectSingleNode('error')) {
                $status = 'Failed'
            }
            elseif ($case.SelectSingleNode('skipped')) {
                $status = 'Skipped'
            }

            [pscustomobject]@{
                Name       = [string]$case.GetAttribute('name')
                ClassName  = [string]$case.GetAttribute('classname')
                Suite      = [string]$suite.GetAttribute('name')
                Status     = $status
                Duration   = ConvertTo-Seconds $case.GetAttribute('time')
                SourceFile = (Get-Item -LiteralPath $Path).FullName
            }
        }
    }
}

function ConvertFrom-JsonTestResult {
    <#
    .SYNOPSIS
        Parses a JSON test report into normalized test result records.
    .DESCRIPTION
        Expected schema:
        { "suite": "name", "tests": [ { "name", "classname", "status", "duration" } ] }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    Assert-FileExists $Path

    try {
        $doc = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    }
    catch {
        throw "File '$Path' is not valid JSON: $($_.Exception.Message)"
    }

    if (-not ($doc.PSObject.Properties.Name -contains 'tests')) {
        throw "File '$Path' is not a recognized JSON test report: missing 'tests' array."
    }

    $suiteName = if ($doc.PSObject.Properties.Name -contains 'suite') { [string]$doc.suite } else { '' }

    foreach ($test in $doc.tests) {
        $status = switch (([string]$test.status).ToLowerInvariant()) {
            'passed'  { 'Passed' }
            'failed'  { 'Failed' }
            'skipped' { 'Skipped' }
            default   { throw "File '$Path' contains an unknown test status '$($test.status)' for test '$($test.name)'." }
        }

        [pscustomobject]@{
            Name       = [string]$test.name
            ClassName  = [string]$test.classname
            Suite      = $suiteName
            Status     = $status
            Duration   = ConvertTo-Seconds $test.duration
            SourceFile = (Get-Item -LiteralPath $Path).FullName
        }
    }
}

function Import-TestResultFile {
    <#
    .SYNOPSIS
        Parses a single result file, dispatching on the file extension.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    switch ([System.IO.Path]::GetExtension($Path).ToLowerInvariant()) {
        '.xml'  { ConvertFrom-JUnitXml -Path $Path }
        '.json' { ConvertFrom-JsonTestResult -Path $Path }
        default { throw "Unsupported test result format '$([System.IO.Path]::GetExtension($Path))' for file '$Path'. Supported: .xml (JUnit), .json." }
    }
}

# ---------------------------------------------------------------------------
# Aggregation
# ---------------------------------------------------------------------------

function Import-TestResultDirectory {
    <#
    .SYNOPSIS
        Parses every .xml and .json result file in a directory (one file per
        matrix leg) and returns the combined normalized records.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        # Optional file-name filter, mainly for tests that share a fixture dir.
        [string[]]$Include = @('*.xml', '*.json')
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Test results directory not found: '$Path'."
    }

    $files = Get-ChildItem -Path $Path -File -Include $Include -Recurse |
        Sort-Object FullName
    if (-not $files) {
        throw "No test result files (*.xml, *.json) found in '$Path'."
    }

    foreach ($file in $files) {
        Import-TestResultFile -Path $file.FullName
    }
}

function Get-TestResultSummary {
    <#
    .SYNOPSIS
        Computes totals and flaky tests from normalized result records.
    .DESCRIPTION
        A test is *flaky* when the same test identity (ClassName.Name) has at
        least one Passed and at least one Failed record across the aggregated
        runs. Skipped records never influence flakiness.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Results
    )

    # Flaky detection: group by test identity and look for mixed outcomes.
    $flaky = $Results |
        Group-Object { if ($_.ClassName) { "$($_.ClassName).$($_.Name)" } else { $_.Name } } |
        ForEach-Object {
            $passed = @($_.Group | Where-Object Status -eq 'Passed').Count
            $failed = @($_.Group | Where-Object Status -eq 'Failed').Count
            if ($passed -gt 0 -and $failed -gt 0) {
                [pscustomobject]@{ Name = $_.Name; Passed = $passed; Failed = $failed }
            }
        } |
        Sort-Object Name

    # Measure-Object emits nothing for an empty pipeline, so guard the sum.
    $durationSum = if ($Results.Count -gt 0) {
        ($Results | Measure-Object -Property Duration -Sum).Sum
    } else { 0.0 }

    [pscustomobject]@{
        Total      = $Results.Count
        Passed     = @($Results | Where-Object Status -eq 'Passed').Count
        Failed     = @($Results | Where-Object Status -eq 'Failed').Count
        Skipped    = @($Results | Where-Object Status -eq 'Skipped').Count
        Duration   = [math]::Round($durationSum, 2)
        FileCount  = @($Results | Select-Object -ExpandProperty SourceFile -Unique).Count
        FlakyTests = @($flaky)
    }
}

# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------

function New-MarkdownSummary {
    <#
    .SYNOPSIS
        Renders a summary object as GitHub-flavored markdown suitable for
        appending to $GITHUB_STEP_SUMMARY.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Summary
    )

    # Invariant culture so '4.25s' renders identically on every runner locale.
    $duration = $Summary.Duration.ToString('0.##', [System.Globalization.CultureInfo]::InvariantCulture)

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('# 🧪 Test Results Summary')
    $lines.Add('')
    $lines.Add('| Metric | Count |')
    $lines.Add('| ------ | ----- |')
    $lines.Add("| ✅ Passed | $($Summary.Passed) |")
    $lines.Add("| ❌ Failed | $($Summary.Failed) |")
    $lines.Add("| ⏭️ Skipped | $($Summary.Skipped) |")
    $lines.Add("| **Total** | **$($Summary.Total)** |")
    $lines.Add('')
    $lines.Add("**Duration:** ${duration}s across $($Summary.FileCount) result file(s)")
    $lines.Add('')

    if ($Summary.FlakyTests.Count -gt 0) {
        $lines.Add('## ⚠️ Flaky Tests')
        $lines.Add('')
        $lines.Add('Tests that passed in some runs and failed in others:')
        $lines.Add('')
        $lines.Add('| Test | Passed | Failed |')
        $lines.Add('| ---- | ------ | ------ |')
        foreach ($t in $Summary.FlakyTests) {
            $lines.Add("| $($t.Name) | $($t.Passed) | $($t.Failed) |")
        }
    }
    else {
        $lines.Add('✨ No flaky tests detected.')
    }

    return ($lines -join "`n") + "`n"
}

function ConvertTo-Seconds {
    # Durations in fixtures/reports are strings; parse with the invariant
    # culture so '0.25' works regardless of the machine locale.
    param($Value)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return 0.0 }
    return [double]::Parse([string]$Value, [System.Globalization.CultureInfo]::InvariantCulture)
}

Export-ModuleMember -Function @(
    'ConvertFrom-JUnitXml'
    'ConvertFrom-JsonTestResult'
    'Import-TestResultFile'
    'Import-TestResultDirectory'
    'Get-TestResultSummary'
    'New-MarkdownSummary'
)
