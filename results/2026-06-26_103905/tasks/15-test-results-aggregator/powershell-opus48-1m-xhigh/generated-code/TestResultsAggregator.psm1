<#
.SYNOPSIS
    Test Results Aggregator — parses JUnit XML and JSON test result files, aggregates
    them across a matrix build, detects flaky tests, and renders a markdown summary
    suitable for a GitHub Actions job summary.

.DESCRIPTION
    The module exposes small, individually testable functions:

        ConvertFrom-JUnitXml        Parse one JUnit XML file  -> normalized results
        ConvertFrom-TestResultJson  Parse one JSON file       -> normalized results
        Import-TestResultFile       Dispatch by extension     -> normalized results
        Get-TestResultFile          Enumerate input files (dir / glob / file list)
        Get-TestResultSummary       Aggregate results -> totals + flaky tests
        New-MarkdownSummary         Render the summary as GitHub-flavored markdown
        Format-MetricsBlock         Render machine-readable KEY=VALUE lines (CI asserts)
        Invoke-TestResultsAggregator  Orchestrate the whole pipeline

    A "normalized test result" is a PSCustomObject with these properties:
        Suite      - source/suite label (used for grouping & display)
        ClassName  - test class (may be empty)
        Name       - test case name
        TestId     - stable identity used for flaky detection ("ClassName.Name")
        Status     - one of 'passed' | 'failed' | 'skipped'
        Duration   - seconds (double)
        Message    - failure / skip message (may be empty)
        SourceFile - originating file path

    All numeric parsing/formatting uses InvariantCulture so the script behaves the
    same on runners with comma decimal separators (e.g. de-DE).
#>

Set-StrictMode -Version Latest

# Canonical status values.
$script:PASSED  = 'passed'
$script:FAILED  = 'failed'
$script:SKIPPED = 'skipped'

#region Internal helpers --------------------------------------------------------

function ConvertTo-InvariantDouble {
    # Parse a string into a double using InvariantCulture, then (as a fallback)
    # the current culture. Empty/missing values become 0.0. Never throws.
    [CmdletBinding()]
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return [double]0 }

    $parsed = [double]0
    $inv    = [System.Globalization.CultureInfo]::InvariantCulture
    if ([double]::TryParse($Value, [System.Globalization.NumberStyles]::Float, $inv, [ref]$parsed)) {
        return $parsed
    }
    if ([double]::TryParse($Value, [ref]$parsed)) { return $parsed }
    return [double]0
}

function Format-InvariantDuration {
    # Format a double as a fixed 2-decimal string regardless of host culture.
    param([double]$Seconds)
    return $Seconds.ToString('0.00', [System.Globalization.CultureInfo]::InvariantCulture)
}

function ConvertTo-NormalizedStatus {
    # Map the many spellings test frameworks emit onto our 3 canonical statuses.
    param([string]$Raw)

    $value = ("$Raw").Trim().ToLowerInvariant()
    switch ($value) {
        { $_ -in @('passed', 'pass', 'success', 'ok', 'succeeded') } { return $script:PASSED }
        { $_ -in @('failed', 'fail', 'failure', 'error', 'errored', 'broken') } { return $script:FAILED }
        { $_ -in @('skipped', 'skip', 'ignored', 'pending', 'disabled', 'notrun') } { return $script:SKIPPED }
        default {
            throw "Unrecognized test status '$Raw'. Expected one of passed/failed/skipped (or common aliases)."
        }
    }
}

function New-TestResult {
    # Factory for the normalized result object so every parser produces an identical shape.
    param(
        [string]$Suite,
        [string]$ClassName,
        [string]$Name,
        [string]$Status,
        [double]$Duration,
        [string]$Message,
        [string]$SourceFile
    )

    $testId = if ([string]::IsNullOrWhiteSpace($ClassName)) { $Name } else { "$ClassName.$Name" }

    [PSCustomObject]@{
        Suite      = $Suite
        ClassName  = $ClassName
        Name       = $Name
        TestId     = $testId
        Status     = $Status
        Duration   = $Duration
        Message    = $Message
        SourceFile = $SourceFile
    }
}

