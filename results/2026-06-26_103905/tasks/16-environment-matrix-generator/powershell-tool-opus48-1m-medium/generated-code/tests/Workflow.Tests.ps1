# Workflow.Tests.ps1
#
# Two suites:
#   1. Workflow STRUCTURE tests   - parse the YAML, assert triggers/jobs/steps,
#                                   verify referenced script paths exist, and
#                                   assert actionlint passes (exit 0).
#   2. ACT INTEGRATION tests      - build an isolated temp git repo containing
#                                   the project + all fixtures, run the workflow
#                                   end-to-end with `act push --rm`, capture the
#                                   output to act-result.txt, and assert EXACT
#                                   expected values for every fixture plus
#                                   "Job succeeded".
#
# All fixtures are processed in a single `act push` run (the workflow loops over
# them) to stay within the act-run budget while still asserting per-fixture.
#
# Run with:  Invoke-Pester ./tests/Workflow.Tests.ps1

BeforeAll {
    $script:RepoRoot     = Split-Path $PSScriptRoot -Parent
    $script:WorkflowPath = Join-Path $RepoRoot '.github/workflows/environment-matrix-generator.yml'

    # Helper: pull the matrix JSON block a fixture printed between its
    # "===== FIXTURE: <name> =====" header and the following "=====" marker.
    # Defined in BeforeAll so it is in scope for It blocks under Pester 5.
    function Get-FixtureJson {
        param([string] $Output, [string] $Name)

        $lines = $Output -split "`r?`n"
        $collecting = $false
        $buffer = @()
        foreach ($line in $lines) {
            if ($line -match "===== FIXTURE: $([regex]::Escape($Name)) =====") {
                $collecting = $true
                continue
            }
            if ($collecting) {
                # act prefixes step output; stop at the next delimiter line.
                if ($line -match '=====\s*(JOBCOUNT|VALIDATION_FAILED|END FIXTURE)') { break }
                # Strip act's "[Workflow/Job] | " log prefix to recover raw JSON.
                $clean = $line -replace '^.*?\|\s?', ''
                $buffer += $clean
            }
        }
        return ($buffer -join "`n")
    }
}

Describe 'Workflow structure' {
    BeforeAll {
        Import-Module powershell-yaml -ErrorAction Stop
        $script:Yaml = ConvertFrom-Yaml (Get-Content $WorkflowPath -Raw)
    }

    It 'exists as a YAML file' {
        Test-Path $WorkflowPath | Should -Be $true
    }

    It 'declares the expected trigger events' {
        # ConvertFrom-Yaml parses the `on:` key (YAML 1.1 may map it to $true).
        $on = if ($Yaml.ContainsKey('on')) { $Yaml['on'] } else { $Yaml[$true] }
        $on.Keys | Should -Contain 'push'
        $on.Keys | Should -Contain 'pull_request'
        $on.Keys | Should -Contain 'workflow_dispatch'
        $on.Keys | Should -Contain 'schedule'
    }

    It 'sets least-privilege permissions' {
        $Yaml.permissions.contents | Should -Be 'read'
    }

    It 'defines the generate-matrix job on ubuntu-latest' {
        $Yaml.jobs.Keys | Should -Contain 'generate-matrix'
        $Yaml.jobs['generate-matrix'].'runs-on' | Should -Be 'ubuntu-latest'
    }

    It 'checks out the repo with actions/checkout@v4' {
        $steps = $Yaml.jobs['generate-matrix'].steps
        @($steps | Where-Object { $_.uses -eq 'actions/checkout@v4' }).Count | Should -Be 1
    }

    It 'uses shell: pwsh for run steps' {
        $steps = $Yaml.jobs['generate-matrix'].steps
        $runSteps = $steps | Where-Object { $_.ContainsKey('run') }
        $runSteps.Count | Should -BeGreaterThan 0
        foreach ($s in $runSteps) { $s.shell | Should -Be 'pwsh' }
    }

    It 'references the BuildMatrix module that actually exists' {
        $generateStep = $Yaml.jobs['generate-matrix'].steps |
            Where-Object { $_.ContainsKey('run') -and $_.run -match 'BuildMatrix.psm1' }
        $generateStep | Should -Not -BeNullOrEmpty
        Test-Path (Join-Path $RepoRoot 'src/BuildMatrix.psm1') | Should -Be $true
    }

    It 'ships the CLI script and unit tests referenced by the project' {
        Test-Path (Join-Path $RepoRoot 'src/Generate-Matrix.ps1') | Should -Be $true
        Test-Path (Join-Path $RepoRoot 'tests/BuildMatrix.Tests.ps1') | Should -Be $true
    }

    It 'passes actionlint with exit code 0' {
        $output = & actionlint $WorkflowPath 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($output -join "`n")
    }
}

