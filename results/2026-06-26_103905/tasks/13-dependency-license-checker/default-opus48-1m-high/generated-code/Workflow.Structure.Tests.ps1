#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
    Workflow structure tests.

    These validate the GitHub Actions workflow file itself:
      * it is valid YAML with the expected triggers / jobs / steps,
      * it references script files that actually exist,
      * it passes actionlint.

    YAML is parsed with python3 + PyYAML (emitted as JSON) since PowerShell has
    no built-in YAML reader.
#>

BeforeAll {
    $script:Root         = $PSScriptRoot
    $script:WorkflowPath = Join-Path $Root '.github/workflows/dependency-license-checker.yml'

    # Parse the workflow YAML into a PowerShell object via python3 -> JSON.
    $json = python3 -c "import json,sys,yaml; print(json.dumps(yaml.safe_load(open(sys.argv[1]))))" $WorkflowPath
    $script:Workflow = $json | ConvertFrom-Json
}

Describe 'Workflow file' {
    It 'exists' {
        Test-Path -LiteralPath $script:WorkflowPath | Should -BeTrue
    }

    It 'is valid YAML (parses without error)' {
        $script:Workflow | Should -Not -BeNullOrEmpty
    }
}

Describe 'Triggers' {
    # NOTE: PyYAML parses the YAML key `on:` as the boolean True, so the trigger
    # block is keyed by $true on the parsed object.
    BeforeAll { $script:On = $script:Workflow.PSObject.Properties['True'].Value }

    It 'triggers on push' { $script:On.PSObject.Properties.Name | Should -Contain 'push' }
    It 'triggers on pull_request' { $script:On.PSObject.Properties.Name | Should -Contain 'pull_request' }
    It 'triggers on a schedule' { $script:On.PSObject.Properties.Name | Should -Contain 'schedule' }
    It 'supports workflow_dispatch' { $script:On.PSObject.Properties.Name | Should -Contain 'workflow_dispatch' }
}

Describe 'Permissions' {
    It 'declares least-privilege read access to contents' {
        $script:Workflow.permissions.contents | Should -Be 'read'
    }
}

Describe 'Jobs' {
    It 'defines the unit-tests and compliance-report jobs' {
        $jobs = $script:Workflow.jobs.PSObject.Properties.Name
        $jobs | Should -Contain 'unit-tests'
        $jobs | Should -Contain 'compliance-report'
    }

    It 'makes compliance-report depend on unit-tests' {
        $script:Workflow.jobs.'compliance-report'.needs | Should -Be 'unit-tests'
    }

    It 'checks out the repository with actions/checkout@v4 in every job' {
        foreach ($jobName in $script:Workflow.jobs.PSObject.Properties.Name) {
            $uses = $script:Workflow.jobs.$jobName.steps.uses
            ($uses -contains 'actions/checkout@v4') | Should -BeTrue -Because "$jobName must checkout"
        }
    }

    It 'runs its steps with the pwsh shell' {
        $shells = $script:Workflow.jobs.'compliance-report'.steps |
            Where-Object { $_.run } | ForEach-Object { $_.shell }
        $shells | Should -Contain 'pwsh'
    }
}

Describe 'Referenced script files exist' {
    It 'references LicenseChecker.Tests.ps1 which exists' {
        $body = Get-Content -LiteralPath $script:WorkflowPath -Raw
        $body | Should -Match 'LicenseChecker\.Tests\.ps1'
        Test-Path (Join-Path $script:Root 'LicenseChecker.Tests.ps1') | Should -BeTrue
    }
    It 'references Invoke-LicenseCheck.ps1 which exists' {
        $body = Get-Content -LiteralPath $script:WorkflowPath -Raw
        $body | Should -Match 'Invoke-LicenseCheck\.ps1'
        Test-Path (Join-Path $script:Root 'Invoke-LicenseCheck.ps1') | Should -BeTrue
    }
    It 'has the LicenseChecker.psm1 module present' {
        Test-Path (Join-Path $script:Root 'LicenseChecker.psm1') | Should -BeTrue
    }
}

Describe 'actionlint' {
    It 'passes with exit code 0' {
        $null = & actionlint $script:WorkflowPath 2>&1
        $LASTEXITCODE | Should -Be 0
    }
}
