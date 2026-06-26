#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
    Workflow tests for the Dependency License Checker.

    Two layers:
      1. Structure tests  - parse the YAML, assert triggers/jobs/steps exist and
                            that the script paths the workflow references are real,
                            and that actionlint passes.
      2. Execution tests  - run the workflow through `act` for each fixture test
                            case, capture output to act-result.txt, and assert on
                            exact expected values + job success.
#>

# Load the test cases during DISCOVERY so the data-driven `-ForEach` blocks can
# enumerate them. (Pester's discovery and run phases use separate scopes, so the
# same file is also loaded again in BeforeAll for the run phase.)
BeforeDiscovery {
    $Cases = (Import-PowerShellDataFile (Join-Path $PSScriptRoot 'test-cases.psd1')).Cases
}

BeforeAll {
    $script:ProjectRoot  = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:WorkflowFile = Join-Path $script:ProjectRoot '.github' 'workflows' 'dependency-license-checker.yml'
    $script:ActResult    = Join-Path $script:ProjectRoot 'act-result.txt'
    $script:ActImage     = 'act-ubuntu-pwsh:latest'

    Import-Module powershell-yaml -ErrorAction Stop
    $script:Workflow = Get-Content -LiteralPath $script:WorkflowFile -Raw | ConvertFrom-Yaml
}

Describe 'Workflow structure' {

    It 'is valid, parseable YAML' {
        $script:Workflow | Should -Not -BeNullOrEmpty
    }

    It 'defines the expected trigger events' {
        # PSYaml parses the bare key `on:` to the boolean $true, so look it up dynamically.
        $onKey = $script:Workflow.Keys | Where-Object { "$_" -in @('on', 'True') } | Select-Object -First 1
        $triggers = $script:Workflow[$onKey]
        $triggers.Keys | Should -Contain 'push'
        $triggers.Keys | Should -Contain 'pull_request'
        $triggers.Keys | Should -Contain 'schedule'
        $triggers.Keys | Should -Contain 'workflow_dispatch'
    }

    It 'declares least-privilege read permissions' {
        $script:Workflow.permissions.contents | Should -Be 'read'
    }

    It 'defines both the unit-tests and license-check jobs' {
        $script:Workflow.jobs.Keys | Should -Contain 'unit-tests'
        $script:Workflow.jobs.Keys | Should -Contain 'license-check'
    }

    It 'orders license-check after unit-tests via a job dependency' {
        $script:Workflow.jobs['license-check'].needs | Should -Be 'unit-tests'
    }

    It 'checks out the repository with actions/checkout@v4' {
        $allSteps = $script:Workflow.jobs.Values.steps
        ($allSteps.uses | Where-Object { $_ -eq 'actions/checkout@v4' }) | Should -Not -BeNullOrEmpty
    }

    It 'runs PowerShell steps with shell: pwsh' {
        $runSteps = $script:Workflow.jobs.Values.steps | Where-Object { $_.run }
        foreach ($step in $runSteps) {
            $step.shell | Should -Be 'pwsh'
        }
    }

    It 'references script and config files that actually exist' {
        Test-Path (Join-Path $script:ProjectRoot 'Invoke-LicenseCheck.ps1')        | Should -BeTrue
        Test-Path (Join-Path $script:ProjectRoot 'src/DependencyLicenseChecker.psm1') | Should -BeTrue
        Test-Path (Join-Path $script:ProjectRoot 'tests/DependencyLicenseChecker.Tests.ps1') | Should -BeTrue
        Test-Path (Join-Path $script:ProjectRoot 'config/license-config.json')     | Should -BeTrue
        Test-Path (Join-Path $script:ProjectRoot 'config/license-db.json')         | Should -BeTrue
    }

    It 'passes actionlint with no errors' {
        Push-Location $script:ProjectRoot
        try {
            $null = & actionlint '.github/workflows/dependency-license-checker.yml' 2>&1
            $LASTEXITCODE | Should -Be 0
        }
        finally { Pop-Location }
    }
}

Describe 'Workflow execution via act' {

    BeforeAll {
        # Load the same case data for the run phase (separate scope from discovery).
        $script:Cases = (Import-PowerShellDataFile (Join-Path $PSScriptRoot 'test-cases.psd1')).Cases

        # Helper: build an isolated temp git repo containing the project files for
        # a given case, run `act push`, and return @{ ExitCode; Output }.
        function Invoke-ActCase {
            param([hashtable]$Case)

            $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("dlc-act-" + $Case.Name)
            if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
            New-Item -ItemType Directory -Path $tmp | Out-Null

            # Copy the project files the workflow needs into the temp repo.
            foreach ($item in @('src', 'config', 'fixtures', 'tests', '.github',
                                'Invoke-LicenseCheck.ps1', '.actrc')) {
                $src = Join-Path $script:ProjectRoot $item
                if (Test-Path $src) {
                    Copy-Item -Path $src -Destination $tmp -Recurse -Force
                }
            }

            Push-Location $tmp
            try {
                # act requires a git repo with at least one commit for a push event.
                git init -q 2>&1 | Out-Null
                git config user.email 'ci@example.com' 2>&1 | Out-Null
                git config user.name 'ci' 2>&1 | Out-Null
                git add -A 2>&1 | Out-Null
                git commit -q -m 'fixture' 2>&1 | Out-Null

                # --pull=false: use the locally-built act image instead of trying
                # to pull it from a registry (it only exists locally).
                $out = & act push `
                    -W '.github/workflows/dependency-license-checker.yml' `
                    --rm `
                    --pull=false `
                    -P "ubuntu-latest=$script:ActImage" `
                    --env "MANIFEST_PATH=$($Case.Manifest)" 2>&1
                $code = $LASTEXITCODE
            }
            finally { Pop-Location }

            return @{ ExitCode = $code; Output = ($out | Out-String) }
        }

        # Run all cases once, up front, accumulating output into act-result.txt.
        # (Running here keeps the slow act invocations out of the per-It timing and
        # lets every assertion read from the captured results.)
        Set-Content -LiteralPath $script:ActResult -Value "Dependency License Checker - act run log`n" -Encoding utf8

        $script:Runs = @{}
        foreach ($case in $script:Cases) {
            $result = Invoke-ActCase -Case $case
            $script:Runs[$case.Name] = $result

            $delim = "`n===== TEST CASE: $($case.Name) (manifest=$($case.Manifest)) =====`n"
            Add-Content -LiteralPath $script:ActResult -Value $delim -Encoding utf8
            Add-Content -LiteralPath $script:ActResult -Value $result.Output -Encoding utf8
            Add-Content -LiteralPath $script:ActResult -Value "----- exit code: $($result.ExitCode) -----`n" -Encoding utf8
        }
    }

    It 'created the act-result.txt artifact' {
        Test-Path $script:ActResult | Should -BeTrue
    }

    It 'exits 0 for case <Name>' -ForEach $Cases {
        $script:Runs[$Name].ExitCode | Should -Be 0
    }

    It 'shows both jobs succeeding for case <Name>' -ForEach $Cases {
        $output = $script:Runs[$Name].Output
        # act prints one "Job succeeded" per successful job; we have two jobs.
        ([regex]::Matches($output, 'Job succeeded')).Count | Should -BeGreaterOrEqual 2
    }

    It 'produces the exact expected report lines for case <Name>' -ForEach $Cases {
        $output = $script:Runs[$Name].Output
        foreach ($line in $Expected) {
            $output | Should -BeLike "*$line*"
        }
    }
}
