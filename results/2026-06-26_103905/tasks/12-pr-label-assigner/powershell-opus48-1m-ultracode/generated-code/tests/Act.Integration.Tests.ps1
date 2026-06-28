# Act.Integration.Tests.ps1
#
# End-to-end tests that run EVERY fixture case through the real GitHub Actions
# workflow using `act` (nektos/act) in Docker, then assert on exact expected
# label sets parsed from the pipeline's output.
#
# Why one act run for all cases:
#   Each `act push` takes ~30-90s, and the task guidance caps act invocations at
#   three. The workflow's assign-labels job therefore processes ALL fixtures in a
#   single run and prints one parseable "RESULT case=<name> labels=<...>" line per
#   case. This harness runs act ONCE, then asserts each case independently from
#   that single run's output -- exercising every case through the pipeline while
#   staying well within the act-run budget.
#
# The full act log plus a clearly-delimited per-case breakdown is written to
# act-result.txt in the repository root (a required artifact).

# Expected results are hand-computed from config/labeler-config.json and the
# fixtures, NOT derived from the script (so the assertion is independent of it).
# Available at discovery time for -ForEach.
$ExpectedCases = @(
    @{ Case = 'api';   Expected = 'api,backend,source' }
    @{ Case = 'docs';  Expected = 'documentation' }
    @{ Case = 'mixed'; Expected = 'api,backend,tests,ci,source,documentation,config' }
    @{ Case = 'none';  Expected = 'NONE' }
    @{ Case = 'tests'; Expected = 'api,backend,tests,source,documentation' }
)

# Whether act + docker are usable on this host (evaluated during discovery so we
# can cleanly skip on machines without them; on the benchmark host both exist).
$script:ActUsable = [bool](Get-Command act -ErrorAction SilentlyContinue) -and
                    [bool](Get-Command docker -ErrorAction SilentlyContinue)

