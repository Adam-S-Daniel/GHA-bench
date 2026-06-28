# Integration tests that run the workflow end-to-end with nektos/act.
#
# For each test case we:
#   1. build a throwaway git repo containing the project files + that case's
#      test-result fixtures,
#   2. run `act push --rm` against the real workflow,
#   3. append the full act output to act-result.txt (a required artifact),
#   4. assert act exited 0, that the job succeeded, and that the aggregated
#      output matches the EXACT known-good values for that case's input.
#
# Run with:  Invoke-Pester -Path tests/Workflow.Act.Tests.ps1
#
# Requires Docker + act (both pre-installed in this environment) and the custom
# act-ubuntu-pwsh image referenced by ./.actrc.

# --- Test-case table (evaluated at discovery time so -ForEach can see it) ------

# Each case provides the files to drop into the repo's test-results/ directory
# and the exact substrings that MUST appear in the act output for that input.
$script:Cases = @(
    @{
        Name        = 'mixed-matrix-with-flaky'
        Description = 'JUnit + JSON across two matrix legs; test_logout is flaky'
        Files       = @{
            'run1-junit.xml' = @'
<testsuites>
  <testsuite name="ApiTests" tests="4" failures="1" skipped="1" time="1.20">
    <testcase name="test_login"  classname="ApiTests" time="0.50"/>
    <testcase name="test_logout" classname="ApiTests" time="0.30"/>
    <testcase name="test_search" classname="ApiTests" time="0.40">
      <failure message="boom">Server error</failure>
    </testcase>
    <testcase name="test_upload" classname="ApiTests" time="0.00">
      <skipped/>
    </testcase>
  </testsuite>
</testsuites>
'@
            'run2-results.json' = @'
{ "tests": [
  { "name": "test_login",  "suite": "ApiTests", "status": "passed", "duration": 0.45 },
  { "name": "test_logout", "suite": "ApiTests", "status": "failed", "duration": 0.35 },
  { "name": "test_search", "suite": "ApiTests", "status": "failed", "duration": 0.42 },
  { "name": "test_delete", "suite": "ApiTests", "status": "passed", "duration": 0.20 } ] }
'@
        }
        # Expected: passed=4 failed=3 skipped=1 total=8 duration=2.62, flaky test_logout.
        Expected    = @(
            'STATUS passed=4 failed=3 skipped=1 total=8 duration=2.62'
            '| Total | 8 |'
            '| ApiTests | test_logout | 1 | 1 |'
        )
        NotExpected = @('No flaky tests detected')
    },
    @{
        Name        = 'all-green-no-flaky'
        Description = 'All tests pass across both legs; no flaky tests'
        Files       = @{
            'green1-junit.xml' = @'
<testsuite name="Smoke" tests="2" failures="0" skipped="0" time="0.30">
  <testcase name="boots_up" classname="Smoke" time="0.10"/>
  <testcase name="renders"  classname="Smoke" time="0.20"/>
</testsuite>
'@
            'green2-results.json' = @'
{ "tests": [
  { "name": "boots_up",   "suite": "Smoke", "status": "passed", "duration": 0.10 },
  { "name": "shuts_down", "suite": "Smoke", "status": "ok",     "duration": 0.30 } ] }
'@
        }
        # Expected: passed=4 failed=0 skipped=0 total=4 duration=0.70, no flaky.
        Expected    = @(
            'STATUS passed=4 failed=0 skipped=0 total=4 duration=0.70'
            '| Total | 4 |'
            'No flaky tests detected'
        )
        NotExpected = @('flaky)')
    }
)

