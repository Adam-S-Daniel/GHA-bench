<#
.SYNOPSIS
    Aggregate test results from multiple JUnit XML and JSON files (e.g. a matrix
    build), compute totals, identify flaky tests, and render a GitHub Actions
    job-summary markdown report.

.DESCRIPTION
    This module exposes small, single-purpose functions, each developed
    test-first (red/green TDD):

      Import-JUnitResult            Parse a single JUnit XML file.
      Import-JsonResult             Parse a single JSON results file.
      Import-TestResultFile         Dispatch on extension to the right parser.
      Get-TestAggregate            Aggregate results, compute totals, find flaky.
      New-MarkdownSummary          Render aggregate as markdown.
      Invoke-TestResultsAggregation End-to-end: directory -> markdown file.

    The common in-memory representation for a single test case is a PSCustomObject
    with: Name, Suite, Status ('Passed'|'Failed'|'Skipped'), Duration (seconds).
#>

Set-StrictMode -Version Latest

# Normalise an arbitrary status string from a result file into one of the three
# canonical states. Anything unrecognised is treated as Failed so problems are
# surfaced rather than silently dropped.
function ConvertTo-CanonicalStatus {
    param([string]$Raw)
    switch -Regex ($Raw) {
        '^(pass(ed)?|success|ok)$'        { return 'Passed' }
        '^(skip(ped)?|ignored|disabled)$' { return 'Skipped' }
        default                           { return 'Failed' }
    }
}

function Import-JUnitResult {
    <#
    .SYNOPSIS Parse a JUnit XML file into canonical test-case objects.
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

    # JUnit files may have a <testsuites> root or a bare <testsuite> root.
    $testcases = $doc.SelectNodes('//testcase')
    if ($null -eq $testcases) { return @() }

    $results = foreach ($tc in $testcases) {
        # A testcase is Failed if it has <failure> or <error>, Skipped if it has
        # <skipped>, otherwise Passed.
        $status = 'Passed'
        if ($tc.SelectSingleNode('failure') -or $tc.SelectSingleNode('error')) {
            $status = 'Failed'
        } elseif ($tc.SelectSingleNode('skipped')) {
            $status = 'Skipped'
        }

        $duration = 0.0
        if ($tc.HasAttribute('time')) {
            # JUnit times use invariant (dot) decimal separator.
            [double]::TryParse($tc.GetAttribute('time'),
                [System.Globalization.NumberStyles]::Float,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [ref]$duration) | Out-Null
        }

        $suite = if ($tc.HasAttribute('classname') -and $tc.GetAttribute('classname')) {
            $tc.GetAttribute('classname')
        } elseif ($tc.ParentNode -and $tc.ParentNode.Name -eq 'testsuite') {
            $tc.ParentNode.GetAttribute('name')
        } else { 'default' }

        [pscustomobject]@{
            Name     = $tc.GetAttribute('name')
            Suite    = $suite
            Status   = $status
            Duration = $duration
        }
    }

    return @($results)
}

function Import-JsonResult {
    <#
    .SYNOPSIS Parse a JSON results file into canonical test-case objects.
    .DESCRIPTION
        Expected shape: { "tests": [ { "name", "suite", "status", "duration" } ] }
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "JSON results file not found: $Path"
    }

    try {
        $data = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    } catch {
        throw "Failed to parse JSON '$Path': $($_.Exception.Message)"
    }

    if ($null -eq $data.tests) {
        throw "JSON results file '$Path' is missing a 'tests' array."
    }

    $results = foreach ($t in $data.tests) {
        $duration = 0.0
        if ($null -ne $t.duration) { $duration = [double]$t.duration }

        [pscustomobject]@{
            Name     = [string]$t.name
            Suite    = if ($t.PSObject.Properties.Name -contains 'suite' -and $t.suite) { [string]$t.suite } else { 'default' }
            Status   = ConvertTo-CanonicalStatus ([string]$t.status)
            Duration = $duration
        }
    }

    return @($results)
}

function Import-TestResultFile {
    <#
    .SYNOPSIS Dispatch to the correct parser based on file extension.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $ext = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    switch ($ext) {
        '.xml'  { return Import-JUnitResult -Path $Path }
        '.json' { return Import-JsonResult  -Path $Path }
        default  { throw "Unsupported test result file extension '$ext' for '$Path'. Supported: .xml, .json" }
    }
}

