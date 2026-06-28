# Workflow.Tests.ps1
# Two kinds of tests for the CI pipeline:
#   1. 'structure' - static checks of the workflow YAML (triggers, jobs, steps,
#      script references) and that actionlint passes. Fast, no containers.
#   2. 'act'       - end-to-end execution of every test case THROUGH the actual
#      GitHub Actions workflow via `nektos/act`. Each case sets up an isolated
#      temp git repo with that case's fixture data, runs `act push --rm`,
#      captures the output to act-result.txt, and asserts on the EXACT labels
#      the pipeline produced.
#
# Run structure-only:  Invoke-Pester tests/Workflow.Tests.ps1 -Tag structure
# Run act end-to-end :  Invoke-Pester tests/Workflow.Tests.ps1 -Tag act

BeforeAll {
    $script:ProjectRoot = Split-Path $PSScriptRoot -Parent
    $script:WorkflowPath = Join-Path $script:ProjectRoot '.github/workflows/pr-label-assigner.yml'
}

Describe 'Workflow structure' -Tag 'structure' {
    BeforeAll {
        Import-Module powershell-yaml -ErrorAction Stop
        $script:Yaml = ConvertFrom-Yaml (Get-Content -Raw -LiteralPath $script:WorkflowPath)
    }

    It 'is valid YAML with a name' {
        $script:Yaml.name | Should -Be 'PR Label Assigner'
    }

    It 'declares the expected trigger events' {
        # ConvertFrom-Yaml turns the "on:" key into a hashtable of triggers.
        $on = $script:Yaml['on']
        $on.Keys | Should -Contain 'push'
        $on.Keys | Should -Contain 'pull_request'
        $on.Keys | Should -Contain 'workflow_dispatch'
        $on.Keys | Should -Contain 'schedule'
    }

    It 'sets least-privilege permissions' {
        $script:Yaml.permissions.contents | Should -Be 'read'
        $script:Yaml.permissions['pull-requests'] | Should -Be 'write'
    }

    It 'defines both jobs with the correct dependency ordering' {
        $jobs = $script:Yaml.jobs
        $jobs.Keys | Should -Contain 'unit-tests'
        $jobs.Keys | Should -Contain 'assign-labels'
        # assign-labels must wait for unit-tests.
        $jobs['assign-labels'].needs | Should -Be 'unit-tests'
    }

    It 'checks out the repo with actions/checkout@v4 in every job' {
        foreach ($jobName in $script:Yaml.jobs.Keys) {
            $steps = $script:Yaml.jobs[$jobName].steps
            ($steps.uses -contains 'actions/checkout@v4') | Should -BeTrue -Because "$jobName should check out the repo"
        }
    }

    It 'runs all run-steps with the pwsh shell' {
        foreach ($jobName in $script:Yaml.jobs.Keys) {
            foreach ($step in $script:Yaml.jobs[$jobName].steps) {
                if ($step.ContainsKey('run')) {
                    $step.shell | Should -Be 'pwsh' -Because "step '$($step.name)' uses run:"
                }
            }
        }
    }

    It 'references the Assign-Labels.ps1 script that exists on disk' {
        $assignStep = $script:Yaml.jobs['assign-labels'].steps |
            Where-Object { $_.ContainsKey('run') -and $_.run -match 'Assign-Labels\.ps1' }
        $assignStep | Should -Not -BeNullOrEmpty
        Test-Path (Join-Path $script:ProjectRoot 'Assign-Labels.ps1') | Should -BeTrue
    }

    It 'references the Pester test file that exists on disk' {
        $testStep = $script:Yaml.jobs['unit-tests'].steps |
            Where-Object { $_.ContainsKey('run') -and $_.run -match 'tests/LabelAssigner\.Tests\.ps1' }
        $testStep | Should -Not -BeNullOrEmpty
        Test-Path (Join-Path $script:ProjectRoot 'tests/LabelAssigner.Tests.ps1') | Should -BeTrue
    }

    It 'references supporting files that exist on disk' {
        Test-Path (Join-Path $script:ProjectRoot 'src/LabelAssigner.psm1') | Should -BeTrue
        Test-Path (Join-Path $script:ProjectRoot 'rules.json') | Should -BeTrue
        Test-Path (Join-Path $script:ProjectRoot 'fixtures/changed-files.txt') | Should -BeTrue
    }

    It 'passes actionlint with exit code 0' {
        $null = & actionlint $script:WorkflowPath 2>&1
        $LASTEXITCODE | Should -Be 0
    }
}

