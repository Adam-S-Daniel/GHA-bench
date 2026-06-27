#requires -Modules Pester

<#
    End-to-end + structural tests for the GitHub Actions workflow.

    Per the task requirements, the validator is NOT exercised directly here:
    every functional test case runs the real pipeline through `act` (nektos/act).
    For each case we:
      1. build a throwaway git repo containing the project files + that case's
         fixture data,
      2. run `act push --rm`, capturing stdout/stderr and the exit code,
      3. append the full output to ../act-result.txt (clearly delimited),
      4. assert act exited 0, every job reports "Job succeeded", and the parsed
         output matches the EXACT known-good values for that case's input.

    To keep `act` invocations to exactly one per case (act is slow), all cases are
    executed once in BeforeAll and the results are asserted in the It blocks.

    Pester phase note: the case catalogue lives in tests/cases.ps1 and is invoked
    in BOTH the discovery phase (to drive -ForEach) and the run phase (to feed the
    act loop), because variables set in one phase do not flow into the other.

    Structural tests (YAML shape, script references, actionlint) need no container
    and run instantly.
#>

# Discovery-phase load: makes the case list available to -ForEach below.
$WorkflowCases = & (Join-Path $PSScriptRoot 'cases.ps1')

BeforeAll {
    $script:RepoRoot     = Split-Path $PSScriptRoot -Parent
    $script:WorkflowPath = Join-Path $script:RepoRoot '.github/workflows/secret-rotation-validator.yml'
    $script:ActResultLog = Join-Path $script:RepoRoot 'act-result.txt'

    # Run-phase load of the same catalogue (top-level $WorkflowCases is not visible here).
    $script:Cases = & (Join-Path $PSScriptRoot 'cases.ps1')

    # act/docker availability (recomputed here; BeforeDiscovery values do not flow in).
    # SRV_SKIP_ACT lets the structural/actionlint tests run without spending the
    # (slow) act invocations - used for quick harness self-checks.
    $script:ActAvailable = [bool](Get-Command act -ErrorAction SilentlyContinue) -and
                           [bool](Get-Command docker -ErrorAction SilentlyContinue) -and
                           -not $env:SRV_SKIP_ACT

    # Helper: stage a throwaway git repo with the project files + a case fixture.
    function New-ActWorkspace {
        param([Parameter(Mandatory)] [string] $FixtureJson)

        $ws = Join-Path ([System.IO.Path]::GetTempPath()) ('srv-act-' + [System.Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $ws -Force | Out-Null

        # Copy the files the workflow needs (deliberately excluding Workflow.Tests.ps1
        # and cases.ps1 so act never tries to run act-inside-act).
        New-Item -ItemType Directory -Path (Join-Path $ws '.github/workflows') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $ws 'tests') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $ws 'fixtures') -Force | Out-Null

        Copy-Item (Join-Path $script:RepoRoot 'SecretRotationValidator.psm1')             (Join-Path $ws 'SecretRotationValidator.psm1')
        Copy-Item (Join-Path $script:RepoRoot 'Invoke-SecretRotationValidator.ps1')        (Join-Path $ws 'Invoke-SecretRotationValidator.ps1')
        Copy-Item $script:WorkflowPath                                                     (Join-Path $ws '.github/workflows/secret-rotation-validator.yml')
        Copy-Item (Join-Path $script:RepoRoot '.actrc')                                    (Join-Path $ws '.actrc')
        Copy-Item (Join-Path $script:RepoRoot 'tests/SecretRotationValidator.Tests.ps1')   (Join-Path $ws 'tests/SecretRotationValidator.Tests.ps1')

        # The per-case fixture under test.
        Set-Content -LiteralPath (Join-Path $ws 'fixtures/secrets.json') -Value $FixtureJson -Encoding utf8

        # act push requires a git repo with at least one commit.
        Push-Location $ws
        try {
            git init -q --initial-branch=main 2>&1 | Out-Null
            git config user.email 'ci@example.com' 2>&1 | Out-Null
            git config user.name  'ci' 2>&1 | Out-Null
            git add -A 2>&1 | Out-Null
            git commit -q -m 'fixture' 2>&1 | Out-Null
        } finally {
            Pop-Location
        }
        return $ws
    }

    # Helper: run `act push` in a workspace and return output + exit code.
    function Invoke-ActPush {
        param([Parameter(Mandatory)] [string] $Workspace)

        Push-Location $Workspace
        try {
            # --pull=false: the act-ubuntu-pwsh image is local-only (no registry).
            # 2>&1 merges stderr so the full transcript is captured for assertions.
            $output = & act push --rm --pull=false 2>&1 | Out-String
            $code   = $LASTEXITCODE
        } finally {
            Pop-Location
        }
        return [pscustomobject]@{ Output = $output; ExitCode = $code }
    }

    # ---- Run every case through act exactly once, recording results keyed by name. ----
    $script:ActResults = @{}
    if ($script:ActAvailable) {
        # Fresh act-result.txt for this run (required deliverable artifact).
        Set-Content -LiteralPath $script:ActResultLog -Value "Secret Rotation Validator - act test results`n" -Encoding utf8

        foreach ($case in $script:Cases) {
            $ws = $null
            try {
                $ws  = New-ActWorkspace -FixtureJson $case.Fixture
                $run = Invoke-ActPush -Workspace $ws

                $script:ActResults[$case.Name] = $run

                # Append this case's full transcript, clearly delimited.
                $delim = @(
                    ''
                    '################################################################################'
                    "# TEST CASE: $($case.Name)"
                    "# Expected: $($case.Expected.Summary)"
                    "# act exit code: $($run.ExitCode)"
                    '################################################################################'
                    ''
                ) -join "`n"
                Add-Content -LiteralPath $script:ActResultLog -Value $delim
                Add-Content -LiteralPath $script:ActResultLog -Value $run.Output
            } finally {
                if ($ws -and (Test-Path $ws)) { Remove-Item $ws -Recurse -Force -ErrorAction SilentlyContinue }
            }
        }
    }
}

