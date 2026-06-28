#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
    WORKFLOW STRUCTURE TESTS (no `act` required — fast and deterministic).

    These verify the workflow file independently of running it:
      * actionlint passes cleanly (exit code 0)
      * the workflow references script/config files that actually exist
      * the parsed structure has the expected triggers, jobs and steps
#>

BeforeAll {
    $script:RepoRoot     = Split-Path $PSScriptRoot -Parent
    $script:WorkflowPath = Join-Path $RepoRoot '.github/workflows/pr-label-assigner.yml'
    $script:WorkflowText = Get-Content -LiteralPath $WorkflowPath -Raw
}

Describe 'Workflow file - existence and actionlint' {

    It 'exists at .github/workflows/pr-label-assigner.yml' {
        Test-Path -LiteralPath $WorkflowPath | Should -BeTrue
    }

    It 'passes actionlint with exit code 0' {
        $actionlint = Get-Command actionlint -ErrorAction SilentlyContinue
        if (-not $actionlint) { Set-ItResult -Skipped -Because 'actionlint not installed' ; return }

        $output = & actionlint $WorkflowPath 2>&1
        $exit = $LASTEXITCODE
        if ($exit -ne 0) { Write-Host ($output | Out-String) }
        $exit | Should -Be 0
    }

    It 'is parseable as YAML when a YAML parser is available' {
        $yamlModule = Get-Module -ListAvailable -Name 'powershell-yaml' | Select-Object -First 1
        if (-not $yamlModule) { Set-ItResult -Skipped -Because 'powershell-yaml not installed' ; return }

        Import-Module powershell-yaml -Force
        { ConvertFrom-Yaml $WorkflowText } | Should -Not -Throw
    }
}

Describe 'Workflow file - triggers' {

    It 'declares the <_> trigger' -ForEach @('push', 'pull_request', 'workflow_dispatch', 'schedule') {
        $WorkflowText | Should -Match "(?m)^\s+$([regex]::Escape($_)):"
    }

    It 'uses a valid cron expression for the schedule trigger' {
        $WorkflowText | Should -Match "cron:\s*'[\d\*/, \-]+'"
    }
}

Describe 'Workflow file - jobs and dependencies' {

    It 'defines a unit-tests job and an assign-labels job' {
        $WorkflowText | Should -Match '(?m)^\s+unit-tests:'
        $WorkflowText | Should -Match '(?m)^\s+assign-labels:'
    }

    It 'makes assign-labels depend on unit-tests (needs:)' {
        $WorkflowText | Should -Match 'needs:\s*unit-tests'
    }

    It 'declares permissions' {
        $WorkflowText | Should -Match '(?m)^permissions:'
        $WorkflowText | Should -Match 'contents:\s*read'
    }

    It 'sets the config/fixture env vars' {
        $WorkflowText | Should -Match 'RULES_FILE:'
        $WorkflowText | Should -Match 'CHANGED_FILES_FILE:'
    }

    It 'runs on ubuntu-latest' {
        $WorkflowText | Should -Match 'runs-on:\s*ubuntu-latest'
    }
}

Describe 'Workflow file - steps reference real files' {

    It 'checks out the repo with actions/checkout@v4' {
        $WorkflowText | Should -Match 'actions/checkout@v4'
    }

    It 'uses the pwsh shell (not "pwsh -Command" from bash)' {
        $WorkflowText | Should -Match 'shell:\s*pwsh'
    }

    It 'references the entry script <_>, which exists' -ForEach @('Invoke-PRLabelAssigner.ps1') {
        $WorkflowText | Should -Match ([regex]::Escape($_))
        Test-Path -LiteralPath (Join-Path $RepoRoot $_) | Should -BeTrue
    }

    It 'references the unit-test file <_>, which exists' -ForEach @('tests/PRLabelAssigner.Tests.ps1') {
        $WorkflowText | Should -Match ([regex]::Escape($_))
        Test-Path -LiteralPath (Join-Path $RepoRoot $_) | Should -BeTrue
    }

    It 'all referenced project files exist on disk' {
        foreach ($f in @('PRLabelAssigner.psm1', 'Invoke-PRLabelAssigner.ps1', 'labeler-rules.json', 'fixtures/changed-files.txt')) {
            Test-Path -LiteralPath (Join-Path $RepoRoot $f) | Should -BeTrue -Because "workflow/script depends on $f"
        }
    }
}