function Get-TestAggregate {
    <#
    .SYNOPSIS Aggregate test-case objects: totals + flaky detection.
    .DESCRIPTION
        A test is identified by "Suite.Name". A test is flaky when, across all
        runs, it has at least one Passed result AND at least one Failed result.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Results)

    $passed = 0; $failed = 0; $skipped = 0; $duration = 0.0

    # Track the set of statuses seen per test key, for flaky detection.
    $statusesByTest = @{}

    foreach ($r in $Results) {
        switch ($r.Status) {
            'Passed'  { $passed++ }
            'Failed'  { $failed++ }
            'Skipped' { $skipped++ }
        }
        $duration += [double]$r.Duration

        $key = "$($r.Suite).$($r.Name)"
        if (-not $statusesByTest.ContainsKey($key)) {
            $statusesByTest[$key] = [System.Collections.Generic.HashSet[string]]::new()
        }
        [void]$statusesByTest[$key].Add($r.Status)
    }

    # Flaky = saw both Passed and Failed for the same test key. Sorted for
    # deterministic output.
    $flaky = @(
        $statusesByTest.Keys |
            Where-Object { $statusesByTest[$_].Contains('Passed') -and $statusesByTest[$_].Contains('Failed') } |
            Sort-Object
    )

    return [pscustomobject]@{
        Total    = $passed + $failed + $skipped
        Passed   = $passed
        Failed   = $failed
        Skipped  = $skipped
        Duration = [math]::Round($duration, 3)
        Flaky    = $flaky
        Tests    = @($Results)
    }
}

function New-MarkdownSummary {
    <#
    .SYNOPSIS Render an aggregate object as GitHub-flavoured markdown.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Aggregate)

    $status = if ($Aggregate.Failed -gt 0) { 'FAILED' }
              elseif ($Aggregate.Flaky.Count -gt 0) { 'PASSED (with flaky tests)' }
              else { 'PASSED' }

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('# Test Results Summary')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("**Overall status: $status**")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('| Metric | Count |')
    [void]$sb.AppendLine('| --- | --- |')
    [void]$sb.AppendLine("| Total | $($Aggregate.Total) |")
    [void]$sb.AppendLine("| Passed | $($Aggregate.Passed) |")
    [void]$sb.AppendLine("| Failed | $($Aggregate.Failed) |")
    [void]$sb.AppendLine("| Skipped | $($Aggregate.Skipped) |")
    # Duration formatted with invariant culture so the decimal point is stable.
    $durStr = $Aggregate.Duration.ToString('0.###', [System.Globalization.CultureInfo]::InvariantCulture)
    [void]$sb.AppendLine("| Duration (s) | $durStr |")
    [void]$sb.AppendLine('')

    [void]$sb.AppendLine('## Flaky Tests')
    [void]$sb.AppendLine('')
    if ($Aggregate.Flaky.Count -eq 0) {
        [void]$sb.AppendLine('No flaky tests detected.')
    } else {
        [void]$sb.AppendLine("Detected $($Aggregate.Flaky.Count) flaky test(s) (passed in some runs, failed in others):")
        [void]$sb.AppendLine('')
        foreach ($f in $Aggregate.Flaky) {
            [void]$sb.AppendLine("- ``$f``")
        }
    }
    [void]$sb.AppendLine('')

    return $sb.ToString()
}

function Invoke-TestResultsAggregation {
    <#
    .SYNOPSIS End-to-end driver: parse all result files under a path, aggregate,
              and write the markdown summary.
    .PARAMETER InputPath
        A directory (all *.xml / *.json beneath it are parsed) or a single file.
    .PARAMETER OutputPath
        Where to write the markdown summary.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$InputPath,
        [Parameter(Mandatory)][string]$OutputPath
    )

    if (-not (Test-Path -LiteralPath $InputPath)) {
        throw "Input path not found: $InputPath"
    }

    # Collect candidate files: either a single file or every supported file in a
    # directory tree.
    if (Test-Path -LiteralPath $InputPath -PathType Container) {
        $files = Get-ChildItem -LiteralPath $InputPath -Recurse -File |
            Where-Object { $_.Extension -in '.xml', '.json' }
    } else {
        $files = @(Get-Item -LiteralPath $InputPath)
    }

    if (-not $files -or @($files).Count -eq 0) {
        throw "No supported test result files (.xml/.json) found under: $InputPath"
    }

    $all = foreach ($f in $files) {
        Write-Verbose "Parsing $($f.FullName)"
        Import-TestResultFile -Path $f.FullName
    }

    $aggregate = Get-TestAggregate -Results @($all)
    $markdown  = New-MarkdownSummary -Aggregate $aggregate

    # Write summary (ensure parent dir exists).
    $outDir = Split-Path -Parent $OutputPath
    if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }
    Set-Content -LiteralPath $OutputPath -Value $markdown -Encoding utf8

    return $aggregate
}

Export-ModuleMember -Function Import-JUnitResult, Import-JsonResult, Import-TestResultFile,
    Get-TestAggregate, New-MarkdownSummary, Invoke-TestResultsAggregation
