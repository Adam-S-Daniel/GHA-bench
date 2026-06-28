# Workflow.Tests.ps1
#
# Acceptance + structure tests for the GitHub Actions workflow.
#
#   * 'Workflow structure'  — parses the YAML and asserts on triggers, jobs,
#                             steps, permissions, env, and that the script paths
#                             the workflow references actually exist.
#   * 'actionlint'          — asserts actionlint exits 0 on the workflow.
#   * 'Workflow acceptance via act' (Tag 'Act') — for EACH fixture, spins up an
#                             isolated git repo, runs `act push --rm`, appends
#                             the output to act-result.txt, and asserts the exit
#                             code, the exact report values, and that every job
#                             reports success.
#
# The 'Act' describe is tagged so the fast static checks can be run on their own:
#     Invoke-Pester ./Workflow.Tests.ps1 -ExcludeTagFilter Act      # instant
#     Invoke-Pester ./Workflow.Tests.ps1                            # runs act
#
# NOTE: the act describe runs `act push` once per fixture (3 runs total).

BeforeAll {
    $script:Root         = $PSScriptRoot
    $script:WorkflowPath = Join-Path $Root '.github/workflows/secret-rotation-validator.yml'
    $script:ScriptPath   = Join-Path $Root 'SecretRotationValidator.ps1'
    $script:TestsPath    = Join-Path $Root 'SecretRotationValidator.Tests.ps1'

    Import-Module powershell-yaml -ErrorAction Stop
    $script:Wf = Get-Content -LiteralPath $WorkflowPath -Raw | ConvertFrom-Yaml

    # Flattened list of every step across all jobs, for convenient assertions.
    $script:AllSteps = foreach ($jobName in $Wf['jobs'].Keys) {
        foreach ($step in $Wf['jobs'][$jobName]['steps']) { $step }
    }
}

Describe 'Workflow structure' {

    It 'has the expected workflow name' {
        $Wf['name'] | Should -Be 'Secret Rotation Validator'
    }

    It 'declares all four trigger events (push, pull_request, schedule, workflow_dispatch)' {
        $triggers = $Wf['on']
        $triggers.Keys | Should -Contain 'push'
        $triggers.Keys | Should -Contain 'pull_request'
        $triggers.Keys | Should -Contain 'schedule'
        $triggers.Keys | Should -Contain 'workflow_dispatch'
    }

    It 'defines a cron schedule' {
        $Wf['on']['schedule'][0]['cron'] | Should -Match '^\S+ \S+ \S+ \S+ \S+$'
    }

    It 'exposes workflow_dispatch inputs for config, window and format' {
        $inputs = $Wf['on']['workflow_dispatch']['inputs']
        $inputs.Keys | Should -Contain 'config_path'
        $inputs.Keys | Should -Contain 'warning_window_days'
        $inputs.Keys | Should -Contain 'format'
    }

    It 'requests least-privilege read-only contents permission' {
        $Wf['permissions']['contents'] | Should -Be 'read'
    }

    It 'sets workflow-level environment variables' {
        $Wf['env'].Keys | Should -Contain 'CONFIG_PATH'
        $Wf['env'].Keys | Should -Contain 'REPORT_FORMAT'
    }

    It 'declares exactly the two expected jobs' {
        $Wf['jobs'].Keys | Should -Contain 'unit-tests'
        $Wf['jobs'].Keys | Should -Contain 'rotation-report'
    }

    It 'makes the report job depend on the unit-tests job' {
        @($Wf['jobs']['rotation-report']['needs']) | Should -Contain 'unit-tests'
    }

    It 'runs both jobs on ubuntu-latest' {
        $Wf['jobs']['unit-tests']['runs-on']      | Should -Be 'ubuntu-latest'
        $Wf['jobs']['rotation-report']['runs-on'] | Should -Be 'ubuntu-latest'
    }

    It 'checks out the repository with actions/checkout@v4 in every job' {
        foreach ($jobName in $Wf['jobs'].Keys) {
            $uses = $Wf['jobs'][$jobName]['steps'] | ForEach-Object { $_['uses'] }
            $uses | Should -Contain 'actions/checkout@v4'
        }
    }

    It 'runs PowerShell steps with shell: pwsh (never pwsh -Command/-File)' {
        $runSteps = $AllSteps | Where-Object { $_.Contains('run') }
        ($runSteps | Where-Object { $_['shell'] -eq 'pwsh' }).Count | Should -BeGreaterThan 0
        foreach ($s in $runSteps) {
            $s['shell'] | Should -Be 'pwsh'
            $s['run']   | Should -Not -Match 'pwsh\s+-(Command|File)'
        }
    }

    It 'references the validator script and its tests by name' {
        $wfText = Get-Content -LiteralPath $WorkflowPath -Raw
        $wfText | Should -Match 'SecretRotationValidator\.ps1'
        $wfText | Should -Match 'SecretRotationValidator\.Tests\.ps1'
    }

    It 'references only files that actually exist on disk' {
        Test-Path -LiteralPath $ScriptPath                       | Should -BeTrue
        Test-Path -LiteralPath $TestsPath                        | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $Root 'fixtures/config.json') | Should -BeTrue
    }
}

Describe 'actionlint' {
    It 'passes actionlint with exit code 0' {
        $output = (& actionlint $WorkflowPath 2>&1 | Out-String)
        $LASTEXITCODE | Should -Be 0 -Because "actionlint reported:`n$output"
    }
}

