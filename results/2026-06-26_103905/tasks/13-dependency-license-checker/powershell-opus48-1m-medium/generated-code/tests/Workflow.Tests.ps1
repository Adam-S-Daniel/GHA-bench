<#
    Workflow structure tests + act integration tests.

    These tests validate the GitHub Actions workflow two ways:
      1. Static structure: parse the YAML, assert triggers/jobs/steps/paths,
         and assert that actionlint passes.
      2. Live execution: run the workflow under `act` for several fixture cases,
         capture output to act-result.txt, and assert on EXACT expected values
         plus job success.

    The act runs are executed once in BeforeAll (one `act push` per test case,
    3 total) and the results are asserted in individual It blocks.
#>

BeforeAll {
    $script:ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:WorkflowPath = Join-Path $script:ProjectRoot '.github' 'workflows' 'dependency-license-checker.yml'
    $script:ActResultPath = Join-Path $script:ProjectRoot 'act-result.txt'

    Import-Module powershell-yaml -ErrorAction Stop
    $script:Workflow = Get-Content -LiteralPath $script:WorkflowPath -Raw | ConvertFrom-Yaml
}

Describe 'Workflow structure (static analysis)' {

    It 'is valid YAML and parses into an object' {
        $script:Workflow | Should -Not -BeNullOrEmpty
    }

    It 'has a name' {
        $script:Workflow.name | Should -Be 'Dependency License Checker'
    }

    It 'declares the expected trigger events' {
        # powershell-yaml maps the `on:` key; access via index to avoid the
        # PowerShell `-on` operator ambiguity.
        $triggers = $script:Workflow['on']
        $triggers.Keys | Should -Contain 'push'
        $triggers.Keys | Should -Contain 'pull_request'
        $triggers.Keys | Should -Contain 'schedule'
        $triggers.Keys | Should -Contain 'workflow_dispatch'
    }

    It 'sets least-privilege contents:read permissions' {
        $script:Workflow.permissions.contents | Should -Be 'read'
    }

    It 'defines both the unit-tests and compliance jobs' {
        $script:Workflow.jobs.Keys | Should -Contain 'unit-tests'
        $script:Workflow.jobs.Keys | Should -Contain 'compliance'
    }

    It 'makes the compliance job depend on unit-tests' {
        $script:Workflow.jobs.compliance.needs | Should -Be 'unit-tests'
    }

    It 'uses actions/checkout@v4 in both jobs' {
        foreach ($jobName in 'unit-tests', 'compliance') {
            $steps = $script:Workflow.jobs[$jobName].steps
            ($steps | Where-Object { $_.uses -like 'actions/checkout@v4' }) | Should -Not -BeNullOrEmpty
        }
    }

    It 'runs PowerShell steps with shell: pwsh' {
        $runSteps = $script:Workflow.jobs.compliance.steps | Where-Object { $_.run }
        foreach ($step in $runSteps) {
            $step.shell | Should -Be 'pwsh'
        }
    }

    It 'references script files that actually exist on disk' {
        # The compliance step invokes ./src/Invoke-LicenseCheck.ps1.
        $runText = ($script:Workflow.jobs.compliance.steps | Where-Object { $_.run }).run -join "`n"
        $runText | Should -Match 'src/Invoke-LicenseCheck\.ps1'

        Test-Path (Join-Path $script:ProjectRoot 'src' 'Invoke-LicenseCheck.ps1') | Should -BeTrue
        Test-Path (Join-Path $script:ProjectRoot 'src' 'LicenseChecker.psm1')     | Should -BeTrue
        Test-Path (Join-Path $script:ProjectRoot 'config' 'license-config.json')  | Should -BeTrue
        Test-Path (Join-Path $script:ProjectRoot 'config' 'license-db.json')      | Should -BeTrue
    }

    It 'passes actionlint with exit code 0' {
        $output = & actionlint $script:WorkflowPath 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($output -join "`n")
    }
}

