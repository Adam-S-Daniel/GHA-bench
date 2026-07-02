# Workflow tests: static structure checks plus end-to-end execution via act.
#
# Structure tests parse the workflow YAML and verify triggers/jobs/steps and
# that every file the workflow references actually exists.
#
# The act harness runs every end-to-end test case THROUGH the GitHub Actions
# pipeline: for each case it builds a temp git repo containing the project
# files plus that case's fixture, runs `act push --rm`, appends the full output
# to act-result.txt (a required artifact), and asserts on exact expected
# values from the known-good result for that fixture.

BeforeDiscovery {
    # Test-case table is needed at discovery time to generate one It per case.
    $script:ActCases = @(
        @{
            CaseName    = 'mixed-urgency fixture (default secrets.json)'
            FixtureFile = 'secrets.json'
            # Exact known-good values for fixtures/secrets.json at
            # REFERENCE_DATE 2026-07-01 with a 14-day window.
            ExpectedLines = @(
                'ROTATION-SUMMARY expired=2 warning=2 ok=1 total=5'
                '| db-password | EXPIRED | 2026-04-01 | -91 | billing-api, reporting |'
                '| webhook-token | EXPIRED | 2026-07-01 | 0 | ci-pipeline |'
                '| jwt-secret | WARNING | 2026-07-04 | 3 | auth-service, gateway |'
                '| api-key | WARNING | 2026-07-05 | 4 | gateway |'
                '| tls-cert | OK | 2027-06-01 | 335 | web-frontend |'
                '"daysRemaining": -91'
            )
        }
        @{
            CaseName    = 'all-ok fixture (secrets-ok.json)'
            FixtureFile = 'secrets-ok.json'
            ExpectedLines = @(
                'ROTATION-SUMMARY expired=0 warning=0 ok=2 total=2'
                '| signing-key | OK | 2026-08-29 | 59 | release-pipeline |'
                '| oauth-secret | OK | 2026-10-28 | 119 | sso |'
            )
        }
    )
}

BeforeAll {
    $script:ProjectRoot  = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:WorkflowPath = Join-Path $ProjectRoot '.github' 'workflows' 'secret-rotation-validator.yml'
}

Describe 'Workflow structure' {

    BeforeAll {
        Import-Module powershell-yaml -ErrorAction Stop
        $script:Workflow = Get-Content -Path $WorkflowPath -Raw | ConvertFrom-Yaml
        # YAML 1.1 parsers may read the unquoted 'on' key as boolean true;
        # accept either spelling.
        $script:Triggers = if ($Workflow.Contains('on')) { $Workflow['on'] } else { $Workflow[$true] }
    }

    It 'has push, pull_request, schedule, and workflow_dispatch triggers' {
        $Triggers.Keys | Should -Contain 'push'
        $Triggers.Keys | Should -Contain 'pull_request'
        $Triggers.Keys | Should -Contain 'workflow_dispatch'
        $Triggers['schedule'][0]['cron'] | Should -Be '0 6 * * 1'
    }

    It 'restricts permissions to contents: read' {
        $Workflow['permissions']['contents'] | Should -Be 'read'
    }

    It 'defines a test job and a report job that depends on it' {
        $Workflow['jobs'].Keys | Should -Contain 'test'
        $Workflow['jobs'].Keys | Should -Contain 'report'
        $Workflow['jobs']['report']['needs'] | Should -Be 'test'
    }

    It 'checks out the repository with actions/checkout@v4 in every job' {
        foreach ($job in $Workflow['jobs'].Values) {
            @($job['steps'] | Where-Object { $_['uses'] -eq 'actions/checkout@v4' }).Count |
                Should -BeGreaterOrEqual 1
        }
    }

    It 'uses shell: pwsh on every run step' {
        foreach ($job in $Workflow['jobs'].Values) {
            foreach ($step in ($job['steps'] | Where-Object { $_.Contains('run') })) {
                $step['shell'] | Should -Be 'pwsh'
            }
        }
    }

    It 'references files that actually exist in the repository' {
        $raw = Get-Content -Path $WorkflowPath -Raw
        foreach ($ref in 'SecretRotationValidator.ps1', 'tests/SecretRotationValidator.Tests.ps1', 'fixtures/secrets.json') {
            $raw | Should -Match ([regex]::Escape($ref))
            Test-Path (Join-Path $ProjectRoot $ref) | Should -BeTrue -Because "workflow references $ref"
        }
    }

    It 'passes actionlint' {
        & actionlint $WorkflowPath
        $LASTEXITCODE | Should -Be 0
    }
}