Describe 'Workflow acceptance via act' -Tag 'Act' {

    BeforeAll {
        Import-Module (Join-Path $Root 'test/ActHarness.psm1') -Force

        $script:ResultLog = Join-Path $Root 'act-result.txt'
        # Start a fresh artifact for this run.
        Set-Content -LiteralPath $ResultLog -Encoding utf8 -Value @"
ACT WORKFLOW TEST RESULTS - Secret Rotation Validator
Generated: $((Get-Date).ToString('u'))
Each section below is one test case: an isolated git repo seeded with that
case's fixture, run through `act push --rm`.
"@

        # Exact, known-good expectations per fixture (computed deterministically
        # against referenceDate 2026-06-28, warning window 14).
        $script:CaseOrder = @('mixed', 'all-ok', 'all-expired')
        $script:Expected  = @{
            'mixed' = @{
                Fixture = Join-Path $Root 'fixtures/mixed.json'
                Summary = 'ROTATION_SUMMARY expired=2 warning=1 ok=2 total=5'
                Groups  = @(
                    'GROUP EXPIRED: STRIPE_API_KEY,DATABASE_PASSWORD'
                    'GROUP WARNING: JWT_SIGNING_KEY'
                    'GROUP OK: GITHUB_TOKEN,TLS_CERT'
                )
                Policy   = 'POLICY_EXIT_CODE=1'
                Report   = @('# Secret Rotation Report', '## Expired (2)', '## Warning (1)', '## OK (2)')
                Json     = @('"total": 5', '"expired": 2', '"warningWindowDays": 14')
            }
            'all-ok' = @{
                Fixture = Join-Path $Root 'fixtures/all-ok.json'
                Summary = 'ROTATION_SUMMARY expired=0 warning=0 ok=2 total=2'
                Groups  = @('GROUP OK: SESSION_SECRET,SMTP_PASSWORD')
                Policy  = 'POLICY_EXIT_CODE=0'
                Report  = @('## OK (2)', '_None_')
                Json    = @('"total": 2', '"expired": 0')
            }
            'all-expired' = @{
                Fixture = Join-Path $Root 'fixtures/all-expired.json'
                Summary = 'ROTATION_SUMMARY expired=3 warning=0 ok=0 total=3'
                Groups  = @('GROUP EXPIRED: DEPRECATED_CERT,LEGACY_DB_PASSWORD,OLD_API_TOKEN')
                Policy  = 'POLICY_EXIT_CODE=1'
                Report  = @('## Expired (3)')
                Json    = @('"total": 3', '"expired": 3')
            }
        }

        # Run act once per case (this is the slow part) and stash the results.
        $script:Results = @{}
        foreach ($case in $CaseOrder) {
            $script:Results[$case] = Invoke-ActCase `
                -CaseName    $case `
                -FixturePath $Expected[$case].Fixture `
                -ProjectRoot $Root `
                -ResultLog   $ResultLog
        }
    }

    It 'produced the act-result.txt artifact' {
        Test-Path -LiteralPath $ResultLog | Should -BeTrue
    }

    # One Context per fixture. -ForEach supplies $Name at discovery time (so the
    # contexts are generated correctly) and at run time (so each It reads the
    # right captured output) — avoiding the foreach loop-variable capture bug.
    Context "case: <Name>" -ForEach @(
        @{ Name = 'mixed' }
        @{ Name = 'all-ok' }
        @{ Name = 'all-expired' }
    ) {

        It 'act exited with code 0' {
            $r = $Results[$Name]
            $r.ExitCode | Should -Be 0 -Because "act output:`n$($r.Output)"
        }

        It 'every job reported success and none failed' {
            $out = $Results[$Name].Output
            # Two jobs (unit-tests + rotation-report) must each succeed.
            ([regex]::Matches($out, 'Job succeeded')).Count | Should -BeGreaterOrEqual 2
            $out | Should -Not -Match 'Job failed'
        }

        It 'emitted the exact ROTATION_SUMMARY line' {
            $Results[$Name].Output.Contains($Expected[$Name].Summary) |
                Should -BeTrue -Because "expected '$($Expected[$Name].Summary)'"
        }

        It 'emitted the exact urgency-group membership lines' {
            $out = $Results[$Name].Output
            foreach ($line in $Expected[$Name].Groups) {
                $out.Contains($line) | Should -BeTrue -Because "expected group line '$line'"
            }
        }

        It 'reported the exact POLICY_EXIT_CODE' {
            $Results[$Name].Output.Contains($Expected[$Name].Policy) |
                Should -BeTrue -Because "expected '$($Expected[$Name].Policy)'"
        }

        It 'rendered the markdown report' {
            $out = $Results[$Name].Output
            foreach ($frag in $Expected[$Name].Report) {
                $out.Contains($frag) | Should -BeTrue -Because "expected markdown fragment '$frag'"
            }
        }

        It 'rendered the JSON report' {
            $out = $Results[$Name].Output
            foreach ($frag in $Expected[$Name].Json) {
                $out.Contains($frag) | Should -BeTrue -Because "expected JSON fragment '$frag'"
            }
        }

        It 'ran the validator unit tests inside the pipeline (no failures)' {
            $out = $Results[$Name].Output
            # Pester's own summary line proves the unit job executed the suite.
            $out | Should -Match 'Tests Passed:\s*\d+'
            $out | Should -Not -Match 'Tests Passed:\s*\d+,\s*Failed:\s*[1-9]'
        }
    }
}