BeforeAll {
    $script:Root          = Split-Path $PSScriptRoot -Parent
    $script:ActResultFile = Join-Path $script:Root 'act-result.txt'
    $script:WorkflowRel   = '.github/workflows/test-results-aggregator.yml'

    # Start act-result.txt fresh for this run.
    $header = "act integration run`n" + ('=' * 60)
    Set-Content -LiteralPath $script:ActResultFile -Value $header -Encoding utf8

    # Build a self-contained throwaway git repo for a case and return its path.
    function New-ActRepo {
        param(
            [string]    $CaseName,
            [hashtable] $Files
        )

        $repo = Join-Path ([System.IO.Path]::GetTempPath()) ("act_${CaseName}_" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $repo | Out-Null

        # Copy the project files the workflow needs.
        Copy-Item -Recurse -Path (Join-Path $script:Root 'src') -Destination (Join-Path $repo 'src')
        Copy-Item -Path (Join-Path $script:Root 'Invoke-Aggregator.ps1') -Destination $repo
        Copy-Item -Path (Join-Path $script:Root '.actrc') -Destination $repo

        # The workflow runs ONLY the unit test file in CI, so copy just that.
        New-Item -ItemType Directory -Path (Join-Path $repo 'tests') | Out-Null
        Copy-Item -Path (Join-Path $script:Root 'tests/TestResultsAggregator.Tests.ps1') -Destination (Join-Path $repo 'tests')

        New-Item -ItemType Directory -Path (Join-Path $repo '.github/workflows') -Force | Out-Null
        Copy-Item -Path (Join-Path $script:Root $script:WorkflowRel) -Destination (Join-Path $repo '.github/workflows')

        # Drop this case's fixtures into test-results/.
        $resultsDir = Join-Path $repo 'test-results'
        New-Item -ItemType Directory -Path $resultsDir | Out-Null
        foreach ($fileName in $Files.Keys) {
            Set-Content -LiteralPath (Join-Path $resultsDir $fileName) -Value $Files[$fileName] -Encoding utf8
        }

        # act needs a git repo with at least one commit.
        git -C $repo init -q
        git -C $repo add -A
        git -C $repo -c user.email='ci@example.com' -c user.name='ci' commit -qm 'fixture' | Out-Null

        return $repo
    }

    # Run the workflow with act in the given repo; returns @{ Output; ExitCode }.
    function Invoke-Act {
        param([string] $RepoPath)

        Push-Location $RepoPath
        try {
            $output = & act push --rm --pull=false -W $script:WorkflowRel 2>&1 | Out-String
            $code = $LASTEXITCODE
        }
        finally {
            Pop-Location
        }
        return @{ Output = $output; ExitCode = $code }
    }
}

Describe 'Workflow via act' {

    It 'case <Name>: act succeeds and output matches exact expected values' -ForEach $script:Cases {

        $repo = New-ActRepo -CaseName $Name -Files $Files
        try {
            $run = Invoke-Act -RepoPath $repo
        }
        finally {
            Remove-Item -LiteralPath $repo -Recurse -Force -ErrorAction SilentlyContinue
        }

        # Persist the full output BEFORE asserting, so the artifact is complete
        # even if an assertion below fails.
        $delim = "`n" + ('-' * 60) + "`nCASE: $Name  ($Description)`nEXIT: $($run.ExitCode)`n" + ('-' * 60)
        Add-Content -LiteralPath $script:ActResultFile -Value $delim -Encoding utf8
        Add-Content -LiteralPath $script:ActResultFile -Value $run.Output -Encoding utf8

        # 1. act / the job must succeed.
        $run.ExitCode | Should -Be 0 -Because "act should exit 0 for case '$Name'"
        $run.Output   | Should -Match 'Job succeeded'

        # 2. Exact known-good values for this case's input.
        foreach ($expected in $Expected) {
            $run.Output | Should -BeLike "*$expected*" -Because "output should contain '$expected'"
        }

        # 3. Values that must NOT appear (guards against false positives).
        foreach ($unexpected in $NotExpected) {
            $run.Output | Should -Not -BeLike "*$unexpected*" -Because "output should NOT contain '$unexpected'"
        }
    }
}