Describe 'Act integration (full pipeline run)' {
    BeforeAll {
        $script:ActResultPath = Join-Path $RepoRoot 'act-result.txt'
        # Start a fresh act-result.txt for this run.
        Set-Content -Path $ActResultPath -Value "ACT RESULT LOG - environment-matrix-generator`n" -Encoding utf8

        # --- Build an isolated temp git repo with the project + fixtures. ---
        $script:TmpRepo = Join-Path ([System.IO.Path]::GetTempPath()) ("emg-act-" + [System.Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $TmpRepo -Force | Out-Null

        foreach ($item in @('src', 'tests', 'fixtures', '.github', '.actrc')) {
            $srcPath = Join-Path $RepoRoot $item
            if (Test-Path $srcPath) {
                Copy-Item -Path $srcPath -Destination $TmpRepo -Recurse -Force
            }
        }

        Push-Location $TmpRepo
        try {
            git init -q 2>&1 | Out-Null
            git config user.email 'ci@example.com' 2>&1 | Out-Null
            git config user.name 'CI' 2>&1 | Out-Null
            git add -A 2>&1 | Out-Null
            git commit -q -m 'fixture' 2>&1 | Out-Null

            # Run the workflow end-to-end. Single run covers all fixtures.
            # --pull=false: use the locally-built act-ubuntu-pwsh image instead
            # of force-pulling the :latest tag from a registry.
            $script:ActOutput = & act push --rm --pull=false 2>&1 | Out-String
            $script:ActExit = $LASTEXITCODE
        }
        finally {
            Pop-Location
        }

        # Persist the full act output to the required artifact.
        Add-Content -Path $ActResultPath -Value "===== ACT PUSH RUN (all fixtures) =====" -Encoding utf8
        Add-Content -Path $ActResultPath -Value $ActOutput -Encoding utf8
        Add-Content -Path $ActResultPath -Value "===== ACT EXIT CODE: $ActExit =====`n" -Encoding utf8
    }

    AfterAll {
        if ($TmpRepo -and (Test-Path $TmpRepo)) {
            Remove-Item -Path $TmpRepo -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'act exited with code 0' {
        $ActExit | Should -Be 0 -Because "act output:`n$ActOutput"
    }

    It 'reports Job succeeded' {
        $ActOutput | Should -Match 'Job succeeded'
    }

    It 'wrote the act-result.txt artifact' {
        Test-Path $ActResultPath | Should -Be $true
        (Get-Content $ActResultPath -Raw).Length | Should -BeGreaterThan 0
    }

    It 'basic fixture expands to exactly 4 jobs' {
        $ActOutput | Should -Match 'JOBCOUNT: basic = 4'
    }

    It 'basic fixture emits the exact OS dimension and fail-fast=true' {
        # Extract the JSON block printed for the basic fixture.
        $json = Get-FixtureJson -Output $ActOutput -Name 'basic'
        $parsed = $json | ConvertFrom-Json
        $parsed.strategy.'fail-fast' | Should -Be $true
        @($parsed.strategy.matrix.os) | Should -Be @('ubuntu-latest', 'windows-latest')
        @($parsed.strategy.matrix.node) | Should -Be @('18', '20')
        $parsed.jobCount | Should -Be 4
    }

    It 'include-exclude fixture expands to exactly 6 jobs' {
        $ActOutput | Should -Match 'JOBCOUNT: include-exclude = 6'
    }

    It 'include-exclude fixture carries max-parallel=3 and fail-fast=false' {
        $json = Get-FixtureJson -Output $ActOutput -Name 'include-exclude'
        $parsed = $json | ConvertFrom-Json
        $parsed.strategy.'fail-fast' | Should -Be $false
        $parsed.strategy.'max-parallel' | Should -Be 3
        # exclude + include arrays are preserved in the emitted matrix.
        @($parsed.strategy.matrix.exclude).Count | Should -Be 1
        @($parsed.strategy.matrix.include).Count | Should -Be 2
        $parsed.jobCount | Should -Be 6
    }

    It 'oversize fixture fails validation with the exact max-size message' {
        $ActOutput | Should -Match 'VALIDATION_FAILED: oversize = .*exceeds the maximum allowed size of 5'
    }

    It 'runs the Pester unit tests inside the pipeline (13 passed)' {
        # The final workflow step runs Invoke-Pester; assert the summary line.
        $ActOutput | Should -Match 'Tests Passed: 13'
    }
}
