#requires -Modules Pester

<#
    Workflow structure tests (fast, no act required).

    Parses the workflow YAML and asserts the expected triggers, jobs and steps;
    verifies the workflow references real script files; and asserts actionlint
    passes cleanly.
#>

BeforeAll {
    Import-Module powershell-yaml -ErrorAction Stop

    $script:ProjectDir   = $PSScriptRoot
    $script:WorkflowPath = Join-Path $script:ProjectDir '.github/workflows/environment-matrix-generator.yml'
    $script:Raw          = Get-Content $script:WorkflowPath -Raw
    $script:Wf           = $script:Raw | ConvertFrom-Yaml
}

Describe 'Workflow file' {
    It 'exists and is valid YAML' {
        Test-Path $script:WorkflowPath | Should -BeTrue
        $script:Wf | Should -Not -BeNullOrEmpty
    }

    It 'has a human-readable name' {
        $script:Wf.name | Should -Be 'Environment Matrix Generator'
    }
}

Describe 'Triggers' {
    # powershell-yaml parses the bare `on:` key as the boolean true, so assert
    # on the raw text for trigger presence (a known YAML 1.1 quirk).
    It 'fires on push, pull_request, workflow_dispatch and schedule' {
        $script:Raw | Should -Match '(?m)^\s*push:'
        $script:Raw | Should -Match '(?m)^\s*pull_request:'
        $script:Raw | Should -Match '(?m)^\s*workflow_dispatch:'
        $script:Raw | Should -Match '(?m)^\s*schedule:'
        $script:Raw | Should -Match "cron: '0 6 \* \* 1'"
    }
}

Describe 'Permissions and env' {
    It 'declares least-privilege contents: read' {
        $script:Wf.permissions.contents | Should -Be 'read'
    }
    It 'defines workflow-level environment variables' {
        $script:Wf.env.PRIMARY_FIXTURE | Should -Be 'basic'
        $script:Wf.env.MAX_MATRIX_SIZE | Should -Be '256'
    }
}

Describe 'Jobs and dependencies' {
    It 'defines the three pipeline jobs' {
        $script:Wf.jobs.Keys | Should -Contain 'test'
        $script:Wf.jobs.Keys | Should -Contain 'generate-matrix'
        $script:Wf.jobs.Keys | Should -Contain 'build'
    }
    It 'wires job dependencies via needs:' {
        $script:Wf.jobs['generate-matrix'].needs | Should -Be 'test'
        $script:Wf.jobs['build'].needs | Should -Be 'generate-matrix'
    }
    It 'consumes the generated matrix via fromJson on the build job' {
        ($script:Wf.jobs['build'].strategy.matrix) | Should -Match 'fromJson\(needs\.generate-matrix\.outputs\.matrix\)'
    }
    It 'exposes the matrix as a job output' {
        $script:Wf.jobs['generate-matrix'].outputs.matrix | Should -Match 'steps\.generate\.outputs\.matrix'
    }
}

Describe 'Steps' {
    It 'checks out the repo with actions/checkout@v4 in every checkout step' {
        $script:Raw | Should -Match 'actions/checkout@v4'
        # No checkout step should reference an older major version.
        $script:Raw | Should -Not -Match 'actions/checkout@v[123]\b'
    }
    It 'runs all PowerShell steps with shell: pwsh' {
        $script:Raw | Should -Match 'shell: pwsh'
    }
    It 'invokes Invoke-Pester against the unit test file' {
        $testSteps = $script:Wf.jobs['test'].steps | Where-Object { $_.run -match 'Invoke-Pester' }
        $testSteps | Should -Not -BeNullOrEmpty
        ($testSteps.run -join "`n") | Should -Match 'BuildMatrix\.Tests\.ps1'
    }
}

Describe 'Script references resolve on disk' {
    It 'references New-BuildMatrix.ps1 which exists' {
        $script:Raw | Should -Match 'New-BuildMatrix\.ps1'
        Test-Path (Join-Path $script:ProjectDir 'New-BuildMatrix.ps1') | Should -BeTrue
    }
    It 'references BuildMatrix.Tests.ps1 which exists' {
        Test-Path (Join-Path $script:ProjectDir 'BuildMatrix.Tests.ps1') | Should -BeTrue
    }
    It 'has the BuildMatrix.psm1 module and fixtures present' {
        Test-Path (Join-Path $script:ProjectDir 'BuildMatrix.psm1') | Should -BeTrue
        (Get-ChildItem (Join-Path $script:ProjectDir 'fixtures') -Filter *.json).Count | Should -BeGreaterThan 0
    }
}

Describe 'actionlint validation' {
    It 'passes actionlint with exit code 0' {
        $null = & actionlint $script:WorkflowPath 2>&1
        $LASTEXITCODE | Should -Be 0
    }
}