#endregion

#region Parsers ----------------------------------------------------------------

function ConvertFrom-JUnitXml {
    <#
    .SYNOPSIS
        Parse a JUnit XML file (or raw content) into normalized test result objects.
    .DESCRIPTION
        Handles both a <testsuites> root and a bare <testsuite> root. A testcase is
        classified as:
            failed  - if it has a <failure> or <error> child
            skipped - if it has a <skipped> child
            passed  - otherwise
    #>
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Path', Position = 0)]
        [string]$Path,

        [Parameter(Mandatory, ParameterSetName = 'Content')]
        [string]$Content
    )

    if ($PSCmdlet.ParameterSetName -eq 'Path') {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            throw "JUnit XML file not found: '$Path'"
        }
        $Content    = Get-Content -LiteralPath $Path -Raw
        $sourceFile = (Resolve-Path -LiteralPath $Path).Path
        $sourceName = [System.IO.Path]::GetFileName($sourceFile)
    }
    else {
        $sourceFile = '<content>'
        $sourceName = '<content>'
    }

    # Parse defensively so malformed XML produces a clear, file-scoped error.
    $doc = [System.Xml.XmlDocument]::new()
    try {
        $doc.LoadXml($Content)
    }
    catch {
        throw "Failed to parse JUnit XML '$sourceFile': $($_.Exception.Message)"
    }

    # Default suite label: <testsuites name> / <testsuite name> / file name.
    $root      = $doc.DocumentElement
    $suiteName = if ($root -and $root.HasAttribute('name') -and $root.GetAttribute('name')) {
        $root.GetAttribute('name')
    } else {
        $sourceName
    }

    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($case in $doc.SelectNodes('//testcase')) {
        $className = if ($case.HasAttribute('classname')) { $case.GetAttribute('classname') } else { '' }
        $name      = if ($case.HasAttribute('name')) { $case.GetAttribute('name') } else { '' }
        $duration  = ConvertTo-InvariantDouble $case.GetAttribute('time')

        $failureNode = $case.SelectSingleNode('failure')
        $errorNode   = $case.SelectSingleNode('error')
        $skippedNode = $case.SelectSingleNode('skipped')

        if ($failureNode -or $errorNode) {
            $status  = $script:FAILED
            $node    = if ($failureNode) { $failureNode } else { $errorNode }
            $message = $node.GetAttribute('message')
        }
        elseif ($skippedNode) {
            $status  = $script:SKIPPED
            $message = $skippedNode.GetAttribute('message')
        }
        else {
            $status  = $script:PASSED
            $message = ''
        }

        # Prefer the nearest enclosing <testsuite name> when present.
        $caseSuite = $suiteName
        $parent    = $case.ParentNode
        if ($parent -and $parent.LocalName -eq 'testsuite' -and $parent.HasAttribute('name') -and $parent.GetAttribute('name')) {
            $caseSuite = $parent.GetAttribute('name')
        }

        $results.Add((New-TestResult -Suite $caseSuite -ClassName $className -Name $name `
            -Status $status -Duration $duration -Message $message -SourceFile $sourceFile))
    }

    return $results.ToArray()
}

function ConvertFrom-TestResultJson {
    <#
    .SYNOPSIS
        Parse a JSON test result file (or raw content) into normalized result objects.
    .DESCRIPTION
        Accepts either an object with a `tests` array or a bare top-level array.
        Each test entry may use `duration` or `time` for seconds, and any of the
        common status spellings (passed/pass/success, failed/fail/error, skipped/skip...).
    #>
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Path', Position = 0)]
        [string]$Path,

        [Parameter(Mandatory, ParameterSetName = 'Content')]
        [string]$Content
    )

    if ($PSCmdlet.ParameterSetName -eq 'Path') {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            throw "JSON test result file not found: '$Path'"
        }
        $Content    = Get-Content -LiteralPath $Path -Raw
        $sourceFile = (Resolve-Path -LiteralPath $Path).Path
        $sourceName = [System.IO.Path]::GetFileName($sourceFile)
    }
    else {
        $sourceFile = '<content>'
        $sourceName = '<content>'
    }

    try {
        $data = $Content | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Failed to parse JSON '$sourceFile': $($_.Exception.Message)"
    }

    # Normalize to: a suite name + an array of test entries.
    if ($data -is [System.Array]) {
        $suiteName = $sourceName
        $tests     = $data
    }
    elseif ($null -ne $data -and ($data.PSObject.Properties.Name -contains 'tests')) {
        $suiteName = if ($data.PSObject.Properties.Name -contains 'name' -and $data.name) { [string]$data.name } else { $sourceName }
        $tests     = @($data.tests)
    }
    else {
        throw "Invalid JSON test result '$sourceFile': expected a top-level array or an object with a 'tests' array."
    }

    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($t in $tests) {
        $props     = $t.PSObject.Properties.Name
        $name      = if ($props -contains 'name') { [string]$t.name } else { '' }
        $className = if ($props -contains 'classname') { [string]$t.classname } elseif ($props -contains 'class') { [string]$t.class } else { '' }
        $rawStatus = if ($props -contains 'status') { $t.status } elseif ($props -contains 'result') { $t.result } else { $script:PASSED }
        $status    = ConvertTo-NormalizedStatus $rawStatus

        $durRaw   = if ($props -contains 'duration') { $t.duration } elseif ($props -contains 'time') { $t.time } else { 0 }
        $duration = ConvertTo-InvariantDouble ([string]$durRaw)
        $message  = if ($props -contains 'message') { [string]$t.message } else { '' }

        $results.Add((New-TestResult -Suite $suiteName -ClassName $className -Name $name `
            -Status $status -Duration $duration -Message $message -SourceFile $sourceFile))
    }

    return $results.ToArray()
}