Describe 'Workflow runs through act' -Skip:(-not $script:ActUsable) {

    BeforeAll {
        # Pester runs discovery and run in separate scopes: the top-level
        # $ExpectedCases above is visible to -ForEach (discovery) but NOT here in
        # the run phase, so we re-declare a run-phase copy. The two are kept in
        # sync and cross-checked by the per-case assertions below.
        $script:ExpectedCases = @(
            @{ Case = 'api';   Expected = 'api,backend,source' }
            @{ Case = 'docs';  Expected = 'documentation' }
            @{ Case = 'mixed'; Expected = 'api,backend,tests,ci,source,documentation,config' }
            @{ Case = 'none';  Expected = 'NONE' }
            @{ Case = 'tests'; Expected = 'api,backend,tests,source,documentation' }
        )

        $script:repoRoot   = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
        $script:resultFile = Join-Path $script:repoRoot 'act-result.txt'
        $actExe            = (Get-Command act).Source
        $image             = 'act-ubuntu-pwsh:latest'

        # --- 1. Build an isolated temp git repo with the project + fixtures ----
        $script:tempRepo = Join-Path ([System.IO.Path]::GetTempPath()) ("pr-label-act-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:tempRepo -Force | Out-Null

        # Copy exactly the files the workflow needs (not .git / act-result.txt).
        $toCopy = @('src', 'scripts', 'config', 'fixtures', 'tests', '.github', '.actrc')
        foreach ($item in $toCopy) {
            $srcPath = Join-Path $script:repoRoot $item
            if (Test-Path -LiteralPath $srcPath) {
                Copy-Item -LiteralPath $srcPath -Destination $script:tempRepo -Recurse -Force
            }
        }

        # --- 2. Initialise + commit so actions/checkout@v4 has a real repo -----
        Push-Location $script:tempRepo
        try {
            git init -q -b main 2>&1 | Out-Null
            git -c user.email='ci@example.com' -c user.name='CI' add -A 2>&1 | Out-Null
            git -c user.email='ci@example.com' -c user.name='CI' commit -q -m 'fixture' 2>&1 | Out-Null

            # --- 3. Run the workflow once over all fixtures --------------------
            # --pull=false : the image is local; never hit the network.
            # -P           : pin the runner image (also set via copied .actrc).
            $raw = & $actExe push --rm --pull=false -P "ubuntu-latest=$image" `
                -W '.github/workflows/pr-label-assigner.yml' 2>&1
            $script:actExit   = $LASTEXITCODE
            $script:actOutput = ($raw | Out-String)
        }
        finally {
            Pop-Location
        }

        # --- 4. Parse RESULT lines (strip ANSI colour codes first) ------------
        $script:clean = $script:actOutput -replace "`e\[[0-9;]*m", ''
        $script:parsed = @{}
        foreach ($line in ($script:clean -split "`r?`n")) {
            if ($line -match 'RESULT case=(?<case>\S+) labels=(?<labels>\S+)') {
                $script:parsed[$Matches['case']] = $Matches['labels']
            }
        }

        # Count successful jobs reported by act.
        $script:jobSucceededCount = ([regex]::Matches($script:clean, 'Job succeeded')).Count

        # --- 5. Persist the required artifact ---------------------------------
        $sb = [System.Text.StringBuilder]::new()
        [void]$sb.AppendLine('=================================================================')
        [void]$sb.AppendLine(' PR LABEL ASSIGNER - act integration run')
        [void]$sb.AppendLine(' All fixture cases were bundled into a single `act push` run to')
        [void]$sb.AppendLine(' respect the documented limit of <=3 act invocations.')
        [void]$sb.AppendLine((" act exit code : {0}" -f $script:actExit))
        [void]$sb.AppendLine((" jobs succeeded: {0}" -f $script:jobSucceededCount))
        [void]$sb.AppendLine('=================================================================')
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('----- FULL act push OUTPUT -----')
        [void]$sb.AppendLine($script:actOutput)
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('----- PER-CASE RESULTS (parsed from the run above) -----')
        foreach ($c in $script:ExpectedCases) {
            $actual = if ($script:parsed.ContainsKey($c.Case)) { $script:parsed[$c.Case] } else { '<MISSING>' }
            $status = if ($actual -eq $c.Expected) { 'PASS' } else { 'FAIL' }
            [void]$sb.AppendLine('')
            [void]$sb.AppendLine(("### CASE: {0}" -f $c.Case))
            [void]$sb.AppendLine(("  fixture        : fixtures/case-{0}.txt" -f $c.Case))
            [void]$sb.AppendLine(("  expected labels: {0}" -f $c.Expected))
            [void]$sb.AppendLine(("  actual   labels: {0}" -f $actual))
            [void]$sb.AppendLine(("  status         : {0}" -f $status))
        }
        Set-Content -LiteralPath $script:resultFile -Value $sb.ToString() -Encoding utf8
    }

    AfterAll {
        if ($script:tempRepo -and (Test-Path -LiteralPath $script:tempRepo)) {
            Remove-Item -LiteralPath $script:tempRepo -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'act exited with code 0' {
        $script:actExit | Should -Be 0 -Because ("act output:`n" + $script:actOutput)
    }

    It 'every job reports "Job succeeded" (test + assign-labels)' {
        # The test job and the assign-labels job must each succeed.
        $script:jobSucceededCount | Should -BeGreaterOrEqual 2
    }

    It 'the test (Pester) job ran and the unit suite passed in-container' {
        # Pester's detailed summary proves the test job executed successfully.
        $script:clean | Should -Match 'Tests Passed:\s*\d+,\s*Failed:\s*0'
    }

    It 'the assign-labels job ran to completion' {
        $script:clean | Should -Match 'All fixture cases processed successfully'
    }

    It 'produced a RESULT line for every fixture case' {
        $script:parsed.Keys.Count | Should -Be $script:ExpectedCases.Count
    }

    It 'case <Case> yields exactly labels <Expected>' -ForEach $ExpectedCases {
        $script:parsed.ContainsKey($Case) | Should -BeTrue -Because "no RESULT line for case '$Case'"
        $script:parsed[$Case] | Should -Be $Expected
    }

    It 'wrote the act-result.txt artifact' {
        Test-Path -LiteralPath $script:resultFile | Should -BeTrue
        (Get-Item -LiteralPath $script:resultFile).Length | Should -BeGreaterThan 0
    }
}