Describe 'Workflow execution via act' {

    BeforeAll {
        # ----- Test cases: each picks a fixture and lists the EXACT expected
        # summary values that the known-good run must produce. -----
        $script:Cases = @(
            @{
                Name           = 'package-json'
                Manifest       = 'fixtures/package.json'
                ExpectApproved = 3
                ExpectDenied   = 0
                ExpectUnknown  = 1
                MustContain    = @('lodash', '4.17.21', 'APPROVED', 'left-pad', 'UNKNOWN')
            },
            @{
                Name           = 'requirements-txt'
                Manifest       = 'fixtures/requirements.txt'
                ExpectApproved = 3
                ExpectDenied   = 0
                ExpectUnknown  = 0
                MustContain    = @('requests', '2.31.0', 'flask', 'pyyaml', 'APPROVED')
            },
            @{
                Name           = 'package-denied'
                Manifest       = 'fixtures/package-denied.json'
                ExpectApproved = 1
                ExpectDenied   = 1
                ExpectUnknown  = 0
                MustContain    = @('evil-pkg', 'GPL-3.0', 'DENIED')
            }
        )

        # Helper: build an isolated temp git repo with all project files plus the
        # case's `.ci-manifest` pointer, run `act push`, and capture everything.
        function Invoke-ActCase {
            param([hashtable] $Case, [string] $ProjectRoot)

            $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("act-lic-" + $Case.Name + "-" + [System.Guid]::NewGuid().ToString('N').Substring(0,8))
            New-Item -ItemType Directory -Path $tmp -Force | Out-Null

            # Copy the project files the workflow needs.
            foreach ($item in 'src', 'tests', 'fixtures', 'config', '.github', '.actrc') {
                Copy-Item -Path (Join-Path $ProjectRoot $item) -Destination $tmp -Recurse -Force
            }

            # Drop the per-case fixture pointer.
            Set-Content -Path (Join-Path $tmp '.ci-manifest') -Value $Case.Manifest -NoNewline

            # act needs a git repo.
            Push-Location $tmp
            try {
                git init -q 2>&1 | Out-Null
                git config user.email 'ci@example.com' 2>&1 | Out-Null
                git config user.name 'ci' 2>&1 | Out-Null
                git add -A 2>&1 | Out-Null
                git commit -q -m 'test case' 2>&1 | Out-Null

                # Run the workflow. --rm cleans up containers afterwards.
                # --pull=false: use the locally-built act image instead of pulling.
                $output = & act push --rm --pull=false -W '.github/workflows/dependency-license-checker.yml' 2>&1
                $exit = $LASTEXITCODE
            }
            finally {
                Pop-Location
            }

            Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue

            return [pscustomobject]@{
                Name     = $Case.Name
                Output   = ($output | Out-String)
                ExitCode = $exit
            }
        }

        # Run every case once, accumulating output into act-result.txt.
        Set-Content -Path $script:ActResultPath -Value "act integration run`n" -Encoding utf8
        $script:Results = @{}
        foreach ($case in $script:Cases) {
            $res = Invoke-ActCase -Case $case -ProjectRoot $script:ProjectRoot
            $script:Results[$case.Name] = $res

            $delimiter = ("=" * 70)
            Add-Content -Path $script:ActResultPath -Value $delimiter
            Add-Content -Path $script:ActResultPath -Value "TEST CASE: $($case.Name)  (manifest=$($case.Manifest))"
            Add-Content -Path $script:ActResultPath -Value "EXIT CODE: $($res.ExitCode)"
            Add-Content -Path $script:ActResultPath -Value $delimiter
            Add-Content -Path $script:ActResultPath -Value $res.Output
            Add-Content -Path $script:ActResultPath -Value "`n"
        }
    }

    It 'produced the act-result.txt artifact' {
        Test-Path $script:ActResultPath | Should -BeTrue
    }

    Context 'case <Name>' -ForEach @(
        @{ Name = 'package-json'    ; Approved = 3; Denied = 0; Unknown = 1; Contains = @('lodash', '4.17.21', 'APPROVED', 'left-pad', 'UNKNOWN') }
        @{ Name = 'requirements-txt'; Approved = 3; Denied = 0; Unknown = 0; Contains = @('requests', '2.31.0', 'flask', 'pyyaml', 'APPROVED') }
        @{ Name = 'package-denied'  ; Approved = 1; Denied = 1; Unknown = 0; Contains = @('evil-pkg', 'GPL-3.0', 'DENIED') }
    ) {
        It 'exited act with code 0' {
            $script:Results[$Name].ExitCode | Should -Be 0 -Because $script:Results[$Name].Output
        }

        It 'reports every job succeeded' {
            $script:Results[$Name].Output | Should -Match 'Job succeeded'
        }

        It 'shows exactly <Approved> approved, <Denied> denied, <Unknown> unknown' {
            $out = $script:Results[$Name].Output
            $out | Should -Match ("Approved:\s*" + $Approved + "\b")
            $out | Should -Match ("Denied:\s*"   + $Denied   + "\b")
            $out | Should -Match ("Unknown:\s*"  + $Unknown  + "\b")
        }

        It 'contains the expected dependency/license details' {
            $out = $script:Results[$Name].Output
            foreach ($needle in $Contains) {
                $out | Should -BeLike "*$needle*"
            }
        }
    }
}
