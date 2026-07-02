<#
    Validates the GitHub Actions workflow itself: structure (parsed YAML),
    static analysis (actionlint), and actual execution via `act` in Docker.

    Per the task requirements, the *runtime* behavior of the compliance
    report (Approved/Denied/Unknown per dependency) is verified only through
    the real pipeline here -- the script is never invoked directly in this
    file. Pure-function logic is already covered test-first in
    DependencyLicenseChecker.Tests.ps1.
#>

BeforeAll {
    $RepoRoot = $PSScriptRoot
    $WorkflowPath = Join-Path $RepoRoot '.github/workflows/dependency-license-checker.yml'
    $ActResultPath = Join-Path $RepoRoot 'act-result.txt'
}

Describe 'Workflow structure' {
    BeforeAll {
        Import-Module powershell-yaml -ErrorAction Stop
        $Workflow = Get-Content -LiteralPath $WorkflowPath -Raw | ConvertFrom-Yaml -Ordered
    }

    It 'exists at the expected path' {
        Test-Path -LiteralPath $WorkflowPath -PathType Leaf | Should -BeTrue
    }

    It 'defines push, pull_request, workflow_dispatch, and schedule triggers' {
        $Workflow.on.Keys | Should -Contain 'push'
        $Workflow.on.Keys | Should -Contain 'pull_request'
        $Workflow.on.Keys | Should -Contain 'workflow_dispatch'
        $Workflow.on.Keys | Should -Contain 'schedule'
    }

    It 'declares read-only contents permissions' {
        $Workflow.permissions.contents | Should -Be 'read'
    }

    It 'defines the license-check job with an npm and a python matrix scenario' {
        $Workflow.jobs.Keys | Should -Contain 'license-check'
        $scenarios = $Workflow.jobs.'license-check'.strategy.matrix.scenario
        $scenarios.name | Should -Contain 'npm'
        $scenarios.name | Should -Contain 'python'
    }

    It 'defines a report-summary job that depends on license-check' {
        $Workflow.jobs.Keys | Should -Contain 'report-summary'
        $Workflow.jobs.'report-summary'.needs | Should -Be 'license-check'
    }

    It 'uses actions/checkout@v4' {
        $steps = $Workflow.jobs.'license-check'.steps
        ($steps | Where-Object { $_.uses -eq 'actions/checkout@v4' }) | Should -Not -BeNullOrEmpty
    }

    It 'runs the license-check step with shell: pwsh' {
        $steps = $Workflow.jobs.'license-check'.steps
        $runStep = $steps | Where-Object { $_.run -match 'Invoke-LicenseCheck\.ps1' }
        $runStep | Should -Not -BeNullOrEmpty
        $runStep.shell | Should -Be 'pwsh'
    }

    It 'references script, fixture, and config files that actually exist in the repo' {
        (Join-Path $RepoRoot 'Invoke-LicenseCheck.ps1') | Should -Exist
        (Join-Path $RepoRoot 'DependencyLicenseChecker.psm1') | Should -Exist
        foreach ($scenario in $Workflow.jobs.'license-check'.strategy.matrix.scenario) {
            (Join-Path $RepoRoot $scenario.manifest) | Should -Exist
        }
        (Join-Path $RepoRoot $Workflow.env.LICENSE_POLICY_PATH) | Should -Exist
        (Join-Path $RepoRoot $Workflow.env.LICENSE_LOOKUP_PATH) | Should -Exist
    }
}

Describe 'actionlint validation' {
    It 'passes actionlint with exit code 0' {
        $output = & actionlint $WorkflowPath 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($output -join "`n")
    }
}

Describe 'Workflow execution via act' {
    BeforeAll {
        # Build an isolated temp git repo containing exactly the project files
        # the workflow needs, then drive the *actual* GitHub Actions pipeline
        # with `act push`. Every assertion below is derived from what the
        # pipeline itself printed -- the script is not called directly.
        # Start each test run with a clean artifact rather than accumulating
        # output across unrelated Invoke-Pester invocations.
        Remove-Item -LiteralPath $ActResultPath -Force -ErrorAction SilentlyContinue

        $TempRepo = Join-Path ([System.IO.Path]::GetTempPath()) "license-checker-act-$([System.Guid]::NewGuid())"
        New-Item -ItemType Directory -Path $TempRepo | Out-Null

        foreach ($item in 'Invoke-LicenseCheck.ps1', 'DependencyLicenseChecker.psm1', 'fixtures', 'config', '.github', '.actrc') {
            Copy-Item -Path (Join-Path $RepoRoot $item) -Destination $TempRepo -Recurse
        }

        Push-Location $TempRepo
        try {
            git init --quiet -b main
            git config user.email 'test@example.com'
            git config user.name 'Test Runner'
            git add -A
            git commit --quiet -m 'test commit'

            $script:ActOutput = & act push --rm --pull=false 2>&1 | Out-String
            $script:ActExitCode = $LASTEXITCODE
        }
        finally {
            Pop-Location
        }

        $delimiter = '=' * 80
        $header = "$delimiter`nTEST CASE: license-check matrix (npm scenario + python scenario) via act push`n$delimiter"
        $footer = "$delimiter`nEXIT CODE: $script:ActExitCode`n$delimiter`n"
        Add-Content -LiteralPath $ActResultPath -Value $header
        Add-Content -LiteralPath $ActResultPath -Value $script:ActOutput
        Add-Content -LiteralPath $ActResultPath -Value $footer
    }

    AfterAll {
        if ($TempRepo -and (Test-Path -LiteralPath $TempRepo)) {
            Remove-Item -LiteralPath $TempRepo -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'exits with code 0' {
        $script:ActExitCode | Should -Be 0 -Because $script:ActOutput
    }

    It 'writes the act-result.txt artifact' {
        Test-Path -LiteralPath $ActResultPath | Should -BeTrue
    }

    It 'reports Job succeeded for every job (2 matrix jobs + 1 summary job)' {
        $matches = [regex]::Matches($script:ActOutput, 'Job succeeded')
        $matches.Count | Should -Be 3
    }

    It 'produces the exact expected compliance report for the npm scenario' {
        $script:ActOutput | Should -Match ([regex]::Escape('REPORT_LINE|left-pad|1.3.0|MIT|Approved'))
        $script:ActOutput | Should -Match ([regex]::Escape('REPORT_LINE|gpl-lib|2.0.0|GPL-3.0|Denied'))
        $script:ActOutput | Should -Match ([regex]::Escape('REPORT_LINE|mystery-pkg|1.0.0|UNKNOWN|Unknown'))
    }

    It 'produces the exact expected compliance report for the python scenario' {
        $script:ActOutput | Should -Match ([regex]::Escape('REPORT_LINE|requests|2.31.0|Apache-2.0|Approved'))
        $script:ActOutput | Should -Match ([regex]::Escape('REPORT_LINE|copyleft-pkg|1.0.0|AGPL-3.0|Denied'))
        $script:ActOutput | Should -Match ([regex]::Escape('REPORT_LINE|obscure-pkg|0.1.0|UNKNOWN|Unknown'))
    }

    It 'produces the exact expected summary counts for both scenarios' {
        $matches = [regex]::Matches($script:ActOutput, [regex]::Escape('SUMMARY|Approved=1|Denied=1|Unknown=1|Total=3'))
        $matches.Count | Should -Be 2
    }
}
