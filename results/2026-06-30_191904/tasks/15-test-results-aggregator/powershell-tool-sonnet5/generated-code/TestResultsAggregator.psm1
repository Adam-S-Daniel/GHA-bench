<#
    TestResultsAggregator.psm1

    Parses JUnit-XML and JSON test result files, aggregates them across
    multiple files (each file represents one "run" - e.g. one cell of a
    CI build matrix), computes pass/fail/skip totals and duration, detects
    flaky tests (a test that passed in at least one run and failed in at
    least one other run), and renders a GitHub Actions job-summary-flavored
    Markdown report.

    Every parsed test case is normalized to the same shape so downstream
    functions (summary, flaky detection, markdown) don't need to know which
    file format a result originally came from:

        [PSCustomObject]@{
            Source          = 'run1-junit.xml'   # file the record came from (one run/matrix cell)
            Format          = 'JUnit' | 'Json'
            Suite           = 'AuthService'
            Name            = 'test_login'
            FullName        = 'AuthService.test_login'
            Status          = 'Passed' | 'Failed' | 'Skipped'
            DurationSeconds = 0.5
            Message         = $null | 'AssertionError: ...'
        }
#>

Set-StrictMode -Version Latest

function Get-PropertyValueOrDefault {
    <#
        .SYNOPSIS
        Safely reads an optional property from a PSCustomObject (e.g. one
        produced by ConvertFrom-Json), returning a default when the property
        is absent. Needed because Set-StrictMode -Version Latest throws when
        referencing a property that does not exist on the object.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string]$PropertyName,

        $Default = $null
    )

    if ($InputObject.PSObject.Properties.Name -contains $PropertyName) {
        return $InputObject.$PropertyName
    }
    return $Default
}

function ConvertFrom-JUnitXml {
    <#
        .SYNOPSIS
        Parses a JUnit-style XML test result file into normalized test records.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "JUnit XML file not found: '$Path'."
    }

    try {
        [xml]$xml = Get-Content -LiteralPath $Path -Raw
    }
    catch {
        throw "Failed to parse JUnit XML file '$Path': $($_.Exception.Message)"
    }

    $testCaseNodes = $xml.SelectNodes('//testcase')
    if (-not $testCaseNodes -or $testCaseNodes.Count -eq 0) {
        throw "JUnit XML file '$Path' contains no <testcase> elements."
    }

    $source = Split-Path -Leaf $Path
    # Using a List[object] (rather than "$x = foreach (...) {...}") sidesteps
    # PowerShell's single-item array collapsing when a file has exactly one
    # <testcase>, so callers always get a real, flat array back.
    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($node in $testCaseNodes) {
        $suite = if ($node.HasAttribute('classname')) { $node.GetAttribute('classname') } else { $node.ParentNode.GetAttribute('name') }
        $name = $node.GetAttribute('name')
        if ([string]::IsNullOrEmpty($name)) {
            throw "JUnit XML file '$Path' contains a <testcase> with no 'name' attribute."
        }

        $duration = 0.0
        if ($node.HasAttribute('time')) {
            [void][double]::TryParse($node.GetAttribute('time'), [ref]$duration)
        }

        $status = 'Passed'
        $message = $null
        $failureNode = $node.SelectSingleNode('failure')
        if (-not $failureNode) { $failureNode = $node.SelectSingleNode('error') }
        $skippedNode = $node.SelectSingleNode('skipped')
        if ($failureNode) {
            $status = 'Failed'
            $message = if ($failureNode.HasAttribute('message')) { $failureNode.GetAttribute('message') } else { $null }
        }
        elseif ($skippedNode) {
            $status = 'Skipped'
            $message = if ($skippedNode.HasAttribute('message')) { $skippedNode.GetAttribute('message') } else { $null }
        }

        $results.Add([PSCustomObject]@{
            Source          = $source
            Format          = 'JUnit'
            Suite           = $suite
            Name            = $name
            FullName        = "$suite.$name"
            Status          = $status
            DurationSeconds = $duration
            Message         = $message
        })
    }

    return , $results.ToArray()
}

