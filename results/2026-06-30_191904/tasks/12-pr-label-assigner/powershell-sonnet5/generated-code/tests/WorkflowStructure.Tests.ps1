<#
    Structure tests for the GitHub Actions workflow itself (as opposed to the
    PowerShell label-assignment logic, covered by PrLabelAssigner.Tests.ps1).
    These parse the workflow YAML and assert on its shape, confirm the files
    it references actually exist, and assert that actionlint passes.
#>

BeforeAll {
    $script:RepoRoot = Join-Path $PSScriptRoot '..'
    $script:WorkflowPath = Join-Path $script:RepoRoot '.github' 'workflows' 'pr-label-assigner.yml'

    if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
        Install-Module -Name powershell-yaml -Force -SkipPublisherCheck -Scope CurrentUser
    }
    Import-Module powershell-yaml -Force

    $script:WorkflowYaml = Get-Content -LiteralPath $script:WorkflowPath -Raw
    $script:Workflow = ConvertFrom-Yaml -Yaml $script:WorkflowYaml -Ordered
}

Describe 'pr-label-assigner.yml workflow structure' {
    It 'exists at the expected path' {
        Test-Path -LiteralPath $script:WorkflowPath -PathType Leaf | Should -BeTrue
    }

    It 'parses as valid YAML' {
        { ConvertFrom-Yaml -Yaml $script:WorkflowYaml } | Should -Not -Throw
    }

    Context 'triggers' {
        BeforeAll {
            # YAML parses the bare 'on:' key as boolean $true in PowerShell-Yaml; look it up defensively.
            $script:Triggers = if ($script:Workflow.Contains('on')) { $script:Workflow['on'] } else { $script:Workflow[$true] }
        }

        It 'triggers on pull_request' {
            $script:Triggers.Contains('pull_request') | Should -BeTrue
        }

        It 'triggers on push' {
            $script:Triggers.Contains('push') | Should -BeTrue
        }

        It 'triggers on workflow_dispatch' {
            $script:Triggers.Contains('workflow_dispatch') | Should -BeTrue
        }
    }

    Context 'jobs' {
        BeforeAll {
            $script:Jobs = $script:Workflow['jobs']
        }

        It 'defines a unit-tests job' {
            $script:Jobs.Contains('unit-tests') | Should -BeTrue
        }

        It 'defines an assign-labels job' {
            $script:Jobs.Contains('assign-labels') | Should -BeTrue
        }

        It 'makes assign-labels depend on unit-tests' {
            $script:Jobs['assign-labels']['needs'] | Should -Be 'unit-tests'
        }

        It 'grants assign-labels pull-requests write permission' {
            $script:Jobs['assign-labels']['permissions']['pull-requests'] | Should -Be 'write'
        }

        It 'runs every job on ubuntu-latest' {
            foreach ($jobName in $script:Jobs.Keys) {
                $script:Jobs[$jobName]['runs-on'] | Should -Be 'ubuntu-latest'
            }
        }

        It 'checks out the repository in every job' {
            foreach ($jobName in $script:Jobs.Keys) {
                $steps = $script:Jobs[$jobName]['steps']
                $usesCheckout = $steps | Where-Object { $_.Contains('uses') -and $_['uses'] -like 'actions/checkout@*' }
                $usesCheckout | Should -Not -BeNullOrEmpty -Because "job '$jobName' should check out the repo"
            }
        }

        It 'uses shell: pwsh for every scripted step' {
            foreach ($jobName in $script:Jobs.Keys) {
                $steps = $script:Jobs[$jobName]['steps']
                foreach ($step in $steps) {
                    if ($step.Contains('run')) {
                        $step['shell'] | Should -Be 'pwsh' -Because "every run: step in job '$jobName' must use shell: pwsh"
                    }
                }
            }
        }
    }

    Context 'script references' {
        It 'invokes Invoke-PrLabelAssigner.ps1, which in turn imports PrLabelAssigner.psm1 (both exist on disk)' {
            $script:WorkflowYaml | Should -Match 'Invoke-PrLabelAssigner\.ps1'
            Test-Path -LiteralPath (Join-Path $script:RepoRoot 'PrLabelAssigner.psm1') | Should -BeTrue
            Get-Content -LiteralPath (Join-Path $script:RepoRoot 'Invoke-PrLabelAssigner.ps1') -Raw | Should -Match 'PrLabelAssigner\.psm1'
        }

        It 'references Invoke-PrLabelAssigner.ps1 and it exists on disk' {
            $script:WorkflowYaml | Should -Match 'Invoke-PrLabelAssigner\.ps1'
            Test-Path -LiteralPath (Join-Path $script:RepoRoot 'Invoke-PrLabelAssigner.ps1') | Should -BeTrue
        }

        It 'references the ./tests directory and it exists on disk' {
            $script:WorkflowYaml | Should -Match '\./tests'
            Test-Path -LiteralPath (Join-Path $script:RepoRoot 'tests') -PathType Container | Should -BeTrue
        }

        It 'references rules.json and it exists on disk' {
            $script:WorkflowYaml | Should -Match 'RULES_PATH'
            Test-Path -LiteralPath (Join-Path $script:RepoRoot 'rules.json') | Should -BeTrue
        }
    }
}

Describe 'actionlint validation' {
    It 'is available on PATH' {
        Get-Command -Name actionlint -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'passes with exit code 0 against the workflow file' {
        $output = & actionlint $script:WorkflowPath 2>&1
        $exitCode = $LASTEXITCODE
        ($output | Out-String) | Should -BeNullOrEmpty -Because "actionlint output should be empty on success, got:`n$output"
        $exitCode | Should -Be 0
    }
}
