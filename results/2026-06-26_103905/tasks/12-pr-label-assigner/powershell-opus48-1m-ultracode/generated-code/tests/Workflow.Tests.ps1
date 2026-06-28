# Workflow.Tests.ps1
#
# Static (no-Docker) checks of the GitHub Actions workflow file:
#   * it parses as YAML and has the expected triggers / jobs / steps
#   * it references the script files that actually exist on disk
#   * it passes `actionlint`
#
# These run fast on the host and need neither act nor Docker.

BeforeAll {
    $script:repoRoot     = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:workflowPath = Join-Path $script:repoRoot '.github/workflows/pr-label-assigner.yml'

    $script:hasYaml = $null -ne (Get-Module -ListAvailable -Name powershell-yaml)
    if ($script:hasYaml) {
        Import-Module powershell-yaml -ErrorAction Stop
        $script:wf = ConvertFrom-Yaml (Get-Content -Raw -LiteralPath $script:workflowPath)
    }

    # Flatten every 'run' / 'uses' string across all jobs/steps for easy searching.
    $script:allRun  = @()
    $script:allUses = @()
    if ($script:hasYaml) {
        foreach ($jobName in $script:wf['jobs'].Keys) {
            foreach ($step in $script:wf['jobs'][$jobName]['steps']) {
                if ($step.ContainsKey('run'))  { $script:allRun  += [string]$step['run'] }
                if ($step.ContainsKey('uses')) { $script:allUses += [string]$step['uses'] }
            }
        }
    }
}

Describe 'Workflow file presence and linting' {
    It 'the workflow file exists' {
        Test-Path -LiteralPath $script:workflowPath | Should -BeTrue
    }

    It 'passes actionlint with exit code 0' {
        $output = & actionlint $script:workflowPath 2>&1
        $code = $LASTEXITCODE
        $code | Should -Be 0 -Because ("actionlint output:`n" + ($output -join "`n"))
    }
}

Describe 'Workflow structure' -Skip:($null -eq (Get-Module -ListAvailable -Name powershell-yaml)) {
    It 'has a workflow name' {
        $script:wf['name'] | Should -Not -BeNullOrEmpty
    }

    It 'declares the expected trigger events' {
        $triggers = $script:wf['on']
        $triggers.Keys | Should -Contain 'push'
        $triggers.Keys | Should -Contain 'pull_request'
        $triggers.Keys | Should -Contain 'workflow_dispatch'
        $triggers.Keys | Should -Contain 'schedule'
    }

    It 'declares permissions (least privilege)' {
        $script:wf['permissions']['contents']      | Should -Be 'read'
        $script:wf['permissions']['pull-requests'] | Should -Be 'write'
    }

    It 'defines the shared env (config + fixtures dir)' {
        $script:wf['env']['LABELER_CONFIG'] | Should -Be 'config/labeler-config.json'
        $script:wf['env']['FIXTURES_DIR']   | Should -Be 'fixtures'
    }

    It 'defines a test job and an assign-labels job' {
        $script:wf['jobs'].Keys | Should -Contain 'test'
        $script:wf['jobs'].Keys | Should -Contain 'assign-labels'
    }

    It 'makes assign-labels depend on the test job' {
        # 'needs' may parse as a scalar or a list; normalise to an array.
        $needs = @($script:wf['jobs']['assign-labels']['needs'])
        $needs | Should -Contain 'test'
    }

    It 'uses actions/checkout@v4 to fetch the repo' {
        ($script:allUses -join "`n") | Should -Match 'actions/checkout@v4'
    }

    It 'invokes the multi-fixture runner script' {
        ($script:allRun -join "`n") | Should -Match 'Invoke-AllFixtures\.ps1'
    }

    It 'runs the Pester unit tests in the test job' {
        ($script:allRun -join "`n") | Should -Match 'Invoke-Pester'
    }
}

Describe 'Referenced files exist on disk' {
    It 'the module exists' {
        Test-Path -LiteralPath (Join-Path $script:repoRoot 'src/PRLabelAssigner.psm1') | Should -BeTrue
    }
    It 'the multi-fixture runner script exists' {
        Test-Path -LiteralPath (Join-Path $script:repoRoot 'scripts/Invoke-AllFixtures.ps1') | Should -BeTrue
    }
    It 'the single-PR CLI script exists' {
        Test-Path -LiteralPath (Join-Path $script:repoRoot 'scripts/Invoke-PRLabelAssigner.ps1') | Should -BeTrue
    }
    It 'the labeler config exists' {
        Test-Path -LiteralPath (Join-Path $script:repoRoot 'config/labeler-config.json') | Should -BeTrue
    }
    It 'the unit-test file referenced by the workflow exists' {
        Test-Path -LiteralPath (Join-Path $script:repoRoot 'tests/PRLabelAssigner.Tests.ps1') | Should -BeTrue
    }
    It 'all fixture cases exist' {
        $fixtures = Get-ChildItem -LiteralPath (Join-Path $script:repoRoot 'fixtures') -Filter 'case-*.txt'
        $fixtures.Count | Should -BeGreaterThan 0
    }
}
