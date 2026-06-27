# Workflow.Tests.ps1
# Structural tests for the GitHub Actions workflow.
#
# These run both locally and inside the act container (via the workflow's Pester
# step). Tests that need external tools not guaranteed in the container
# (powershell-yaml, actionlint) are guarded and skipped when the tool is absent,
# so CI stays green while local runs perform the full, richer verification.

BeforeAll {
    $script:Root         = Split-Path $PSScriptRoot -Parent
    $script:WorkflowPath = Join-Path $script:Root '.github/workflows/dependency-license-checker.yml'
    $script:WorkflowText = Get-Content -LiteralPath $script:WorkflowPath -Raw

    $script:HasYaml = [bool](Get-Command ConvertFrom-Yaml -ErrorAction SilentlyContinue)
    if ($script:HasYaml) {
        $script:Wf = ConvertFrom-Yaml $script:WorkflowText
    }

    $script:HasActionlint = [bool](Get-Command actionlint -ErrorAction SilentlyContinue)
}

Describe 'Workflow file' {
    It 'exists' {
        Test-Path -LiteralPath $script:WorkflowPath | Should -BeTrue
    }
}

Describe 'Workflow triggers (text)' {
    It 'declares the <_> trigger' -ForEach @('push', 'pull_request', 'schedule', 'workflow_dispatch') {
        $script:WorkflowText | Should -Match "(?m)^\s*$([regex]::Escape($_))\s*:"
    }
}

Describe 'Workflow structure (text)' {
    It 'requests least-privilege contents: read permission' {
        $script:WorkflowText | Should -Match '(?m)contents:\s*read'
    }
    It 'checks out the repo with actions/checkout@v4' {
        $script:WorkflowText | Should -Match 'uses:\s*actions/checkout@v4'
    }
    It 'uses pwsh as the run shell' {
        $script:WorkflowText | Should -Match 'shell:\s*pwsh'
    }
    It 'references the checker script Invoke-LicenseCheck.ps1' {
        $script:WorkflowText | Should -Match 'Invoke-LicenseCheck\.ps1'
    }
    It 'declares a job dependency via needs:' {
        $script:WorkflowText | Should -Match '(?m)needs:\s*license-check'
    }
}

Describe 'Referenced files exist on disk' {
    It 'the checker entry script exists' {
        Test-Path -LiteralPath (Join-Path $script:Root 'Invoke-LicenseCheck.ps1') | Should -BeTrue
    }
    It 'the module exists' {
        Test-Path -LiteralPath (Join-Path $script:Root 'src/LicenseChecker.psm1') | Should -BeTrue
    }
    It 'the license config referenced by the workflow exists' {
        Test-Path -LiteralPath (Join-Path $script:Root 'config/license-config.json') | Should -BeTrue
    }
}

Describe 'Workflow structure (parsed YAML)' {
    It 'parses and defines the expected triggers' {
        if (-not $script:HasYaml) { Set-ItResult -Skipped -Because 'powershell-yaml not available'; return }
        $on = $script:Wf['on']
        $on.Keys | Should -Contain 'push'
        $on.Keys | Should -Contain 'pull_request'
        $on.Keys | Should -Contain 'schedule'
        $on.Keys | Should -Contain 'workflow_dispatch'
    }

    It 'defines license-check and gate jobs, with gate depending on license-check' {
        if (-not $script:HasYaml) { Set-ItResult -Skipped -Because 'powershell-yaml not available'; return }
        $jobs = $script:Wf['jobs']
        $jobs.Keys | Should -Contain 'license-check'
        $jobs.Keys | Should -Contain 'gate'
        $jobs['gate']['needs'] | Should -Be 'license-check'
    }

    It 'has a checkout step in the license-check job' {
        if (-not $script:HasYaml) { Set-ItResult -Skipped -Because 'powershell-yaml not available'; return }
        $uses = $script:Wf['jobs']['license-check']['steps'] | ForEach-Object { $_['uses'] }
        $uses | Should -Contain 'actions/checkout@v4'
    }
}

Describe 'actionlint validation' {
    It 'passes actionlint with exit code 0' {
        if (-not $script:HasActionlint) { Set-ItResult -Skipped -Because 'actionlint not installed'; return }
        $null = & actionlint $script:WorkflowPath 2>&1
        $LASTEXITCODE | Should -Be 0
    }
}