Describe 'Workflow structure' {

    BeforeAll {
        $script:Yaml = Get-Content -LiteralPath $script:WorkflowPath -Raw
    }

    It 'exists at the expected path' {
        Test-Path $script:WorkflowPath | Should -BeTrue
    }

    It 'declares the required trigger events' {
        # Light-touch structural assertions on the raw YAML keep the test free of a
        # YAML-parser dependency while still verifying the contract.
        $script:Yaml | Should -Match '(?m)^on:'
        $script:Yaml | Should -Match '(?m)^\s+push:'
        $script:Yaml | Should -Match '(?m)^\s+pull_request:'
        $script:Yaml | Should -Match '(?m)^\s+schedule:'
        $script:Yaml | Should -Match '(?m)^\s+workflow_dispatch:'
    }

    It 'declares least-privilege permissions' {
        $script:Yaml | Should -Match 'permissions:'
        $script:Yaml | Should -Match 'contents:\s*read'
    }

    It 'defines both the unit-tests and rotation-report jobs with a dependency' {
        $script:Yaml | Should -Match '(?m)^\s+unit-tests:'
        $script:Yaml | Should -Match '(?m)^\s+rotation-report:'
        $script:Yaml | Should -Match 'needs:\s*unit-tests'
    }

    It 'uses actions/checkout@v4 and the pwsh shell' {
        $script:Yaml | Should -Match 'actions/checkout@v4'
        $script:Yaml | Should -Match 'shell:\s*pwsh'
    }

    It 'references project files that actually exist' {
        # The workflow names these paths; verify they are present in the repo.
        $script:Yaml | Should -Match 'Invoke-SecretRotationValidator\.ps1'
        $script:Yaml | Should -Match 'tests/SecretRotationValidator\.Tests\.ps1'
        Test-Path (Join-Path $script:RepoRoot 'Invoke-SecretRotationValidator.ps1') | Should -BeTrue
        Test-Path (Join-Path $script:RepoRoot 'SecretRotationValidator.psm1') | Should -BeTrue
        Test-Path (Join-Path $script:RepoRoot 'fixtures/secrets.json') | Should -BeTrue
    }
}

Describe 'actionlint validation' {

    It 'passes actionlint with exit code 0' -Skip:(-not (Get-Command actionlint -ErrorAction SilentlyContinue)) {
        $out = & actionlint $script:WorkflowPath 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 0 -Because "actionlint output:`n$out"
    }
}

Describe 'End-to-end pipeline via act' {

    It 'produced the act-result.txt artifact' -Skip:(-not $WorkflowCases) {
        if (-not $script:ActAvailable) { Set-ItResult -Skipped -Because 'act/docker unavailable' ; return }
        Test-Path $script:ActResultLog | Should -BeTrue
    }

    Context 'Case <_.Name>' -ForEach $WorkflowCases {

        It 'act exited with code 0' {
            if (-not $script:ActAvailable) { Set-ItResult -Skipped -Because 'act/docker unavailable' ; return }
            $run = $script:ActResults[$_.Name]
            $run | Should -Not -BeNullOrEmpty
            $run.ExitCode | Should -Be 0 -Because "act output:`n$($run.Output)"
        }

        It 'both jobs reported success' {
            if (-not $script:ActAvailable) { Set-ItResult -Skipped -Because 'act/docker unavailable' ; return }
            $run = $script:ActResults[$_.Name]
            # act prints a "Job succeeded" line per job; this workflow has two jobs.
            $succeeded = ([regex]::Matches($run.Output, 'Job succeeded')).Count
            $succeeded | Should -BeGreaterOrEqual 2 -Because "act output:`n$($run.Output)"
        }

        It 'emitted the exact rotation summary for this input' {
            if (-not $script:ActAvailable) { Set-ItResult -Skipped -Because 'act/docker unavailable' ; return }
            $run = $script:ActResults[$_.Name]
            $run.Output | Should -Match ([regex]::Escape($_.Expected.Summary))
        }

        It 'listed the exact expired secrets for this input' {
            if (-not $script:ActAvailable) { Set-ItResult -Skipped -Because 'act/docker unavailable' ; return }
            $run = $script:ActResults[$_.Name]
            $run.Output | Should -Match ([regex]::Escape($_.Expected.ExpiredNames))
        }

        It 'listed the exact warning secrets for this input' {
            if (-not $script:ActAvailable) { Set-ItResult -Skipped -Because 'act/docker unavailable' ; return }
            $run = $script:ActResults[$_.Name]
            $run.Output | Should -Match ([regex]::Escape($_.Expected.WarningNames))
        }

        It 'ran the Pester unit tests inside the pipeline' {
            if (-not $script:ActAvailable) { Set-ItResult -Skipped -Because 'act/docker unavailable' ; return }
            $run = $script:ActResults[$_.Name]
            # Evidence the unit-tests job actually executed the suite in-container.
            $run.Output | Should -Match 'Tests Passed:\s*\d+'
        }
    }
}