function Import-TestResultFile {
    <#
    .SYNOPSIS
        Parse a single test result file, dispatching by extension (.xml -> JUnit, .json -> JSON).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Test result file not found: '$Path'"
    }

    $ext = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    switch ($ext) {
        '.xml'  { return ConvertFrom-JUnitXml -Path $Path }
        '.json' { return ConvertFrom-TestResultJson -Path $Path }
        default  {
            throw "Unsupported test result file extension '$ext' for '$Path'. Supported: .xml (JUnit), .json."
        }
    }
}

function Get-TestResultFile {
    <#
    .SYNOPSIS
        Resolve one or more inputs (directories, globs, or files) to a list of
        .xml/.json test result files.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string[]]$Path,

        [switch]$Recurse
    )

    $files = [System.Collections.Generic.List[string]]::new()

    foreach ($p in $Path) {
        if (Test-Path -LiteralPath $p -PathType Container) {
            # Directory: collect supported files (optionally recursively).
            Get-ChildItem -LiteralPath $p -File -Recurse:$Recurse |
                Where-Object { $_.Extension -in @('.xml', '.json') } |
                Sort-Object FullName |
                ForEach-Object { $files.Add($_.FullName) }
        }
        elseif (Test-Path -LiteralPath $p -PathType Leaf) {
            $files.Add((Resolve-Path -LiteralPath $p).Path)
        }
        else {
            # Treat as a wildcard/glob.
            $matched = @(Get-ChildItem -Path $p -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -in @('.xml', '.json') } |
                Sort-Object FullName)
            if ($matched.Count -eq 0) {
                throw "Input path not found (no matching .xml/.json files): '$p'"
            }
            $matched | ForEach-Object { $files.Add($_.FullName) }
        }
    }

    if ($files.Count -eq 0) {
        throw "No test result files (.xml/.json) found in: $($Path -join ', ')"
    }

    return $files.ToArray()
}

