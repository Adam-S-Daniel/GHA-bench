# ACCEPTANCE tests — run the whole workflow through `act` (nektos/act) in Docker.
#
# Strategy (to respect the "few act runs" budget): the workflow processes every
# fixture in ONE run via a matrix, so a single `act push --rm` covers the
# unit-tests job + all four license-check legs. We capture the full output to
# act-result.txt and assert on EXACT expected values per fixture, that act exited
# 0, and that every job reports success.

# --- discovery-phase data (must exist when Pester discovers -ForEach cases) ---

# Exact, known-good RESULT line emitted by each fixture leg.
$ExpectedResults = @(
    @{ Name = 'clean';        Line = 'RESULT label=clean total=3 approved=3 denied=0 unknown=0 compliant=true' }
    @{ Name = 'violations';   Line = 'RESULT label=violations total=3 approved=1 denied=2 unknown=0 compliant=false' }
    @{ Name = 'mixed';        Line = 'RESULT label=mixed total=4 approved=1 denied=1 unknown=2 compliant=false' }
    @{ Name = 'requirements'; Line = 'RESULT label=requirements total=5 approved=3 denied=1 unknown=1 compliant=false' }
)

# unit-tests (1) + license-check matrix legs (4) = 5 jobs expected to succeed.
$ExpectedJobCount = 5

# Can we actually run act here? (Evaluated at discovery for -Skip.)
$CanRunAct = [bool](Get-Command act -ErrorAction SilentlyContinue) -and
             [bool](Get-Command docker -ErrorAction SilentlyContinue)

Describe 'Workflow executes successfully via act' -Skip:(-not $CanRunAct) {

    BeforeAll {
        $script:RepoRoot      = (Resolve-Path "$PSScriptRoot/..").Path
        $script:ActResultPath = Join-Path $RepoRoot 'act-result.txt'
        $script:ActImageArg   = 'ubuntu-latest=act-ubuntu-pwsh:latest'

        # Build an isolated temp git repo containing the project + fixtures.
        $script:WorkDir = Join-Path ([System.IO.Path]::GetTempPath()) `
            ("act-liccheck-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null

        foreach ($file in 'DependencyLicenseChecker.ps1', 'license-config.json', 'license-db.json', '.actrc') {
            $src = Join-Path $RepoRoot $file
            if (Test-Path $src) { Copy-Item $src (Join-Path $WorkDir $file) -Force }
        }
        foreach ($dir in 'fixtures', 'tests', '.github') {
            Copy-Item (Join-Path $RepoRoot $dir) (Join-Path $WorkDir $dir) -Recurse -Force
        }

        Push-Location $WorkDir
        try {
            git init -b main *>$null
            git config user.email 'ci@example.com' *>$null
            git config user.name  'CI Bot'        *>$null
            git add -A *>$null
            git commit -m 'license checker + fixtures' *>$null

            # Single act run. --pull=false: the pwsh image is built locally and is
            # not in any registry, so we must NOT force a pull. Explicit -P so we
            # do not depend on .actrc resolution.
            $script:ActOutput = (& act push --rm --pull=false -P $ActImageArg 2>&1 | Out-String)
            $script:ActExit   = $LASTEXITCODE
        }
        finally {
            Pop-Location
        }

        # Persist the full act output — required artifact.
        $delim  = ('=' * 80)
        $header = @(
            $delim
            "act push --rm -P $ActImageArg"
            "single run covering: unit-tests + license-check matrix (clean, violations, mixed, requirements)"
            "act exit code: $ActExit"
            $delim
        ) -join "`n"
        Set-Content -Path $ActResultPath -Value ($header + "`n" + $ActOutput) -Encoding utf8

        # Clean up the temp repo (output is already captured).
        Remove-Item -Path $WorkDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'act exited with code 0' {
        $ActExit | Should -Be 0 -Because "act output:`n$ActOutput"
    }

    It 'wrote the act-result.txt artifact' {
        Test-Path $ActResultPath | Should -BeTrue
    }

    It 'fixture <Name> produced the exact expected RESULT line' -ForEach $ExpectedResults {
        $ActOutput | Should -Match ([regex]::Escape($Line))
    }

    It 'ran the Pester unit tests inside the pipeline (no failures)' {
        # The unit-tests job runs Invoke-Pester; its summary must show 0 failures.
        # Pester colourises the summary, so strip ANSI escape codes before matching.
        $clean = $ActOutput -replace "`e\[[0-9;]*m", ''
        $clean | Should -Match 'Tests Passed: \d+, Failed: 0'
    }

    It "reports at least $ExpectedJobCount succeeded jobs and zero failed" {
        $succeeded = ([regex]::Matches($ActOutput, 'Job succeeded')).Count
        $failed    = ([regex]::Matches($ActOutput, 'Job failed')).Count
        $succeeded | Should -BeGreaterOrEqual $ExpectedJobCount -Because "act output:`n$ActOutput"
        $failed    | Should -Be 0
    }
}

Describe 'Acceptance prerequisites' {
    It 'docker and act are available' {
        # Recompute here: discovery-phase variables are not visible at run-phase.
        $ok = [bool](Get-Command act -ErrorAction SilentlyContinue) -and
              [bool](Get-Command docker -ErrorAction SilentlyContinue)
        if (-not $ok) { Set-ItResult -Skipped -Because 'docker/act not available'; return }
        $ok | Should -BeTrue
    }
}