Describe 'Workflow execution via act' -Tag 'act' {
    BeforeAll {
        # The fixture for every test case is just the contents of the changed-
        # files list; the workflow + script are identical across cases.
        $script:Cases = @(
            @{
                Name           = 'docs-api-and-tests'
                ChangedFiles   = @('docs/getting-started.md', 'src/api/users.ts', 'src/api/users.test.ts', 'README.md')
                ExpectedLabels = 'tests,api,backend,documentation'
                ExpectedCount  = 4
            },
            @{
                Name           = 'frontend-and-spec'
                ChangedFiles   = @('src/web/app.ts', 'src/web/app.spec.ts')
                ExpectedLabels = 'tests,frontend'
                ExpectedCount  = 2
            },
            @{
                Name           = 'no-matching-files'
                ChangedFiles   = @('Makefile', 'LICENSE')
                ExpectedLabels = ''
                ExpectedCount  = 0
            }
        )

        # Start a fresh act-result.txt for this run.
        $script:ResultFile = Join-Path $script:ProjectRoot 'act-result.txt'
        "PR Label Assigner - act execution log" | Set-Content -LiteralPath $script:ResultFile -Encoding utf8
        "Generated by tests/Workflow.Tests.ps1" | Add-Content -LiteralPath $script:ResultFile

        # Helper: build an isolated temp git repo containing the project files
        # plus this case's fixture, then run the workflow through act.
        function Invoke-ActCase {
            param(
                [string]$Name,
                [string[]]$ChangedFiles
            )

            $work = Join-Path ([System.IO.Path]::GetTempPath()) ("actcase_" + $Name + "_" + [System.Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $work -Force | Out-Null

            try {
                # Copy the pieces the workflow needs into the isolated repo.
                foreach ($item in 'src', 'tests', '.github', 'Assign-Labels.ps1', 'rules.json', '.actrc') {
                    $srcPath = Join-Path $script:ProjectRoot $item
                    if (Test-Path $srcPath) {
                        Copy-Item -Path $srcPath -Destination $work -Recurse -Force
                    }
                }

                # Write this case's fixture (the "PR changed files").
                New-Item -ItemType Directory -Path (Join-Path $work 'fixtures') -Force | Out-Null
                $ChangedFiles | Set-Content -LiteralPath (Join-Path $work 'fixtures/changed-files.txt') -Encoding utf8

                # act/checkout need a git repo with at least one commit.
                Push-Location $work
                try {
                    git init -q 2>&1 | Out-Null
                    git config user.email 'ci@example.com' 2>&1 | Out-Null
                    git config user.name 'ci' 2>&1 | Out-Null
                    git add -A 2>&1 | Out-Null
                    git commit -q -m 'fixture' 2>&1 | Out-Null

                    # Run the push-triggered workflow in the local pwsh image.
                    # --pull=false: the image is built locally and must not be
                    # pulled from a registry (act force-pulls by default).
                    $output = & act push --rm --pull=false 2>&1 | Out-String
                    $exit = $LASTEXITCODE
                }
                finally {
                    Pop-Location
                }

                return [pscustomobject]@{ Output = $output; ExitCode = $exit }
            }
            finally {
                if (Test-Path $work) { Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue }
            }
        }

        # Run every case once up front and cache the results so each assertion
        # below does not re-run the (slow) container.
        $script:Results = @{}
        foreach ($case in $script:Cases) {
            $run = Invoke-ActCase -Name $case.Name -ChangedFiles $case.ChangedFiles

            # Persist the full output, clearly delimited, to the required artifact.
            $delim = "=" * 72
            Add-Content -LiteralPath $script:ResultFile -Value $delim
            Add-Content -LiteralPath $script:ResultFile -Value "TEST CASE: $($case.Name)"
            Add-Content -LiteralPath $script:ResultFile -Value "CHANGED FILES: $($case.ChangedFiles -join ', ')"
            Add-Content -LiteralPath $script:ResultFile -Value "EXPECTED LABELS: '$($case.ExpectedLabels)'  (count $($case.ExpectedCount))"
            Add-Content -LiteralPath $script:ResultFile -Value "ACT EXIT CODE: $($run.ExitCode)"
            Add-Content -LiteralPath $script:ResultFile -Value $delim
            Add-Content -LiteralPath $script:ResultFile -Value $run.Output

            $script:Results[$case.Name] = $run
        }
    }

    It 'wrote the act-result.txt artifact' {
        Test-Path $script:ResultFile | Should -BeTrue
    }

    # Data-driven: one set of assertions per case, all sourced from cached act runs.
    It "case '<Name>' exits 0, both jobs succeed, and labels are exactly '<ExpectedLabels>'" -ForEach @(
        @{ Name = 'docs-api-and-tests'; ExpectedLabels = 'tests,api,backend,documentation'; ExpectedCount = 4 }
        @{ Name = 'frontend-and-spec';  ExpectedLabels = 'tests,frontend';                   ExpectedCount = 2 }
        @{ Name = 'no-matching-files';  ExpectedLabels = '';                                  ExpectedCount = 0 }
    ) {
        $run = $script:Results[$Name]
        $out = $run.Output

        # 1. act exited successfully.
        $run.ExitCode | Should -Be 0 -Because "act push should succeed for case '$Name'"

        # 2. Both jobs (unit-tests + assign-labels) report success.
        $jobSucceeded = ([regex]::Matches($out, 'Job succeeded')).Count
        $jobSucceeded | Should -BeGreaterOrEqual 2 -Because 'both jobs must show "Job succeeded"'

        # 3. The pipeline emitted EXACTLY the expected label line.
        $labelMatch = [regex]::Match($out, 'LABELS=([^\r\n]*)')
        $labelMatch.Success | Should -BeTrue -Because 'the workflow must print a LABELS= line'
        $actualLabels = $labelMatch.Groups[1].Value.Trim()
        $actualLabels | Should -Be $ExpectedLabels

        # 4. The emitted count matches too.
        $countMatch = [regex]::Match($out, 'LABEL_COUNT=([0-9]+)')
        $countMatch.Success | Should -BeTrue
        [int]$countMatch.Groups[1].Value | Should -Be $ExpectedCount
    }
}