#endregion

#region Aggregation & rendering -------------------------------------------------

function Get-TestResultSummary {
    <#
    .SYNOPSIS
        Aggregate normalized results into totals and detect flaky tests.
    .DESCRIPTION
        A flaky test is one whose TestId both passed (in >=1 run) AND failed (in >=1
        run) across the aggregated files. Overall result is FAILED iff Failed > 0.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowEmptyCollection()]
        [object[]]$Results,

        [int]$FileCount = 0
    )

    $passed  = @($Results | Where-Object Status -eq $script:PASSED).Count
    $failed  = @($Results | Where-Object Status -eq $script:FAILED).Count
    $skipped = @($Results | Where-Object Status -eq $script:SKIPPED).Count
    $total   = $Results.Count

    $duration = [double]0
    foreach ($r in $Results) { $duration += [double]$r.Duration }
    $duration = [math]::Round($duration, 2)

    # Flaky detection: group identical TestIds and look for mixed pass/fail outcomes.
    $flaky = [System.Collections.Generic.List[object]]::new()
    foreach ($group in ($Results | Group-Object -Property TestId)) {
        $g       = $group.Group
        $pCount  = @($g | Where-Object Status -eq $script:PASSED).Count
        $fCount  = @($g | Where-Object Status -eq $script:FAILED).Count
        $sCount  = @($g | Where-Object Status -eq $script:SKIPPED).Count
        if ($pCount -gt 0 -and $fCount -gt 0) {
            $flaky.Add([PSCustomObject]@{
                TestId    = $group.Name
                PassCount = $pCount
                FailCount = $fCount
                SkipCount = $sCount
                Runs      = $group.Count
            })
        }
    }
    $flakySorted = @($flaky | Sort-Object TestId)

    [PSCustomObject]@{
        Total        = $total
        Passed       = $passed
        Failed       = $failed
        Skipped      = $skipped
        Duration     = $duration
        DurationText = (Format-InvariantDuration $duration)
        Flaky        = $flakySorted
        FlakyCount   = $flakySorted.Count
        Files        = $FileCount
        Overall      = if ($failed -gt 0) { 'FAILED' } else { 'PASSED' }
    }
}

