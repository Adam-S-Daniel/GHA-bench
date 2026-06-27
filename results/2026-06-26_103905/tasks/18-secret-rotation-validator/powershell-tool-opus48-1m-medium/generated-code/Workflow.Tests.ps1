#requires -Modules Pester

<#
    Workflow tests for the Secret Rotation Validator GitHub Actions pipeline.

    Two groups of tests:
      1. Structure / static validation  - parse the YAML, assert triggers,
         jobs, steps, referenced script paths, and that actionlint passes.
      2. act execution tests            - for each test case, build an isolated
         temp git repo, run `act push --rm`, capture output to act-result.txt,
         and assert on EXACT expected values + "Job succeeded".

    Per the task constraints there are exactly 3 act test cases (=> 3 `act push`
    runs total).
#>

BeforeAll {
    $script:RepoRoot     = $PSScriptRoot
    $script:WorkflowPath = Join-Path $RepoRoot '.github/workflows/secret-rotation-validator.yml'
    $script:ActResult    = Join-Path $RepoRoot 'act-result.txt'

    Import-Module powershell-yaml -ErrorAction Stop
    $script:Workflow = Get-Content -Raw $WorkflowPath | ConvertFrom-Yaml

    # Run an act test case in an isolated temp git repo.
    #   FixtureFile : path (relative to fixtures/) of the secrets config to use
    #   WarningDays / OutputFormat : env overrides baked into the temp workflow
    # Returns a hashtable with ExitCode and Output (the captured act log).
    function Invoke-ActCase {
        param(
            [string]$CaseName,
            [string]$FixtureFile,
            [string]$WarningDays,
            [string]$OutputFormat
        )

        $work = Join-Path ([System.IO.Path]::GetTempPath()) ("act-" + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $work 'fixtures') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $work '.github/workflows') -Force | Out-Null

        try {
            # Copy the project files needed by the workflow.
            Copy-Item (Join-Path $RepoRoot 'SecretRotation.psm1')        (Join-Path $work 'SecretRotation.psm1')
            Copy-Item (Join-Path $RepoRoot 'SecretRotation.Tests.ps1')   (Join-Path $work 'SecretRotation.Tests.ps1')
            Copy-Item (Join-Path $RepoRoot 'Invoke-RotationValidator.ps1') (Join-Path $work 'Invoke-RotationValidator.ps1')
            Copy-Item (Join-Path $RepoRoot '.actrc')                     (Join-Path $work '.actrc')

            # The validator always reads fixtures/secrets.json; write the
            # selected case fixture there.
            Copy-Item (Join-Path $RepoRoot "fixtures/$FixtureFile") (Join-Path $work 'fixtures/secrets.json')

            # Copy the workflow, overriding the env values for this case.
            # Case-sensitive (-creplace) so the uppercase env vars are matched
            # without also hitting the lowercase workflow_dispatch input names.
            $wf = Get-Content -Raw $WorkflowPath
            $wf = $wf -creplace "(?m)^(\s*WARNING_DAYS:\s*).*$",  "`${1}'$WarningDays'"
            $wf = $wf -creplace "(?m)^(\s*OUTPUT_FORMAT:\s*).*$", "`${1}$OutputFormat"
            # Give each case a unique workflow name so act derives a unique
            # container/volume name and sequential runs never collide.
            $wf = $wf -replace "(?m)^name:.*$", "name: Secret Rotation Validator $CaseName"
            Set-Content -Path (Join-Path $work '.github/workflows/secret-rotation-validator.yml') -Value $wf

            # Initialise a git repo (act needs one with a commit for `push`).
            Push-Location $work
            try {
                git init -q 2>&1 | Out-Null
                git config user.email 'test@example.com'  | Out-Null
                git config user.name  'test'              | Out-Null
                git add -A 2>&1 | Out-Null
                git commit -qm 'test fixture' 2>&1 | Out-Null

                # Each case uses a unique workflow name (set above), so act
                # derives a unique container/volume name and `--rm` cleans up
                # without colliding with the other cases.
                # --pull=false uses the locally-built pwsh image rather than
                # attempting a registry pull.
                $log = & act push --rm --pull=false 2>&1 | Out-String
                $code = $LASTEXITCODE
            } finally {
                Pop-Location
            }

            # Append to the shared act-result.txt artifact with a delimiter.
            $delim = "`n===== ACT CASE: $CaseName (exit=$code) =====`n"
            Add-Content -Path $ActResult -Value $delim
            Add-Content -Path $ActResult -Value $log

            return @{ ExitCode = $code; Output = $log }
        } finally {
            Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Workflow structure' {

    It 'is valid YAML that parses' {
        $script:Workflow | Should -Not -BeNullOrEmpty
    }

    It 'declares the expected name' {
        $script:Workflow.name | Should -Be 'Secret Rotation Validator'
    }

    It 'configures push, pull_request, schedule and workflow_dispatch triggers' {
        # PowerShell-yaml parses the bare `on:` key; YAML 1.1 turns `on` into $true.
        $on = $script:Workflow[$true]
        if ($null -eq $on) { $on = $script:Workflow.on }
        $on.Keys | Should -Contain 'push'
        $on.Keys | Should -Contain 'pull_request'
        $on.Keys | Should -Contain 'schedule'
        $on.Keys | Should -Contain 'workflow_dispatch'
    }

    It 'sets least-privilege contents:read permission' {
        $script:Workflow.permissions.contents | Should -Be 'read'
    }

    It 'defines the validator env defaults' {
        $script:Workflow.env.CONFIG_PATH | Should -Be 'fixtures/secrets.json'
        $script:Workflow.env.WARNING_DAYS | Should -Be '14'
        $script:Workflow.env.OUTPUT_FORMAT | Should -Be 'markdown'
    }

    It 'has a validate job running on ubuntu-latest' {
        $script:Workflow.jobs.validate | Should -Not -BeNullOrEmpty
        $script:Workflow.jobs.validate.'runs-on' | Should -Be 'ubuntu-latest'
    }

    It 'checks out the repo with actions/checkout@v4' {
        $uses = $script:Workflow.jobs.validate.steps.uses
        $uses | Should -Contain 'actions/checkout@v4'
    }

    It 'runs Pester tests and the validator via pwsh steps' {
        $steps = $script:Workflow.jobs.validate.steps
        $runSteps = $steps | Where-Object { $_.run }
        # All run steps must use the pwsh shell (per task requirement).
        foreach ($s in $runSteps) { $s.shell | Should -Be 'pwsh' }
        ($runSteps.run -join "`n") | Should -Match 'Invoke-Pester'
        ($runSteps.run -join "`n") | Should -Match 'Invoke-RotationValidator\.ps1'
    }
}

Describe 'Referenced files exist' {
    It 'references SecretRotation.psm1 which exists' {
        Test-Path (Join-Path $script:RepoRoot 'SecretRotation.psm1') | Should -BeTrue
    }
    It 'references Invoke-RotationValidator.ps1 which exists' {
        Test-Path (Join-Path $script:RepoRoot 'Invoke-RotationValidator.ps1') | Should -BeTrue
    }
    It 'references SecretRotation.Tests.ps1 which exists' {
        Test-Path (Join-Path $script:RepoRoot 'SecretRotation.Tests.ps1') | Should -BeTrue
    }
    It 'references the default fixture which exists' {
        Test-Path (Join-Path $script:RepoRoot 'fixtures/secrets.json') | Should -BeTrue
    }
}

Describe 'actionlint validation' {
    It 'passes actionlint cleanly (exit 0)' {
        $out = & actionlint $script:WorkflowPath 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($out | Out-String)
    }
}

Describe 'act pipeline execution' {

    BeforeAll {
        # Start each full run with a fresh artifact file.
        if (Test-Path $script:ActResult) { Remove-Item $script:ActResult -Force }
        Set-Content -Path $script:ActResult -Value "Secret Rotation Validator - act results`n"

        # --- Run all three act cases once (each is one `act push`). ---
        $script:CaseMixed = Invoke-ActCase -CaseName 'mixed-markdown' `
            -FixtureFile 'secrets.json' -WarningDays '14' -OutputFormat 'markdown'
        $script:CaseAllOk = Invoke-ActCase -CaseName 'all-ok-markdown' `
            -FixtureFile 'all-ok.json' -WarningDays '7' -OutputFormat 'markdown'
        $script:CaseJson = Invoke-ActCase -CaseName 'mixed-json' `
            -FixtureFile 'secrets.json' -WarningDays '14' -OutputFormat 'json'
    }

    Context 'case: mixed fixture, markdown' {
        It 'exits 0 (act succeeded)' {
            $script:CaseMixed.ExitCode | Should -Be 0 -Because $script:CaseMixed.Output
        }
        It 'reports the job succeeded' {
            $script:CaseMixed.Output | Should -Match 'Job succeeded'
        }
        It 'runs all 21 Pester unit tests with none failing' {
            $script:CaseMixed.Output | Should -Match 'Tests Passed: 21'
            $script:CaseMixed.Output | Should -Match 'Failed: 0'
        }
        It 'produces the exact summary line (2 expired, 1 warning, 1 ok)' {
            $script:CaseMixed.Output | Should -Match 'Summary: 2 expired, 1 warning, 1 ok \(4 total\)'
        }
        It 'classifies prod-db-password as expired with the correct day count' {
            $script:CaseMixed.Output | Should -Match 'prod-db-password \| expired \| -146'
        }
        It 'classifies stripe-api-key as warning in 3 days' {
            $script:CaseMixed.Output | Should -Match 'stripe-api-key \| warning \| 3'
        }
        It 'classifies tls-wildcard-cert as ok in 89 days' {
            $script:CaseMixed.Output | Should -Match 'tls-wildcard-cert \| ok \| 89'
        }
        It 'reports validator exit code 2 (expired present)' {
            $script:CaseMixed.Output | Should -Match 'ROTATION_EXIT_CODE=2'
        }
    }

    Context 'case: all-ok fixture, markdown' {
        It 'exits 0 (act succeeded)' {
            $script:CaseAllOk.ExitCode | Should -Be 0 -Because $script:CaseAllOk.Output
        }
        It 'reports the job succeeded' {
            $script:CaseAllOk.Output | Should -Match 'Job succeeded'
        }
        It 'produces the exact summary line (0 expired, 0 warning, 3 ok)' {
            $script:CaseAllOk.Output | Should -Match 'Summary: 0 expired, 0 warning, 3 ok \(3 total\)'
        }
        It 'reports validator exit code 0 (all ok)' {
            $script:CaseAllOk.Output | Should -Match 'ROTATION_EXIT_CODE=0'
        }
    }

    Context 'case: mixed fixture, json' {
        It 'exits 0 (act succeeded)' {
            $script:CaseJson.ExitCode | Should -Be 0 -Because $script:CaseJson.Output
        }
        It 'reports the job succeeded' {
            $script:CaseJson.Output | Should -Match 'Job succeeded'
        }
        It 'emits JSON summary with total 4' {
            $script:CaseJson.Output | Should -Match '"total": 4'
        }
        It 'emits JSON summary with expired 2' {
            $script:CaseJson.Output | Should -Match '"expired": 2'
        }
        It 'includes the expired prod-db-password entry in JSON' {
            $script:CaseJson.Output | Should -Match '"name": "prod-db-password"'
            $script:CaseJson.Output | Should -Match '"status": "expired"'
        }
    }

    It 'created the act-result.txt artifact' {
        Test-Path $script:ActResult | Should -BeTrue
    }
}
