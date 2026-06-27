<#
.SYNOPSIS
    Static structure tests for the GitHub Actions workflow.

.DESCRIPTION
    These are fast checks (no act): parse the YAML, assert the expected triggers /
    jobs / steps exist, confirm the workflow references files that actually exist,
    and confirm actionlint passes cleanly. Runnable via Invoke-Pester.
#>

BeforeAll {
    $script:root         = Join-Path $PSScriptRoot '..'
    $script:workflowPath = Join-Path $script:root '.github' 'workflows' 'artifact-cleanup-script.yml'

    if (-not (Get-Module -ListAvailable powershell-yaml)) {
        # Not strictly required - we fall back to text parsing if YAML module absent.
    }
}

Describe 'Workflow file' {
    It 'exists' {
        Test-Path $script:workflowPath | Should -BeTrue
    }
}

Describe 'Workflow structure (parsed YAML)' {
    BeforeAll {
        $script:yaml = $null
        if (Get-Module -ListAvailable powershell-yaml) {
            Import-Module powershell-yaml -ErrorAction SilentlyContinue
            $script:yaml = (Get-Content -Raw $script:workflowPath | ConvertFrom-Yaml)
        }
        $script:text = Get-Content -Raw $script:workflowPath
    }

    It 'declares the expected trigger events' {
        # YAML parses the bare "on:" key as boolean true in some parsers, so assert
        # against the raw text to stay parser-agnostic.
        $script:text | Should -Match '(?m)^\s*push:'
        $script:text | Should -Match '(?m)^\s*pull_request:'
        $script:text | Should -Match '(?m)^\s*schedule:'
        $script:text | Should -Match '(?m)^\s*workflow_dispatch:'
    }

    It 'defines least-privilege permissions' {
        $script:text | Should -Match 'permissions:'
        $script:text | Should -Match 'contents:\s*read'
    }

    It 'defines two jobs with a dependency between them' {
        $script:text | Should -Match '(?m)^\s*unit-tests:'
        $script:text | Should -Match '(?m)^\s*cleanup-plan:'
        $script:text | Should -Match 'needs:\s*unit-tests'
    }

    It 'uses actions/checkout@v4' {
        $script:text | Should -Match 'actions/checkout@v4'
    }

    It 'runs its steps with pwsh' {
        $script:text | Should -Match 'shell:\s*pwsh'
    }
}

Describe 'Workflow references real files' {
    BeforeAll { $script:text = Get-Content -Raw $script:workflowPath }

    It 'references Invoke-Cleanup.ps1 which exists' {
        $script:text | Should -Match 'Invoke-Cleanup\.ps1'
        Test-Path (Join-Path $script:root 'Invoke-Cleanup.ps1') | Should -BeTrue
    }

    It 'references the module which exists' {
        $script:text | Should -Match 'ArtifactCleanup\.psm1'
        Test-Path (Join-Path $script:root 'src' 'ArtifactCleanup.psm1') | Should -BeTrue
    }

    It 'references the unit test file which exists' {
        $script:text | Should -Match 'ArtifactCleanup\.Tests\.ps1'
        Test-Path (Join-Path $script:root 'tests' 'ArtifactCleanup.Tests.ps1') | Should -BeTrue
    }

    It 'references the default fixture which exists' {
        Test-Path (Join-Path $script:root 'fixtures' 'sample.json') | Should -BeTrue
    }
}

Describe 'actionlint validation' {
    It 'passes with exit code 0' {
        $out = & actionlint $script:workflowPath 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($out | Out-String)
    }
}
