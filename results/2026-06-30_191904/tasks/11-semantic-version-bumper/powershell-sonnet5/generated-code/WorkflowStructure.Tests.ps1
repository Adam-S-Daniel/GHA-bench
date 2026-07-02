<#
    Pester tests that validate the GitHub Actions workflow file itself:
    its structure (triggers/jobs/steps), that it references real script
    files, and that it passes `actionlint`. These run locally (no `act`
    needed) since they check the workflow's static shape, not its runtime
    behavior in a container -- the runtime behavior is covered separately
    by ActIntegration.Tests.ps1, which drives the workflow via `act`.
#>

BeforeAll {
    Import-Module powershell-yaml -ErrorAction Stop
    $script:WorkflowPath = Join-Path $PSScriptRoot '.github/workflows/semantic-version-bumper.yml'
    $script:WorkflowYaml = ConvertFrom-Yaml -Yaml (Get-Content -Path $script:WorkflowPath -Raw) -Ordered
}

Describe 'semantic-version-bumper.yml structure' {
    It 'exists at the expected workflow path' {
        Test-Path -LiteralPath $script:WorkflowPath -PathType Leaf | Should -BeTrue
    }

    It 'declares push, pull_request, and workflow_dispatch triggers' {
        # The YAML key "on" is parsed by powershell-yaml as the boolean key
        # True (YAML 1.1 treats bare "on"/"off" as booleans), not a string.
        $triggers = $script:WorkflowYaml['on']
        if (-not $triggers) { $triggers = $script:WorkflowYaml[$true] }
        $triggers.Keys | Should -Contain 'push'
        $triggers.Keys | Should -Contain 'pull_request'
        $triggers.Keys | Should -Contain 'workflow_dispatch'
    }

    It 'defines a version-bump job on ubuntu-latest' {
        $script:WorkflowYaml.jobs.Keys | Should -Contain 'version-bump'
        $script:WorkflowYaml.jobs['version-bump']['runs-on'] | Should -Be 'ubuntu-latest'
    }

    It 'declares read-only contents permissions' {
        $script:WorkflowYaml.permissions.contents | Should -Be 'read'
    }

    It 'checks out the repository with full git history' {
        $steps = $script:WorkflowYaml.jobs['version-bump'].steps
        $checkout = $steps | Where-Object { $_.uses -like 'actions/checkout@*' }
        $checkout | Should -Not -BeNullOrEmpty
        $checkout.with.'fetch-depth' | Should -Be 0
    }

    It 'runs Pester tests and the version-bump script using shell: pwsh' {
        $steps = $script:WorkflowYaml.jobs['version-bump'].steps
        $pesterStep = $steps | Where-Object { $_.run -match 'Invoke-Pester' }
        $pesterStep | Should -Not -BeNullOrEmpty
        $pesterStep.shell | Should -Be 'pwsh'

        $bumpStep = $steps | Where-Object { $_.run -match 'Invoke-VersionBump\.ps1' }
        $bumpStep | Should -Not -BeNullOrEmpty
        $bumpStep.shell | Should -Be 'pwsh'
    }
}

Describe 'semantic-version-bumper.yml referenced files' {
    It 'references VersionBumper.Tests.ps1, which exists in the repo' {
        $path = Join-Path $PSScriptRoot 'VersionBumper.Tests.ps1'
        Test-Path -LiteralPath $path -PathType Leaf | Should -BeTrue
    }

    It 'references Invoke-VersionBump.ps1, which exists in the repo' {
        $path = Join-Path $PSScriptRoot 'Invoke-VersionBump.ps1'
        Test-Path -LiteralPath $path -PathType Leaf | Should -BeTrue
    }

    It 'references VersionBumper.psm1 (imported by both scripts above), which exists in the repo' {
        $path = Join-Path $PSScriptRoot 'VersionBumper.psm1'
        Test-Path -LiteralPath $path -PathType Leaf | Should -BeTrue
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
        $exitCode = $LASTEXITCODE

        if ($exitCode -ne 0) {
            Write-Host ($output -join "`n")
        }
        $exitCode | Should -Be 0
    }
}
