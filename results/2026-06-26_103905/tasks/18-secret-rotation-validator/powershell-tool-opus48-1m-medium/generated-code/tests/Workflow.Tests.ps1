# Workflow tests for the Secret Rotation Validator GitHub Actions pipeline.
#
# Two layers:
#   1. Structure tests  - parse the YAML, assert triggers/jobs/steps and that
#                         referenced script paths exist; assert actionlint passes.
#   2. End-to-end tests - for each fixture case, build a throwaway git repo,
#                         run the workflow with `act push --rm`, capture output
#                         to act-result.txt and assert on EXACT expected values.
#
# Per the task: every functional test case runs THROUGH the workflow via act.

BeforeAll {
    $script:RepoRoot    = Split-Path -Parent $PSScriptRoot
    $script:WorkflowPath = Join-Path $script:RepoRoot '.github/workflows/secret-rotation-validator.yml'
    $script:ActResultPath = Join-Path $script:RepoRoot 'act-result.txt'

    # Fresh act-result.txt for this run; each act case appends a delimited block.
    Set-Content -Path $script:ActResultPath -Value "# act-result.txt - Secret Rotation Validator workflow runs`n" -Encoding utf8

    Import-Module powershell-yaml -ErrorAction Stop
    $script:Workflow = Get-Content -Raw -Path $script:WorkflowPath | ConvertFrom-Yaml

    # Helper: build an isolated git repo containing the project + a chosen
    # fixture, run act, append output to act-result.txt and return a result.
    function Invoke-WorkflowCase {
        param(
            [Parameter(Mandatory)] [string]   $CaseName,
            [Parameter(Mandatory)] [string]   $FixtureFile,   # under fixtures/cases
            [Parameter(Mandatory)] [string]   $ReferenceDate,
            [Parameter(Mandatory)] [int]      $WarningWindowDays,
            [Parameter(Mandatory)] [string]   $OutputFormat
        )

        $work = Join-Path ([System.IO.Path]::GetTempPath()) "srv-act-$CaseName-$(New-Guid)"
        New-Item -ItemType Directory -Path $work -Force | Out-Null

        try {
            # Copy the project files the workflow needs into the temp repo.
            foreach ($item in @('src', 'tests', 'fixtures', '.github', 'Invoke-SecretRotationValidator.ps1', '.actrc')) {
                $source = Join-Path $script:RepoRoot $item
                if (Test-Path $source) {
                    Copy-Item -Path $source -Destination $work -Recurse -Force
                }
            }

            # Swap in this case's fixture as the config the workflow reads.
            Copy-Item -Path (Join-Path $script:RepoRoot "fixtures/cases/$FixtureFile") `
                      -Destination (Join-Path $work 'fixtures/secrets.json') -Force

            # act requires a committed git repo to resolve the push event.
            Push-Location $work
            try {
                git init -q 2>&1 | Out-Null
                git config user.email 'ci@example.com' 2>&1 | Out-Null
                git config user.name 'ci' 2>&1 | Out-Null
                git add -A 2>&1 | Out-Null
                git commit -q -m "case $CaseName" 2>&1 | Out-Null

                # Inject the deterministic settings via container env (--env),
                # which the workflow reads when no dispatch input is present.
                $actArgs = @(
                    'push', '--rm',
                    '--pull=false',  # image is local; never authenticate to a registry
                    '--env', "REFERENCE_DATE=$ReferenceDate",
                    '--env', "WARNING_WINDOW_DAYS=$WarningWindowDays",
                    '--env', "OUTPUT_FORMAT=$OutputFormat"
                )
                $output = & act @actArgs 2>&1 | Out-String
                $exit = $LASTEXITCODE
            }
            finally {
                Pop-Location
            }

            # Append a clearly-delimited block to the shared artifact.
            $block = @(
                "================================================================"
                "CASE: $CaseName (fixture=$FixtureFile ref=$ReferenceDate window=$WarningWindowDays format=$OutputFormat)"
                "ACT EXIT CODE: $exit"
                "----------------------------------------------------------------"
                $output
                ""
            ) -join "`n"
            Add-Content -Path $script:ActResultPath -Value $block -Encoding utf8

            return [pscustomobject]@{ ExitCode = $exit; Output = $output }
        }
        finally {
            Remove-Item -Path $work -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Workflow structure' {

    It 'is named and exists on disk' {
        Test-Path $script:WorkflowPath | Should -BeTrue
        $script:Workflow.name | Should -Be 'Secret Rotation Validator'
    }

    It 'declares the expected trigger events' {
        # powershell-yaml preserves the bare `on:` key as the string 'on'.
        $on = $script:Workflow['on']
        $on.Keys | Should -Contain 'push'
        $on.Keys | Should -Contain 'pull_request'
        $on.Keys | Should -Contain 'schedule'
        $on.Keys | Should -Contain 'workflow_dispatch'
    }

    It 'grants least-privilege contents:read permission' {
        $script:Workflow.permissions.contents | Should -Be 'read'
    }

    It 'defines both jobs with a dependency from validate-rotation to unit-tests' {
        $script:Workflow.jobs.Keys | Should -Contain 'unit-tests'
        $script:Workflow.jobs.Keys | Should -Contain 'validate-rotation'
        $script:Workflow.jobs.'validate-rotation'.needs | Should -Be 'unit-tests'
    }

    It 'checks out the repo and uses pwsh in every run step' {
        foreach ($jobName in $script:Workflow.jobs.Keys) {
            $steps = $script:Workflow.jobs.$jobName.steps
            ($steps | Where-Object { $_.uses -eq 'actions/checkout@v4' }).Count | Should -BeGreaterThan 0
            foreach ($step in ($steps | Where-Object { $_.ContainsKey('run') })) {
                $step.shell | Should -Be 'pwsh'
            }
        }
    }

    It 'references script and test files that actually exist' {
        $allRun = foreach ($jobName in $script:Workflow.jobs.Keys) {
            $script:Workflow.jobs.$jobName.steps | Where-Object { $_.ContainsKey('run') } | ForEach-Object { $_.run }
        }
        $joined = $allRun -join "`n"
        $joined | Should -Match 'Invoke-SecretRotationValidator\.ps1'
        $joined | Should -Match 'tests/SecretRotationValidator\.Tests\.ps1'

        Test-Path (Join-Path $script:RepoRoot 'Invoke-SecretRotationValidator.ps1') | Should -BeTrue
        Test-Path (Join-Path $script:RepoRoot 'src/SecretRotationValidator.psm1')   | Should -BeTrue
        Test-Path (Join-Path $script:RepoRoot 'tests/SecretRotationValidator.Tests.ps1') | Should -BeTrue
        Test-Path (Join-Path $script:RepoRoot 'fixtures/secrets.json') | Should -BeTrue
    }
}

Describe 'actionlint validation' {
    It 'passes actionlint with exit code 0' {
        Push-Location $script:RepoRoot
        try {
            $out = & actionlint '.github/workflows/secret-rotation-validator.yml' 2>&1 | Out-String
            $LASTEXITCODE | Should -Be 0 -Because $out
        }
        finally {
            Pop-Location
        }
    }
}

Describe 'End-to-end workflow execution via act' -Tag 'Act' {

    Context 'Case: mixed urgencies, markdown output' {
        BeforeAll {
            $script:mixed = Invoke-WorkflowCase -CaseName 'mixed' -FixtureFile 'mixed.json' `
                -ReferenceDate '2026-06-01' -WarningWindowDays 14 -OutputFormat 'markdown'
        }

        It 'exits with code 0' {
            $script:mixed.ExitCode | Should -Be 0
        }
        It 'reports both jobs succeeded' {
            ([regex]::Matches($script:mixed.Output, 'Job succeeded')).Count | Should -BeGreaterOrEqual 2
        }
        It 'classifies the exact expected summary (2 expired, 1 warning, 1 ok)' {
            $script:mixed.Output | Should -Match 'ROTATION_SUMMARY expired=2 warning=1 ok=1 total=4'
        }
        It 'shows db-password as expired with -61 days until due' {
            $script:mixed.Output | Should -Match '\| db-password \| expired \| 2026-01-01 \| 2026-04-01 \| -61 \| api, worker \|'
        }
        It 'shows tls-cert as warning with 7 days until due' {
            $script:mixed.Output | Should -Match '\| tls-cert \| warning \| 2026-05-25 \| 2026-06-08 \| 7 \| ingress \|'
        }
        It 'shows signing-key as ok' {
            $script:mixed.Output | Should -Match '\| signing-key \| ok \| 2026-06-01 \| 2027-06-01 \| 365 \| releases \|'
        }
    }

    Context 'Case: all ok, markdown output' {
        BeforeAll {
            $script:allok = Invoke-WorkflowCase -CaseName 'all-ok' -FixtureFile 'all-ok.json' `
                -ReferenceDate '2026-01-02' -WarningWindowDays 7 -OutputFormat 'markdown'
        }

        It 'exits with code 0' {
            $script:allok.ExitCode | Should -Be 0
        }
        It 'reports both jobs succeeded' {
            ([regex]::Matches($script:allok.Output, 'Job succeeded')).Count | Should -BeGreaterOrEqual 2
        }
        It 'classifies the exact expected summary (0 expired, 0 warning, 2 ok)' {
            $script:allok.Output | Should -Match 'ROTATION_SUMMARY expired=0 warning=0 ok=2 total=2'
        }
        It 'shows vault-root as ok with 89 days until due' {
            $script:allok.Output | Should -Match '\| vault-root \| ok \| 2026-01-01 \| 2026-04-01 \| 89 \| platform \|'
        }
    }

    Context 'Case: all expired, JSON output' {
        BeforeAll {
            $script:expired = Invoke-WorkflowCase -CaseName 'all-expired' -FixtureFile 'all-expired.json' `
                -ReferenceDate '2026-12-31' -WarningWindowDays 14 -OutputFormat 'json'
        }

        It 'exits with code 0' {
            $script:expired.ExitCode | Should -Be 0
        }
        It 'reports both jobs succeeded' {
            ([regex]::Matches($script:expired.Output, 'Job succeeded')).Count | Should -BeGreaterOrEqual 2
        }
        It 'classifies the exact expected summary (2 expired, 0 warning, 0 ok)' {
            $script:expired.Output | Should -Match 'ROTATION_SUMMARY expired=2 warning=0 ok=0 total=2'
        }
        It 'emits JSON containing legacy-token expired at -334 days' {
            $script:expired.Output | Should -Match '"name": "legacy-token"'
            $script:expired.Output | Should -Match '"daysUntilDue": -334'
        }
        It 'emits JSON containing smtp-password expired at -273 days' {
            $script:expired.Output | Should -Match '"name": "smtp-password"'
            $script:expired.Output | Should -Match '"daysUntilDue": -273'
        }
    }
}

AfterAll {
    if (Test-Path $script:ActResultPath) {
        Write-Host "act output written to: $script:ActResultPath"
    }
}
