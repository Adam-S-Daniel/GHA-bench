# Structural tests for the GitHub Actions workflow itself: valid triggers,
# expected jobs/steps, correct references to script files on disk, and a
# clean actionlint pass. These check the workflow file's shape directly;
# they are distinct from the functional pipeline tests that run through
# `act` (see Test-ActPipeline.ps1 / act-result.txt).

BeforeAll {
    $script:WorkflowPath = "$PSScriptRoot/.github/workflows/artifact-cleanup-script.yml"
    $script:WorkflowText = Get-Content -Raw -Path $script:WorkflowPath

    # No YAML module is guaranteed to be present, and PowerShell 7.4+ does
    # not ship ConvertFrom-Yaml. Parse just enough structure with regex,
    # which is sufficient to assert on triggers/jobs/steps without pulling
    # in an external dependency.
    function Get-YamlTopLevelKeys {
        param([string]$Text)
        ($Text -split "`n") | Where-Object { $_ -match '^[A-Za-z_][A-Za-z0-9_]*:' } | ForEach-Object {
            ($_ -split ':')[0].Trim()
        }
    }
}

Describe 'artifact-cleanup-script.yml structure' {
    It 'exists' {
        Test-Path $script:WorkflowPath | Should -BeTrue
    }

    It 'declares push, pull_request, workflow_dispatch and schedule triggers' {
        $script:WorkflowText | Should -Match '(?m)^on:'
        $script:WorkflowText | Should -Match '(?m)^\s*push:'
        $script:WorkflowText | Should -Match '(?m)^\s*pull_request:'
        $script:WorkflowText | Should -Match '(?m)^\s*workflow_dispatch:'
        $script:WorkflowText | Should -Match '(?m)^\s*schedule:'
        $script:WorkflowText | Should -Match "cron: '0 3 \* \* \*'"
    }

    It 'declares read-only top-level permissions' {
        $script:WorkflowText | Should -Match '(?m)^permissions:'
        $script:WorkflowText | Should -Match '(?m)^\s*contents:\s*read'
    }

    It 'defines both the unit-tests and cleanup-plan jobs' {
        $script:WorkflowText | Should -Match '(?m)^\s*unit-tests:'
        $script:WorkflowText | Should -Match '(?m)^\s*cleanup-plan:'
    }

    It 'makes cleanup-plan depend on unit-tests' {
        $script:WorkflowText | Should -Match 'needs:\s*unit-tests'
    }

    It 'uses actions/checkout@v4 and shell: pwsh (not `pwsh -Command`/-File)' {
        $script:WorkflowText | Should -Match 'actions/checkout@v4'
        $script:WorkflowText | Should -Match 'shell:\s*pwsh'
        $script:WorkflowText | Should -Not -Match 'run:\s*pwsh\s+-(Command|File)'
    }

    It 'references script and fixture files that actually exist in the repo' {
        $script:WorkflowText | Should -Match 'ArtifactCleanup\.Tests\.ps1'
        $script:WorkflowText | Should -Match 'WorkflowStructure\.Tests\.ps1'
        $script:WorkflowText | Should -Match 'Invoke-ArtifactCleanup\.ps1'
        $script:WorkflowText | Should -Match 'fixtures/artifacts-basic\.json'
        $script:WorkflowText | Should -Match 'fixtures/artifacts-keeplatest\.json'

        Test-Path "$PSScriptRoot/ArtifactCleanup.Tests.ps1" | Should -BeTrue
        Test-Path "$PSScriptRoot/WorkflowStructure.Tests.ps1" | Should -BeTrue
        Test-Path "$PSScriptRoot/Invoke-ArtifactCleanup.ps1" | Should -BeTrue
        Test-Path "$PSScriptRoot/fixtures/artifacts-basic.json" | Should -BeTrue
        Test-Path "$PSScriptRoot/fixtures/artifacts-keeplatest.json" | Should -BeTrue
    }

    It 'has three distinct top-level keys expected of a workflow file' {
        $keys = Get-YamlTopLevelKeys -Text $script:WorkflowText
        $keys | Should -Contain 'name'
        $keys | Should -Contain 'on'
        $keys | Should -Contain 'permissions'
        $keys | Should -Contain 'env'
        $keys | Should -Contain 'jobs'
    }
}

Describe 'actionlint validation' {
    It 'passes actionlint with no errors' {
        $actionlint = Get-Command actionlint -ErrorAction SilentlyContinue
        if (-not $actionlint) {
            Set-ItResult -Skipped -Because 'actionlint is not installed on this machine'
            return
        }

        $output = & actionlint $script:WorkflowPath 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($output | Out-String)
    }
}
