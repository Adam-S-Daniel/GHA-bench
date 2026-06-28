#Requires -Modules Pester

<#
    Structure / static tests for the GitHub Actions workflow.

    These run locally (NOT inside act) and validate that the workflow is wired
    up correctly before we pay the cost of an act run:
      * the YAML parses and declares the expected triggers, jobs and steps,
      * the workflow references script files that actually exist on disk,
      * `actionlint` validates the workflow cleanly (exit code 0).
#>

BeforeAll {
    $script:Root         = Split-Path $PSScriptRoot -Parent
    $script:WorkflowPath = Join-Path $script:Root '.github/workflows/semantic-version-bumper.yml'
    $script:Raw          = Get-Content $script:WorkflowPath -Raw

    Import-Module powershell-yaml -ErrorAction Stop
    $script:Doc = ConvertFrom-Yaml $script:Raw

    # YAML 1.1 parses the bare key `on` as the boolean true (the "Norway
    # problem"). Locate the triggers map regardless of how it was keyed.
    function Get-TriggerMap {
        param($Document)
        foreach ($key in $Document.Keys) {
            if ("$key" -eq 'on' -or $key -eq $true) { return $Document[$key] }
        }
        return $null
    }
    $script:Triggers = Get-TriggerMap $script:Doc
}

Describe 'Workflow file' {
    It 'exists' {
        Test-Path $script:WorkflowPath | Should -BeTrue
    }

    It 'is valid, parseable YAML with a name' {
        $script:Doc | Should -Not -BeNullOrEmpty
        $script:Doc['name'] | Should -Be 'Semantic Version Bumper'
    }
}

Describe 'Triggers' {
    It 'declares a triggers (on:) section' {
        $script:Triggers | Should -Not -BeNullOrEmpty
    }

    It 'triggers on <_>' -ForEach @('push', 'pull_request', 'schedule', 'workflow_dispatch') {
        $script:Triggers.Keys | Should -Contain $_
    }

    It 'has a valid weekly cron schedule' {
        $cron = $script:Triggers['schedule'][0]['cron']
        $cron | Should -Match '^\S+\s+\S+\s+\S+\s+\S+\s+\S+$'
    }
}

Describe 'Jobs and dependencies' {
    It 'defines the expected jobs' {
        $script:Doc['jobs'].Keys | Should -Contain 'test'
        $script:Doc['jobs'].Keys | Should -Contain 'bump'
    }

    It 'runs the bump job only after the test job (needs:)' {
        $script:Doc['jobs']['bump']['needs'] | Should -Be 'test'
    }

    It 'declares least-privilege permissions (contents: read)' {
        $script:Doc['permissions']['contents'] | Should -Be 'read'
    }

    It 'centralises file locations as workflow env vars' {
        $script:Doc['env']['VERSION_FILE']   | Should -Be 'VERSION'
        $script:Doc['env']['COMMITS_FILE']   | Should -Be 'commits.txt'
        $script:Doc['env']['CHANGELOG_FILE'] | Should -Be 'CHANGELOG.md'
    }
}

Describe 'Steps' {
    It 'both jobs check out the repo with actions/checkout@v4' {
        $script:Raw | Should -Match 'actions/checkout@v4'
        ([regex]::Matches($script:Raw, 'actions/checkout@v4')).Count | Should -BeGreaterOrEqual 2
    }

    It 'uses the pwsh shell for run steps (per task requirement)' {
        $script:Raw | Should -Match 'shell:\s*pwsh'
    }

    It 'invokes the bumper script' {
        $script:Raw | Should -Match '\./Invoke-VersionBump\.ps1'
    }

    It 'runs the Pester test suite' {
        $script:Raw | Should -Match 'Invoke-Pester'
    }
}

Describe 'Referenced files exist on disk' {
    It 'the bumper entry script exists' {
        Test-Path (Join-Path $script:Root 'Invoke-VersionBump.ps1') | Should -BeTrue
    }
    It 'the module exists' {
        Test-Path (Join-Path $script:Root 'SemanticVersionBumper.psm1') | Should -BeTrue
    }
    It 'the tests directory referenced by the workflow exists' {
        Test-Path (Join-Path $script:Root 'tests') | Should -BeTrue
    }
}

Describe 'actionlint' {
    It 'validates the workflow with no errors (exit 0)' {
        $actionlint = Get-Command actionlint -ErrorAction SilentlyContinue
        if (-not $actionlint) {
            Set-ItResult -Skipped -Because 'actionlint is not installed on this machine'
            return
        }
        & actionlint $script:WorkflowPath 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 0
    }
}