function ConvertFrom-JsonTestResults {
    <#
        .SYNOPSIS
        Parses a custom JSON test result file into normalized test records.

        .DESCRIPTION
        Expected schema:
        {
          "suite": "SuiteName",
          "tests": [
            { "name": "test_x", "status": "passed|failed|skipped", "duration": 0.5, "message": "optional" }
          ]
        }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "JSON test result file not found: '$Path'."
    }

    try {
        $raw = Get-Content -LiteralPath $Path -Raw
        $data = $raw | ConvertFrom-Json
    }
    catch {
        throw "Failed to parse JSON test result file '$Path': $($_.Exception.Message)"
    }

    $suite = Get-PropertyValueOrDefault -InputObject $data -PropertyName 'suite'
    if (-not $suite) {
        throw "JSON test result file '$Path' is missing the required 'suite' field."
    }
    $tests = Get-PropertyValueOrDefault -InputObject $data -PropertyName 'tests'
    if (-not $tests) {
        throw "JSON test result file '$Path' is missing the required 'tests' array."
    }

    $source = Split-Path -Leaf $Path

    $validStatuses = @('passed', 'failed', 'skipped')
    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($test in $tests) {
        $name = Get-PropertyValueOrDefault -InputObject $test -PropertyName 'name'
        if (-not $name) {
            throw "JSON test result file '$Path' contains a test entry with no 'name' field."
        }
        $statusValue = Get-PropertyValueOrDefault -InputObject $test -PropertyName 'status'
        $statusRaw = "$statusValue".ToLowerInvariant()
        if ($statusRaw -notin $validStatuses) {
            throw "JSON test result file '$Path' has test '$name' with unrecognized status '$statusValue'. Expected one of: $($validStatuses -join ', ')."
        }
        $duration = Get-PropertyValueOrDefault -InputObject $test -PropertyName 'duration' -Default 0.0

        $results.Add([PSCustomObject]@{
            Source          = $source
            Format          = 'Json'
            Suite           = $suite
            Name            = $name
            FullName        = "$suite.$name"
            Status          = (Get-Culture).TextInfo.ToTitleCase($statusRaw)
            DurationSeconds = [double]$duration
            Message         = Get-PropertyValueOrDefault -InputObject $test -PropertyName 'message'
        })
    }

    return , $results.ToArray()
}

function Import-TestResultFile {
    <#
        .SYNOPSIS
        Dispatches to the correct parser based on file extension.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    # Capture into a local variable before returning it (rather than
    # `return ConvertFrom-JUnitXml ...`): PowerShell relays a nested call's
    # output stream verbatim through a bare `return <call-expr>`, which would
    # preserve the leaf parser's own unary-comma array protection all the way
    # up. Assigning to a variable first forces a real array value that `return`
    # then enumerates normally, so results from multiple files flatten
    # correctly in Get-AggregatedTestResults.
    $parsed = switch ([System.IO.Path]::GetExtension($Path).ToLowerInvariant()) {
        '.xml' { ConvertFrom-JUnitXml -Path $Path }
        '.json' { ConvertFrom-JsonTestResults -Path $Path }
        default { throw "Unsupported test result file extension for '$Path'. Supported extensions: .xml (JUnit), .json." }
    }
    return $parsed
}