Describe 'Workflow execution via act' {

    BeforeAll {
        # Fresh required artifact for this run; every case appends to it.
        $script:ActResultPath = Join-Path $ProjectRoot 'act-result.txt'
        Set-Content -Path $ActResultPath -Value "act end-to-end results $([datetime]::UtcNow.ToString('u'))"

        # Runs one test case through the full pipeline and returns the act
        # output + exit code. Builds an isolated git repo so act sees a clean
        # 'push' event with exactly this case's fixture as fixtures/secrets.json.
        function script:Invoke-ActCase {
            param([string]$CaseName, [string]$FixtureFile)

            $repo = Join-Path ([System.IO.Path]::GetTempPath()) "srv-act-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
            New-Item -ItemType Directory -Path $repo | Out-Null
            try {
                # Project files the workflow needs, plus .actrc (runner image map).
                Copy-Item (Join-Path $ProjectRoot '.github') (Join-Path $repo '.github') -Recurse
                Copy-Item (Join-Path $ProjectRoot '.actrc') $repo
                Copy-Item (Join-Path $ProjectRoot 'SecretRotationValidator.ps1') $repo
                New-Item -ItemType Directory -Path (Join-Path $repo 'tests') | Out-Null
                Copy-Item (Join-Path $ProjectRoot 'tests' 'SecretRotationValidator.Tests.ps1') (Join-Path $repo 'tests')
                Copy-Item (Join-Path $ProjectRoot 'fixtures') (Join-Path $repo 'fixtures') -Recurse

                Push-Location $repo
                try {
                    git init --quiet 2>&1 | Out-Null
                    git -c user.email='test@example.com' -c user.name='act-test' add -A 2>&1 | Out-Null
                    git -c user.email='test@example.com' -c user.name='act-test' commit --quiet -m 'test' 2>&1 | Out-Null
                    # --pull=false: the runner image is local-only; act's
                    # default force-pull fails against the registry.
                    # --var selects this case's fixture for the report job
                    # without touching the files the unit tests depend on.
                    $output = & act push --rm --pull=false --var "SECRETS_CONFIG=fixtures/$FixtureFile" 2>&1 | Out-String
                    $exit = $LASTEXITCODE
                }
                finally {
                    Pop-Location
                }

                # Append to the required artifact, clearly delimited per case.
                Add-Content -Path $script:ActResultPath -Value @(
                    ''
                    "================ CASE: $CaseName (fixture: $FixtureFile) ================"
                    $output
                    "---------------- exit code: $exit ----------------"
                )

                [pscustomobject]@{ Output = $output; ExitCode = $exit }
            }
            finally {
                Remove-Item -Path $repo -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        # Execute every case once up front; the Its below assert on the results.
        $script:ActResults = @{}
        foreach ($case in $ActCases) {
            $script:ActResults[$case.FixtureFile] = Invoke-ActCase -CaseName $case.CaseName -FixtureFile $case.FixtureFile
        }
    }

    Context 'case: <CaseName>' -ForEach $ActCases {

        BeforeAll { $script:Result = $ActResults[$FixtureFile] }

        It 'act exits with code 0' {
            $Result.ExitCode | Should -Be 0
        }

        It 'every job reports success and none fail' {
            $Result.Output | Should -Match 'Unit tests[^\r\n]*Job succeeded'
            $Result.Output | Should -Match 'Rotation report[^\r\n]*Job succeeded'
            ([regex]::Matches($Result.Output, 'Job succeeded')).Count | Should -Be 2
            $Result.Output | Should -Not -Match 'Job failed'
        }

        It 'output contains the exact expected report values' {
            foreach ($line in $ExpectedLines) {
                $Result.Output | Should -Match ([regex]::Escape($line))
            }
        }
    }

    Context 'required artifact' {

        It 'act-result.txt exists and contains every case' {
            Test-Path $ActResultPath | Should -BeTrue
            $content = Get-Content -Path $ActResultPath -Raw
            foreach ($case in $ActCases) {
                $content | Should -Match ([regex]::Escape("CASE: $($case.CaseName)"))
            }
        }
    }
}
