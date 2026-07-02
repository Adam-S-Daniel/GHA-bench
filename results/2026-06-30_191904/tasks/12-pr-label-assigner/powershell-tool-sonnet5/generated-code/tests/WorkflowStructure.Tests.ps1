# Structural tests for .github/workflows/pr-label-assigner.yml: parses the
# YAML (via the dependency-free SimpleYaml reader, since only pwsh + Pester
# are pre-installed in the act container) and asserts on triggers, jobs,
# permissions, and that referenced script files actually exist. Also shells
# out to actionlint when available.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'Helpers' 'SimpleYaml.psm1') -Force
    $script:RepoRoot = Join-Path $PSScriptRoot '..'
    $script:WorkflowPath = Join-Path $script:RepoRoot '.github' 'workflows' 'pr-label-assigner.yml'
    $script:Workflow = ConvertFrom-SimpleYaml -Lines (Get-Content -Path $script:WorkflowPath)
}

Describe 'pr-label-assigner.yml structure' {
    It 'exists at the expected path' {
        Test-Path -Path $script:WorkflowPath -PathType Leaf | Should -BeTrue
    }

    It 'declares the required trigger events' {
        # YAML parses the bare 'on:' key as boolean true, so read it back as
        # the raw text key. PowerShell's own YAML-less parsing via our
        # reader keeps the literal key text, so look it up defensively.
        $onKey = @('on', 'true', 'True') | Where-Object { $script:Workflow.Contains($_) } | Select-Object -First 1
        $onKey | Should -Not -BeNullOrEmpty
        $triggers = $script:Workflow[$onKey]
        $triggers.Keys | Should -Contain 'push'
        $triggers.Keys | Should -Contain 'pull_request'
        $triggers.Keys | Should -Contain 'schedule'
        $triggers.Keys | Should -Contain 'workflow_dispatch'
    }

    It 'defines a cron schedule with 5 fields' {
        $onKey = @('on', 'true', 'True') | Where-Object { $script:Workflow.Contains($_) } | Select-Object -First 1
        $cronEntry = $script:Workflow[$onKey].schedule[0]
        $cronEntry.cron.Split(' ').Count | Should -Be 5
    }

    It 'exposes a workflow_dispatch input for selecting fixture data' {
        $onKey = @('on', 'true', 'True') | Where-Object { $script:Workflow.Contains($_) } | Select-Object -First 1
        $script:Workflow[$onKey].workflow_dispatch.inputs.changed_files_path | Should -Not -BeNullOrEmpty
    }

    It 'declares least-privilege permissions' {
        $script:Workflow.permissions.contents | Should -Be 'read'
        $script:Workflow.permissions.'pull-requests' | Should -Be 'write'
    }

    It 'defines the test and assign-labels jobs' {
        $script:Workflow.jobs.Keys | Should -Contain 'test'
        $script:Workflow.jobs.Keys | Should -Contain 'assign-labels'
    }

    It 'makes assign-labels depend on the test job' {
        $script:Workflow.jobs.'assign-labels'.needs | Should -Be 'test'
    }

    It 'runs every job on ubuntu-latest' {
        foreach ($jobName in $script:Workflow.jobs.Keys) {
            $script:Workflow.jobs[$jobName].'runs-on' | Should -Be 'ubuntu-latest'
        }
    }

    It 'checks out the repo with actions/checkout@v4 in every job' {
        foreach ($jobName in $script:Workflow.jobs.Keys) {
            $steps = $script:Workflow.jobs[$jobName].steps
            $usesValues = $steps | ForEach-Object { $_.uses } | Where-Object { $_ }
            $usesValues | Should -Contain 'actions/checkout@v4'
        }
    }

    It 'uses shell: pwsh for PowerShell steps rather than invoking pwsh -Command' {
        $allSteps = $script:Workflow.jobs.Keys | ForEach-Object { $script:Workflow.jobs[$_].steps }
        $pwshSteps = $allSteps | Where-Object { $_.shell -eq 'pwsh' }
        $pwshSteps.Count | Should -BeGreaterThan 0
        foreach ($step in $pwshSteps) {
            $step.run | Should -Not -Match 'pwsh\s+-Command'
            $step.run | Should -Not -Match 'pwsh\s+-File'
        }
    }

    It 'references the Assign-PrLabels.ps1 script, and that script exists' {
        $allSteps = $script:Workflow.jobs.Keys | ForEach-Object { $script:Workflow.jobs[$_].steps }
        $runText = ($allSteps | ForEach-Object { $_.run } | Where-Object { $_ }) -join "`n"
        $runText | Should -Match 'Assign-PrLabels\.ps1'
        Test-Path -Path (Join-Path $script:RepoRoot 'Assign-PrLabels.ps1') -PathType Leaf | Should -BeTrue
    }

    It 'references the tests directory for the Pester run, and it exists' {
        $testJobSteps = $script:Workflow.jobs.test.steps
        $runText = ($testJobSteps | ForEach-Object { $_.run } | Where-Object { $_ }) -join "`n"
        $runText | Should -Match '\./tests'
        Test-Path -Path (Join-Path $script:RepoRoot 'tests') -PathType Container | Should -BeTrue
    }

    It 'references label-rules.json, and that file exists' {
        Test-Path -Path (Join-Path $script:RepoRoot 'label-rules.json') -PathType Leaf | Should -BeTrue
    }

    It 'only applies labels to a real PR, gated on the pull_request event' {
        $applyStep = $script:Workflow.jobs.'assign-labels'.steps | Where-Object { $_.name -eq 'Apply labels to the pull request' }
        $applyStep | Should -Not -BeNullOrEmpty
        $applyStep.if | Should -Match "github\.event_name == 'pull_request'"
    }
}

Describe 'actionlint validation' {
    BeforeAll {
        $script:ActionlintCmd = Get-Command -Name actionlint -ErrorAction SilentlyContinue
    }

    It 'passes actionlint with exit code 0' {
        if (-not $script:ActionlintCmd) {
            Set-ItResult -Skipped -Because 'actionlint is not installed in this environment'
            return
        }
        & actionlint $script:WorkflowPath
        $LASTEXITCODE | Should -Be 0
    }
}
