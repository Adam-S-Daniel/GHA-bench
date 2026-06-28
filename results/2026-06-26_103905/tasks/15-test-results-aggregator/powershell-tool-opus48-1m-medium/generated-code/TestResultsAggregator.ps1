<#
.SYNOPSIS
    Test Results Aggregator.

.DESCRIPTION
    Parses test result files in multiple formats (JUnit XML and JSON), aggregates
    them across many files (e.g. the legs of a CI matrix build), computes totals,
    detects flaky tests (those that pass in some runs and fail in others) and
    renders a Markdown summary suitable for a GitHub Actions job summary.

    The script is written as a library of small, individually testable functions.
    When dot-sourced it only defines functions; when run directly with -Path it
    performs the full aggregation (see the param block / bottom of the file).

.NOTES
    Normalized test result objects have the shape:
        [pscustomobject]@{ Name; Suite; Status; Duration }
    where Status is one of 'passed', 'failed', 'skipped' and Duration is seconds.
#>

[CmdletBinding()]
param(
    # Directory containing result files, or a single result file. Optional so the
    # script can be safely dot-sourced from the Pester tests without side effects.
    [string]$Path,

    # Where to write the generated Markdown summary.
    [string]$OutputPath = 'test-summary.md'
)

# ---------------------------------------------------------------------------
# Status normalization helper
# ---------------------------------------------------------------------------
function ConvertTo-NormalizedStatus {
    <#
        Maps the many status spellings found across frameworks/formats onto the
        canonical trio passed/failed/skipped. Anything unrecognized is treated as
        failed so problems are never silently counted as successes.
    #>
    param([string]$Status)

    switch -Regex ($Status.Trim().ToLowerInvariant()) {
        '^(passed|pass|success|ok)$'        { return 'passed' }
        '^(failed|fail|failure|error)$'     { return 'failed' }
        '^(skipped|skip|ignored|disabled)$' { return 'skipped' }
        default                             { return 'failed' }
    }
}

# ---------------------------------------------------------------------------
# JUnit XML parser
# ---------------------------------------------------------------------------
function ConvertFrom-JUnitXml {
    <#
    .SYNOPSIS
        Parse a JUnit-style XML file into normalized test result objects.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "JUnit XML file not found: $Path"
    }

    try {
        [xml]$doc = Get-Content -LiteralPath $Path -Raw
    } catch {
        throw "Failed to parse JUnit XML '$Path': $($_.Exception.Message)"
    }

    # A file may use a <testsuites> root or a bare <testsuite>; SelectNodes with
    # the descendant axis finds every <testcase> regardless of nesting depth.
    $cases = $doc.SelectNodes('//testcase')

    foreach ($case in $cases) {
        # Determine status from child elements: <failure>/<error> => failed,
        # <skipped> => skipped, otherwise passed.
        $status = 'passed'
        if ($case.SelectSingleNode('failure') -or $case.SelectSingleNode('error')) {
            $status = 'failed'
        } elseif ($case.SelectSingleNode('skipped')) {
            $status = 'skipped'
        }

        $duration = 0.0
        if ($case.time) {
            # JUnit times are seconds; parse invariantly to avoid locale issues.
            [double]::TryParse($case.time, [System.Globalization.NumberStyles]::Float,
                [System.Globalization.CultureInfo]::InvariantCulture, [ref]$duration) | Out-Null
        }

        [pscustomobject]@{
            Name     = [string]$case.name
            Suite    = if ($case.classname) { [string]$case.classname } else { 'default' }
            Status   = $status
            Duration = $duration
        }
    }
}

# ---------------------------------------------------------------------------
# JSON parser
# ---------------------------------------------------------------------------
function ConvertFrom-TestResultJson {
    <#
    .SYNOPSIS
        Parse a JSON test result file into normalized test result objects.

    .DESCRIPTION
        Accepts either a top-level array of test objects or an object with a
        "tests" property holding the array. Each test object should expose
        name, suite, status and duration.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "JSON result file not found: $Path"
    }

    try {
        $data = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Failed to parse JSON '$Path': $($_.Exception.Message)"
    }

    # Support both shapes: { "tests": [...] } and a bare [...] array.
    $tests = if ($null -ne $data.tests) { $data.tests } else { $data }

    foreach ($t in $tests) {
        $duration = 0.0
        if ($null -ne $t.duration) { $duration = [double]$t.duration }

        [pscustomobject]@{
            Name     = [string]$t.name
            Suite    = if ($t.suite) { [string]$t.suite } else { 'default' }
            Status   = ConvertTo-NormalizedStatus ([string]$t.status)
            Duration = $duration
        }
    }
}

# ---------------------------------------------------------------------------
# Format dispatcher
# ---------------------------------------------------------------------------
function Import-TestResultFile {
    <#
    .SYNOPSIS
        Parse a single result file, dispatching on its extension.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    switch ([System.IO.Path]::GetExtension($Path).ToLowerInvariant()) {
        '.xml'  { return ConvertFrom-JUnitXml -Path $Path }
        '.json' { return ConvertFrom-TestResultJson -Path $Path }
        default {
            throw "Unsupported test result file format '$([System.IO.Path]::GetExtension($Path))' for: $Path"
        }
    }
}