function Get-AggregatedTestResults {
    <#
        .SYNOPSIS
        Reads every *.xml/*.json test result file in a directory and returns the
        combined, normalized list of test records (simulating a matrix build
        where each file is the output of one matrix cell/run).
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Test results path '$Path' does not exist or is not a directory."
    }

    $files = Get-ChildItem -LiteralPath $Path -File -Include '*.xml', '*.json' -Recurse |
        Sort-Object -Property Name

    if (-not $files -or $files.Count -eq 0) {
        throw "No test result files (*.xml, *.json) found in '$Path'."
    }

    $allResults = [System.Collections.Generic.List[object]]::new()
    foreach ($file in $files) {
        # Force array context per-file: a file with exactly one <testcase>/test
        # entry would otherwise collapse to a scalar and get added as one item
        # instead of being flattened into $allResults.
        $fileResults = @(Import-TestResultFile -Path $file.FullName)
        $allResults.AddRange($fileResults)
    }

    return , $allResults.ToArray()
}

function Get-TestResultSummary {
    <#
        .SYNOPSIS
        Computes totals (passed/failed/skipped/duration) across a set of
        normalized test records.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Results
    )

    $passed = @($Results | Where-Object { $_.Status -eq 'Passed' }).Count
    $failed = @($Results | Where-Object { $_.Status -eq 'Failed' }).Count
    $skipped = @($Results | Where-Object { $_.Status -eq 'Skipped' }).Count
    $durationSum = ($Results | Measure-Object -Property DurationSeconds -Sum).Sum
    if (-not $durationSum) { $durationSum = 0.0 }
    $runCount = @($Results | Select-Object -ExpandProperty Source -Unique).Count

    [PSCustomObject]@{
        Total           = $Results.Count
        Passed          = $passed
        Failed          = $failed
        Skipped         = $skipped
        DurationSeconds = [math]::Round($durationSum, 2)
        RunCount        = $runCount
    }
}

function Find-FlakyTest {
    <#
        .SYNOPSIS
        Identifies flaky tests: tests that passed in at least one run and
        failed in at least one other run.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Results
    )

    $flaky = foreach ($group in ($Results | Group-Object -Property FullName)) {
        $statuses = $group.Group.Status
        $passCount = @($statuses | Where-Object { $_ -eq 'Passed' }).Count
        $failCount = @($statuses | Where-Object { $_ -eq 'Failed' }).Count
        $skipCount = @($statuses | Where-Object { $_ -eq 'Skipped' }).Count

        if ($passCount -gt 0 -and $failCount -gt 0) {
            [PSCustomObject]@{
                FullName  = $group.Name
                Suite     = $group.Group[0].Suite
                Name      = $group.Group[0].Name
                PassCount = $passCount
                FailCount = $failCount
                SkipCount = $skipCount
            }
        }
    }

    $flaky = @($flaky | Sort-Object -Property FullName)
    return , $flaky
}

function New-TestSummaryMarkdown {
    <#
        .SYNOPSIS
        Renders a Markdown report suitable for a GitHub Actions job summary
        ($GITHUB_STEP_SUMMARY).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Summary,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$FlakyTests
    )

    $durationText = '{0:N2}s' -f $Summary.DurationSeconds

    $lines = New-Object System.Collections.Generic.List[string]
    [void]$lines.Add('## 🧪 Test Results Summary')
    [void]$lines.Add('')
    [void]$lines.Add("**Total:** $($Summary.Total)  **Passed:** $($Summary.Passed) ✅  **Failed:** $($Summary.Failed) ❌  **Skipped:** $($Summary.Skipped) ⏭️  **Duration:** $durationText")
    [void]$lines.Add('')
    [void]$lines.Add('| Status | Count |')
    [void]$lines.Add('|---|---|')
    [void]$lines.Add("| ✅ Passed | $($Summary.Passed) |")
    [void]$lines.Add("| ❌ Failed | $($Summary.Failed) |")
    [void]$lines.Add("| ⏭️ Skipped | $($Summary.Skipped) |")
    [void]$lines.Add('')
    [void]$lines.Add('### Flaky Tests')
    [void]$lines.Add('')

    if ($FlakyTests.Count -eq 0) {
        [void]$lines.Add("No flaky tests detected across $($Summary.RunCount) run(s).")
    }
    else {
        [void]$lines.Add("⚠️ **$($FlakyTests.Count) flaky test(s) detected** (passed in some runs, failed in others):")
        [void]$lines.Add('')
        [void]$lines.Add('| Test | Passed | Failed | Skipped |')
        [void]$lines.Add('|---|---|---|---|')
        foreach ($test in $FlakyTests) {
            [void]$lines.Add("| $($test.FullName) | $($test.PassCount) | $($test.FailCount) | $($test.SkipCount) |")
        }
    }

    return ($lines -join "`n")
}

Export-ModuleMember -Function @(
    'ConvertFrom-JUnitXml',
    'ConvertFrom-JsonTestResults',
    'Import-TestResultFile',
    'Get-AggregatedTestResults',
    'Get-TestResultSummary',
    'Find-FlakyTest',
    'New-TestSummaryMarkdown'
)
