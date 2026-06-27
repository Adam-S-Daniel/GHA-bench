# Workflow-structure tests.
#
# These validate the GitHub Actions workflow itself: that it parses, declares
# the expected triggers/jobs/steps, references files that actually exist, and
# passes actionlint cleanly. Run locally (actionlint is not inside the act
# container) via: Invoke-Pester -Path tests/Workflow.Tests.ps1

BeforeAll {
    $script:Root = Split-Path -Parent $PSScriptRoot
    $script:WorkflowPath = Join-Path $script:Root '.github/workflows/secret-rotation-validator.yml'
    $script:Yaml = Get-Content -LiteralPath $script:WorkflowPath -Raw
}

Describe 'Workflow file' {
    It 'exists' {
        Test-Path -LiteralPath $script:WorkflowPath | Should -BeTrue
    }
}

Describe 'Triggers' {
    It 'declares push, pull_request, schedule and workflow_dispatch' {
        $script:Yaml | Should -Match '(?m)^\s*push:'
        $script:Yaml | Should -Match '(?m)^\s*pull_request:'
        $script:Yaml | Should -Match '(?m)^\s*schedule:'
        $script:Yaml | Should -Match '(?m)^\s*workflow_dispatch:'
    }

    It 'has a valid cron schedule' {
        $script:Yaml | Should -Match "cron:\s*'0 8 \* \* 1'"
    }
}

Describe 'Permissions and env' {
    It 'declares least-privilege contents: read' {
        $script:Yaml | Should -Match '(?m)^permissions:'
        $script:Yaml | Should -Match 'contents:\s*read'
    }

    It 'declares default environment variables' {
        $script:Yaml | Should -Match 'DEFAULT_CONFIG_PATH:'
        $script:Yaml | Should -Match 'DEFAULT_WARNING_WINDOW_DAYS:'
    }
}

Describe 'Jobs and dependencies' {
    It 'defines test and report jobs' {
        $script:Yaml | Should -Match '(?m)^\s{2}test:'
        $script:Yaml | Should -Match '(?m)^\s{2}report:'
    }

    It 'report job depends on the test job' {
        $script:Yaml | Should -Match 'needs:\s*test'
    }

    It 'uses actions/checkout@v4' {
        $script:Yaml | Should -Match 'actions/checkout@v4'
    }

    It 'runs pwsh steps' {
        $script:Yaml | Should -Match 'shell:\s*pwsh'
    }
}

Describe 'Script references resolve to real files' {
    It 'references the CLI entry point that exists on disk' {
        $script:Yaml | Should -Match 'Validate-SecretRotation\.ps1'
        Test-Path -LiteralPath (Join-Path $script:Root 'Validate-SecretRotation.ps1') | Should -BeTrue
    }

    It 'references the Pester test file that exists on disk' {
        $script:Yaml | Should -Match 'tests/SecretRotation\.Tests\.ps1'
        Test-Path -LiteralPath (Join-Path $script:Root 'tests/SecretRotation.Tests.ps1') | Should -BeTrue
    }

    It 'depends on the library that exists on disk' {
        Test-Path -LiteralPath (Join-Path $script:Root 'SecretRotation.ps1') | Should -BeTrue
    }
}

Describe 'actionlint' {
    It 'passes with exit code 0' {
        $actionlint = Get-Command actionlint -ErrorAction SilentlyContinue
        if (-not $actionlint) { Set-ItResult -Skipped -Because 'actionlint not installed'; return }
        & actionlint $script:WorkflowPath
        $LASTEXITCODE | Should -Be 0
    }
}