# ---------------------------------------------------------------------------
# Totals
# ---------------------------------------------------------------------------
function Get-TestResultSummary {
    <#
    .SYNOPSIS
        Compute passed/failed/skipped/total counts and total duration.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Results)

    $passed  = @($Results | Where-Object Status -eq 'passed').Count
    $failed  = @($Results | Where-Object Status -eq 'failed').Count
    $skipped = @($Results | Where-Object Status -eq 'skipped').Count
    $duration = ($Results | Measure-Object -Property Duration -Sum).Sum
    if ($null -eq $duration) { $duration = 0 }

    [pscustomobject]@{
        Total    = $Results.Count
        Passed   = $passed
        Failed   = $failed
        Skipped  = $skipped
        # Round to avoid floating point noise in the rendered summary.
        Duration = [math]::Round([double]$duration, 3)
    }
}

# ---------------------------------------------------------------------------
# Flaky test detection
# ---------------------------------------------------------------------------
function Get-FlakyTests {
    <#
    .SYNOPSIS
        Identify flaky tests: those observed both passing and failing.

    .DESCRIPTION
        Groups results by Suite+Name across all runs. A test is flaky when it
        recorded at least one 'passed' and at least one 'failed' outcome. Skips
        are ignored for the purpose of flakiness.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Results)

    $flaky = foreach ($group in $Results | Group-Object { "$($_.Suite)::$($_.Name)" }) {
        $passes = @($group.Group | Where-Object Status -eq 'passed').Count
        $fails  = @($group.Group | Where-Object Status -eq 'failed').Count

        if ($passes -gt 0 -and $fails -gt 0) {
            [pscustomobject]@{
                Name        = $group.Group[0].Name
                Suite       = $group.Group[0].Suite
                PassedCount = $passes
                FailedCount = $fails
                TotalRuns   = $group.Count
            }
        }
    }

    # Always return an array so .Count is reliable even for 0/1 results.
    return @($flaky)
}

# ---------------------------------------------------------------------------
# Markdown rendering
# ---------------------------------------------------------------------------
function New-MarkdownSummary {
    <#
    .SYNOPSIS
        Render an aggregated result set as GitHub-flavored Markdown.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Results)

    $summary = Get-TestResultSummary -Results $Results
    $flaky   = Get-FlakyTests -Results $Results

    # Overall status icon for a quick visual read at the top of the summary.
    $statusIcon = if ($summary.Failed -gt 0) { ':x: Failing' } else { ':white_check_mark: Passing' }

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('## Test Results Summary')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("**Overall:** $statusIcon")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('| Metric | Count |')
    [void]$sb.AppendLine('| --- | ---: |')
    [void]$sb.AppendLine("| Total | $($summary.Total) |")
    [void]$sb.AppendLine("| Passed | $($summary.Passed) |")
    [void]$sb.AppendLine("| Failed | $($summary.Failed) |")
    [void]$sb.AppendLine("| Skipped | $($summary.Skipped) |")
    [void]$sb.AppendLine("| Duration (s) | $($summary.Duration) |")
    [void]$sb.AppendLine()

    [void]$sb.AppendLine('### Flaky Tests')
    [void]$sb.AppendLine()
    if ($flaky.Count -gt 0) {
        [void]$sb.AppendLine('These tests passed in some runs and failed in others:')
        [void]$sb.AppendLine()
        [void]$sb.AppendLine('| Suite | Test | Passed | Failed | Runs |')
        [void]$sb.AppendLine('| --- | --- | ---: | ---: | ---: |')
        foreach ($f in $flaky | Sort-Object Suite, Name) {
            [void]$sb.AppendLine("| $($f.Suite) | $($f.Name) | $($f.PassedCount) | $($f.FailedCount) | $($f.TotalRuns) |")
        }
    } else {
        [void]$sb.AppendLine(':white_check_mark: No flaky tests detected.')
    }
    [void]$sb.AppendLine()

    return $sb.ToString()
}

# ---------------------------------------------------------------------------
# Orchestration / end-to-end entry point
# ---------------------------------------------------------------------------
function Invoke-TestResultsAggregator {
    <#
    .SYNOPSIS
        Aggregate every result file under a path and write a Markdown summary.

    .PARAMETER Path
        A directory (searched recursively for *.xml / *.json) or a single file.

    .PARAMETER OutputPath
        File to write the Markdown summary to.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$OutputPath
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Path not found: $Path"
    }

    # Collect candidate files.
    if (Test-Path -LiteralPath $Path -PathType Container) {
        $files = Get-ChildItem -LiteralPath $Path -Recurse -File |
                 Where-Object { $_.Extension -in '.xml', '.json' }
    } else {
        $files = @(Get-Item -LiteralPath $Path)
    }

    if (-not $files -or @($files).Count -eq 0) {
        throw "No test result files (*.xml, *.json) found under: $Path"
    }

    # Parse and concatenate all results.
    $all = foreach ($file in $files) {
        Write-Verbose "Parsing $($file.FullName)"
        Import-TestResultFile -Path $file.FullName
    }
    $all = @($all)

    $md = New-MarkdownSummary -Results $all
    Set-Content -LiteralPath $OutputPath -Value $md -Encoding utf8

    return $md
}

# ---------------------------------------------------------------------------
# Direct-invocation entry point
# ---------------------------------------------------------------------------
# Only run the aggregation when the script is executed directly with -Path,
# never when it is dot-sourced (in which case $Path is empty). This keeps the
# file usable both as a CLI tool and as a dot-sourced library for Pester.
if ($MyInvocation.InvocationName -ne '.' -and $PSBoundParameters.ContainsKey('Path')) {
    $md = Invoke-TestResultsAggregator -Path $Path -OutputPath $OutputPath
    Write-Host $md

    # When running inside GitHub Actions, append to the job summary too.
    if ($env:GITHUB_STEP_SUMMARY) {
        Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value $md -Encoding utf8
    }
}
