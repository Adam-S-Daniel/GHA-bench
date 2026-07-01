#Requires -Modules Pester

<#
    Structural tests for the GitHub Actions workflow file itself: correct
    triggers, job wiring, and that every script path the workflow
    references actually exists in the repo. Written RED-first against a
    lightweight line-based reader (no powershell-yaml dependency, since
    that module isn't guaranteed to be available offline in the act
    container) before the workflow file's final shape was locked in.
#>

BeforeAll {
    $script:RepoRoot = Join-Path $PSScriptRoot '..'
    $script:WorkflowPath = Join-Path $RepoRoot '.github' 'workflows' 'dependency-license-checker.yml'
    $script:WorkflowContent = Get-Content -LiteralPath $script:WorkflowPath -Raw
    $script:WorkflowLines = Get-Content -LiteralPath $script:WorkflowPath
}

Describe 'dependency-license-checker.yml structure' {

    It 'exists at the expected path' {
        Test-Path -LiteralPath $script:WorkflowPath -PathType Leaf | Should -Be $true
    }

    Context 'triggers' {
        It 'triggers on push' {
            $script:WorkflowContent | Should -Match '(?m)^\s*push:'
        }

        It 'triggers on pull_request' {
            $script:WorkflowContent | Should -Match '(?m)^\s*pull_request:'
        }

        It 'triggers on a schedule' {
            $script:WorkflowContent | Should -Match '(?m)^\s*schedule:'
            $script:WorkflowContent | Should -Match 'cron:'
        }

        It 'supports manual workflow_dispatch' {
            $script:WorkflowContent | Should -Match '(?m)^\s*workflow_dispatch:'
        }
    }

    It 'declares least-privilege permissions' {
        $script:WorkflowContent | Should -Match '(?m)^permissions:'
        $script:WorkflowContent | Should -Match 'contents:\s*read'
    }

    It 'declares the manifest/policy/database paths as env vars' {
        $script:WorkflowContent | Should -Match 'MANIFEST_PATH:'
        $script:WorkflowContent | Should -Match 'POLICY_PATH:'
        $script:WorkflowContent | Should -Match 'LICENSE_DB_PATH:'
    }

    Context 'jobs' {
        It 'defines a test job' {
            $script:WorkflowContent | Should -Match '(?m)^\s*test:'
        }

        It 'defines a compliance-report job that depends on the test job' {
            $script:WorkflowContent | Should -Match '(?m)^\s*compliance-report:'
            $script:WorkflowContent | Should -Match '(?m)^\s*needs:\s*test'
        }

        It 'checks out the repository with actions/checkout@v4 in both jobs' {
            $checkoutCount = ($script:WorkflowLines | Select-String -Pattern 'actions/checkout@v4').Count
            $checkoutCount | Should -Be 2
        }

        It 'uses shell: pwsh for every run step (PowerShell-only requirement)' {
            $runStepCount = ($script:WorkflowLines | Select-String -Pattern '^\s*run:\s*\|').Count
            $pwshShellCount = ($script:WorkflowLines | Select-String -Pattern 'shell:\s*pwsh').Count
            $pwshShellCount | Should -Be $runStepCount
        }
    }

    Context 'script references' {
        It 'references Invoke-LicenseCheck.ps1, and that file exists' {
            $script:WorkflowContent | Should -Match 'Invoke-LicenseCheck\.ps1'
            Test-Path -LiteralPath (Join-Path $script:RepoRoot 'Invoke-LicenseCheck.ps1') -PathType Leaf | Should -Be $true
        }

        It 'references the tests directory used by Invoke-Pester, and that directory exists' {
            $script:WorkflowContent | Should -Match '-Path\s+\./tests'
            Test-Path -LiteralPath (Join-Path $script:RepoRoot 'tests') -PathType Container | Should -Be $true
        }

        It 'references default manifest/policy/database files that exist in the repo' {
            Test-Path -LiteralPath (Join-Path $script:RepoRoot 'package.json') -PathType Leaf | Should -Be $true
            Test-Path -LiteralPath (Join-Path $script:RepoRoot 'license-policy.json') -PathType Leaf | Should -Be $true
            Test-Path -LiteralPath (Join-Path $script:RepoRoot 'license-database.json') -PathType Leaf | Should -Be $true
        }
    }

    Context 'actionlint validation' {
        It 'passes actionlint with exit code 0' {
            $actionlintCmd = Get-Command -Name actionlint -ErrorAction SilentlyContinue
            if (-not $actionlintCmd) {
                Set-ItResult -Skipped -Because 'actionlint is not installed in this environment'
                return
            }

            & actionlint $script:WorkflowPath
            $LASTEXITCODE | Should -Be 0
        }
    }
}
