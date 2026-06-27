# Workflow.Tests.ps1
#
# Static structure tests for the GitHub Actions workflow. These are fast
# (no Docker/act) and run as part of `Invoke-Pester`. They assert that the
# workflow YAML is well-formed, declares the expected triggers/jobs/steps,
# references the script files that actually exist on disk, and passes
# actionlint.

BeforeAll {
    $script:Root         = $PSScriptRoot
    $script:WorkflowPath = Join-Path $Root '.github/workflows/semantic-version-bumper.yml'

    Import-Module powershell-yaml -ErrorAction Stop
    $script:Yaml = ConvertFrom-Yaml (Get-Content -LiteralPath $WorkflowPath -Raw)
}

Describe 'Workflow file' {
    It 'exists' {
        Test-Path $WorkflowPath | Should -BeTrue
    }

    It 'is valid YAML that parses to a mapping' {
        $Yaml | Should -BeOfType [System.Collections.IDictionary]
    }

    It 'has a name' {
        $Yaml['name'] | Should -Be 'Semantic Version Bumper'
    }
}

Describe 'Triggers' {
    # In YAML, the "on" key may be parsed as the boolean true; powershell-yaml
    # keeps it as the string 'on'. Resolve whichever is present.
    BeforeAll {
        $script:On = if ($Yaml.Contains('on')) { $Yaml['on'] } else { $Yaml[$true] }
    }

    It 'declares the expected trigger events' {
        $keys = $On.Keys
        $keys | Should -Contain 'push'
        $keys | Should -Contain 'pull_request'
        $keys | Should -Contain 'schedule'
        $keys | Should -Contain 'workflow_dispatch'
    }

    It 'schedules a cron job' {
        $On['schedule'][0]['cron'] | Should -Not -BeNullOrEmpty
    }
}

Describe 'Permissions' {
    It 'declares least-privilege contents permission' {
        $Yaml['permissions']['contents'] | Should -Be 'read'
    }
}

Describe 'Jobs' {
    It 'defines the bump and report jobs' {
        $Yaml['jobs'].Keys | Should -Contain 'bump'
        $Yaml['jobs'].Keys | Should -Contain 'report'
    }

    It 'wires the report job to depend on the bump job' {
        $Yaml['jobs']['report']['needs'] | Should -Be 'bump'
    }

    It 'exposes job outputs from the bump job' {
        $Yaml['jobs']['bump']['outputs'].Keys | Should -Contain 'new_version'
        $Yaml['jobs']['bump']['outputs'].Keys | Should -Contain 'bump_type'
    }

    It 'runs on ubuntu-latest' {
        $Yaml['jobs']['bump']['runs-on'] | Should -Be 'ubuntu-latest'
    }
}

Describe 'Steps reference real files' {
    BeforeAll {
        $script:Steps = $Yaml['jobs']['bump']['steps']
        $script:StepText = ($Steps | ForEach-Object { ($_ | ConvertTo-Yaml) }) -join "`n"
    }

    It 'checks out the repository with actions/checkout@v4' {
        ($Steps | Where-Object { $_['uses'] -eq 'actions/checkout@v4' }).Count |
            Should -BeGreaterThan 0
    }

    It 'invokes Invoke-Bump.ps1, which exists' {
        $StepText | Should -Match 'Invoke-Bump\.ps1'
        Test-Path (Join-Path $Root 'Invoke-Bump.ps1') | Should -BeTrue
    }

    It 'runs the Pester test file, which exists' {
        $StepText | Should -Match 'SemanticVersionBumper\.Tests\.ps1'
        Test-Path (Join-Path $Root 'SemanticVersionBumper.Tests.ps1') | Should -BeTrue
    }

    It 'uses pwsh as the shell for run steps' {
        $runSteps = $Steps | Where-Object { $_.Contains('run') }
        $runSteps.Count | Should -BeGreaterThan 0
        foreach ($s in $runSteps) {
            $s['shell'] | Should -Be 'pwsh'
        }
    }

    It 'references the implementation file, which exists' {
        Test-Path (Join-Path $Root 'SemanticVersionBumper.ps1') | Should -BeTrue
    }
}

Describe 'actionlint' {
    It 'passes with no errors (exit code 0)' {
        $null = & actionlint $WorkflowPath 2>&1
        $LASTEXITCODE | Should -Be 0
    }
}