function New-MarkdownSummary {
    <#
    .SYNOPSIS
        Render an aggregated summary as GitHub-flavored markdown (job-summary ready).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [object]$Summary,

        [object[]]$Results
    )

    $verdictIcon = if ($Summary.Overall -eq 'PASSED') { '✅' } else { '❌' }
    $notes = [System.Collections.Generic.List[string]]::new()
    if ($Summary.Failed -gt 0)     { $notes.Add("$($Summary.Failed) failed") }
    if ($Summary.FlakyCount -gt 0) { $notes.Add("$($Summary.FlakyCount) flaky") }
    $noteText = if ($notes.Count -gt 0) { ' — ' + ($notes -join ', ') } else { '' }

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('# 🧪 Test Results Summary')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("**Result:** $verdictIcon **$($Summary.Overall)**$noteText")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("Aggregated across **$($Summary.Files)** result file(s).")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('| Metric | Count |')
    [void]$sb.AppendLine('| ------ | ----: |')
    [void]$sb.AppendLine("| ✅ Passed | $($Summary.Passed) |")
    [void]$sb.AppendLine("| ❌ Failed | $($Summary.Failed) |")
    [void]$sb.AppendLine("| ⏭️ Skipped | $($Summary.Skipped) |")
    [void]$sb.AppendLine("| 🧮 Total | $($Summary.Total) |")
    [void]$sb.AppendLine("| ⏱️ Duration | $($Summary.DurationText)s |")
    [void]$sb.AppendLine("| 🔁 Flaky | $($Summary.FlakyCount) |")
    [void]$sb.AppendLine('')

    # Flaky section.
    [void]$sb.AppendLine('## 🔁 Flaky Tests')
    [void]$sb.AppendLine('')
    if ($Summary.FlakyCount -gt 0) {
        [void]$sb.AppendLine('These tests passed in some runs and failed in others:')
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('| Test | ✅ Passed | ❌ Failed | 🧮 Runs |')
        [void]$sb.AppendLine('| ---- | -------: | -------: | -----: |')
        foreach ($f in $Summary.Flaky) {
            [void]$sb.AppendLine("| $($f.TestId) | $($f.PassCount) | $($f.FailCount) | $($f.Runs) |")
        }
    }
    else {
        [void]$sb.AppendLine('_None detected._')
    }

    # Optional per-source breakdown when raw results are provided.
    if ($Results) {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('## 📂 Per-File Breakdown')
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('| Source | ✅ | ❌ | ⏭️ | ⏱️ |')
        [void]$sb.AppendLine('| ------ | -: | -: | -: | -: |')
        foreach ($group in ($Results | Group-Object -Property SourceFile)) {
            $g     = $group.Group
            $p     = @($g | Where-Object Status -eq $script:PASSED).Count
            $f     = @($g | Where-Object Status -eq $script:FAILED).Count
            $s     = @($g | Where-Object Status -eq $script:SKIPPED).Count
            $dur   = [double]0; foreach ($r in $g) { $dur += [double]$r.Duration }
            $label = [System.IO.Path]::GetFileName($group.Name)
            [void]$sb.AppendLine("| $label | $p | $f | $s | $(Format-InvariantDuration $dur)s |")
        }
    }

    return $sb.ToString().TrimEnd() + "`n"
}

function Format-MetricsBlock {
    <#
    .SYNOPSIS
        Render a machine-readable KEY=VALUE block (consumed by the CI assertions).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [object]$Summary
    )

    $flakyTests = if ($Summary.FlakyCount -gt 0) { ($Summary.Flaky.TestId -join ',') } else { '(none)' }

    $lines = @(
        '=== AGGREGATE METRICS ==='
        "FILES_PARSED=$($Summary.Files)"
        "TOTAL_TESTS=$($Summary.Total)"
        "PASSED=$($Summary.Passed)"
        "FAILED=$($Summary.Failed)"
        "SKIPPED=$($Summary.Skipped)"
        "DURATION_SECONDS=$($Summary.DurationText)"
        "FLAKY_COUNT=$($Summary.FlakyCount)"
        "FLAKY_TESTS=$flakyTests"
        "OVERALL=$($Summary.Overall)"
        '=== END METRICS ==='
    )
    return ($lines -join "`n")
}

function Invoke-TestResultsAggregator {
    <#
    .SYNOPSIS
        Full pipeline: resolve input files -> parse -> aggregate -> render.
    .OUTPUTS
        A PSCustomObject with Results, Summary, Markdown and MetricsText.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string[]]$Path,

        [switch]$Recurse
    )

    $files   = Get-TestResultFile -Path $Path -Recurse:$Recurse
    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($file in $files) {
        foreach ($r in (Import-TestResultFile -Path $file)) { $results.Add($r) }
    }

    $resultArray = $results.ToArray()
    $summary     = Get-TestResultSummary -Results $resultArray -FileCount $files.Count

    [PSCustomObject]@{
        Files       = $files
        Results     = $resultArray
        Summary     = $summary
        Markdown    = (New-MarkdownSummary -Summary $summary -Results $resultArray)
        MetricsText = (Format-MetricsBlock -Summary $summary)
    }
}

#endregion

Export-ModuleMember -Function `
    ConvertFrom-JUnitXml, `
    ConvertFrom-TestResultJson, `
    Import-TestResultFile, `
    Get-TestResultFile, `
    Get-TestResultSummary, `
    New-MarkdownSummary, `
    Format-MetricsBlock, `
    Invoke-TestResultsAggregator
