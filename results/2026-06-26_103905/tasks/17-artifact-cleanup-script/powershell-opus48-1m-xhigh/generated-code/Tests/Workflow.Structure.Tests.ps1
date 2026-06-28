# Structure / static-validation tests for the GitHub Actions workflow.
#
# These run on the host (they need powershell-yaml + actionlint, not Docker) and
# are tagged 'Structure' so they can be selected or skipped independently of the
# slow act integration suite.

BeforeAll {
    $script:Root         = Split-Path -Parent $PSScriptRoot
    $script:WorkflowPath = Join-Path $script:Root '.github/workflows/artifact-cleanup-script.yml'

    if (-not (Get-Module -ListAvailable powershell-yaml)) {
        throw "powershell-yaml is required for the structure tests (Install-Module powershell-yaml)."
    }
    Import-Module powershell-yaml -ErrorAction Stop

    $script:Yaml = Get-Content -LiteralPath $script:WorkflowPath -Raw | ConvertFrom-Yaml
}

Describe 'Workflow file - static validation' -Tag 'Structure' {

    It 'exists on disk' {
        Test-Path -LiteralPath $script:WorkflowPath | Should -BeTrue
    }

    It 'passes actionlint with exit code 0' {
        $output = & actionlint $script:WorkflowPath 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($output -join "`n")
    }
}

Describe 'Workflow triggers' -Tag 'Structure' {
    It 'is named' {
        $script:Yaml['name'] | Should -Not -BeNullOrEmpty
    }

    It 'defines the <Trigger> trigger' -ForEach @(
        @{ Trigger = 'push' }
        @{ Trigger = 'pull_request' }
        @{ Trigger = 'schedule' }
        @{ Trigger = 'workflow_dispatch' }
    ) {
        $on = $script:Yaml['on']
        $on.Keys | Should -Contain $Trigger
    }

    It 'exposes a dry_run workflow_dispatch input' {
        $script:Yaml['on']['workflow_dispatch']['inputs'].Keys | Should -Contain 'dry_run'
    }
}

Describe 'Workflow permissions and env' -Tag 'Structure' {
    It 'declares least-privilege contents: read permission' {
        $script:Yaml['permissions']['contents'] | Should -Be 'read'
    }

    It 'defines a DRY_RUN environment variable' {
        $script:Yaml['env'].Keys | Should -Contain 'DRY_RUN'
    }
}

Describe 'Workflow jobs and dependencies' -Tag 'Structure' {
    It 'defines the unit-tests and cleanup-plan jobs' {
        $jobs = $script:Yaml['jobs'].Keys
        $jobs | Should -Contain 'unit-tests'
        $jobs | Should -Contain 'cleanup-plan'
    }

    It 'makes cleanup-plan depend on unit-tests via needs' {
        $script:Yaml['jobs']['cleanup-plan']['needs'] | Should -Be 'unit-tests'
    }

    It 'checks out the repository with actions/checkout@v4' {
        $uses = foreach ($job in $script:Yaml['jobs'].Values) {
            foreach ($step in $job['steps']) {
                if ($step.Contains('uses')) { $step['uses'] }
            }
        }
        $uses | Should -Contain 'actions/checkout@v4'
    }

    It 'uses shell: pwsh on every run step (no pwsh -Command/-File invocation)' {
        $runSteps = foreach ($job in $script:Yaml['jobs'].Values) {
            foreach ($step in $job['steps']) {
                if ($step.Contains('run')) { $step }
            }
        }
        $runSteps.Count | Should -BeGreaterThan 0
        foreach ($step in $runSteps) {
            $step['shell'] | Should -Be 'pwsh'
        }
    }
}

Describe 'Workflow references real project files' -Tag 'Structure' {
    It 'references the entry script, which exists on disk' {
        $raw = Get-Content -LiteralPath $script:WorkflowPath -Raw
        $raw | Should -Match 'Invoke-ArtifactCleanup\.ps1'
        Test-Path (Join-Path $script:Root 'Invoke-ArtifactCleanup.ps1') | Should -BeTrue
    }

    It 'references the fixtures directory, which contains JSON fixtures' {
        $raw = Get-Content -LiteralPath $script:WorkflowPath -Raw
        $raw | Should -Match 'fixtures'
        $fixtures = Get-ChildItem (Join-Path $script:Root 'fixtures') -Filter '*.json'
        $fixtures.Count | Should -BeGreaterThan 0
    }

    It 'references the Pester test file, which exists on disk' {
        $raw = Get-Content -LiteralPath $script:WorkflowPath -Raw
        $raw | Should -Match 'ArtifactCleanup\.Tests\.ps1'
        Test-Path (Join-Path $script:Root 'Tests/ArtifactCleanup.Tests.ps1') | Should -BeTrue
    }
}
