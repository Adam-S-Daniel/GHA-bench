# Workflow.Tests.ps1
#
# Two kinds of tests live here:
#   1. Static structure tests over the workflow YAML (parsed with powershell-yaml)
#      and an actionlint pass.
#   2. An act-driven integration harness: for each fixture case, build a clean temp
#      git repo, run the real workflow via `act push`, and assert on the EXACT
#      report values the pipeline produces.
#
# This file is intentionally NOT run by the workflow's `validate` job (that would
# run act inside act). It is the local/CI harness that exercises the pipeline.
#
# NOTE: each act case runs the full two-job workflow in Docker (~30-60s). The act
# invocations happen once in BeforeAll; the It blocks assert on the captured output.

BeforeDiscovery {
    # Presence of act + docker (and no SKIP_ACT opt-out) decides whether the
    # integration harness can run. SKIP_ACT lets the fast static tests run alone.
    $script:HasAct = [bool](Get-Command act -ErrorAction SilentlyContinue) -and
                     [bool](Get-Command docker -ErrorAction SilentlyContinue) -and
                     -not $env:SKIP_ACT
}

BeforeAll {
    Import-Module powershell-yaml -ErrorAction Stop

    $script:Root = Split-Path -Parent $PSScriptRoot
    $script:WorkflowPath = Join-Path $script:Root '.github/workflows/dependency-license-checker.yml'
    $script:Workflow = ConvertFrom-Yaml (Get-Content -LiteralPath $script:WorkflowPath -Raw)

    # ---- Helper: run one fixture case end-to-end through `act push`. ----
    function Invoke-LicenseCheckActCase {
        param(
            [Parameter(Mandatory)][string]$CaseId,
            [Parameter(Mandatory)][string]$ProjectRoot,
            # Mutates the copied ci-input directory to install the case's manifest.
            [Parameter(Mandatory)][scriptblock]$SetupCiInput
        )

        $work = Join-Path ([System.IO.Path]::GetTempPath()) ("license-act-$CaseId-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $work | Out-Null

        try {
            # Copy only the project files act needs. Crucially EXCLUDE the existing
            # .git so we don't commit a stray gitlink / embedded repo.
            foreach ($file in 'DependencyLicenseChecker.psm1', 'Invoke-DependencyLicenseCheck.ps1', '.actrc') {
                Copy-Item -LiteralPath (Join-Path $ProjectRoot $file) -Destination (Join-Path $work $file)
            }
            Copy-Item -LiteralPath (Join-Path $ProjectRoot '.github') -Destination (Join-Path $work '.github') -Recurse
            Copy-Item -LiteralPath (Join-Path $ProjectRoot 'tests')   -Destination (Join-Path $work 'tests')   -Recurse
            Copy-Item -LiteralPath (Join-Path $ProjectRoot 'ci-input') -Destination (Join-Path $work 'ci-input') -Recurse

            # Apply the case-specific manifest into the copied ci-input.
            & $SetupCiInput $work

            Push-Location $work
            try {
                # Fresh repo; set identity inline so a clean HOME can't break commit.
                git init -q -b main 2>&1 | Out-Null
                git -c user.email='ci@example.com' -c user.name='ci' add -A 2>&1 | Out-Null
                git -c user.email='ci@example.com' -c user.name='ci' commit -q -m "case $CaseId" 2>&1 | Out-Null
                $trackedCount = @(git ls-files).Count

                # --rm cleans up on failure; --pull=false uses the local custom image
                # (act-ubuntu-pwsh:latest from .actrc) instead of trying a registry pull.
                $raw = & act push --rm --pull=false 2>&1 | Out-String
                $exit = $LASTEXITCODE
            }
            finally {
                Pop-Location
            }

            return [pscustomobject]@{
                CaseId   = $CaseId
                ExitCode = $exit
                Raw      = $raw
                # Strip ANSI colour codes so exact-string assertions are reliable.
                Clean    = ($raw -replace '\x1b\[[0-9;]*m', '')
                Tracked  = $trackedCount
            }
        }
        finally {
            Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # ---- Run all act cases once, persisting output to act-result.txt. ----
    $script:RunAct = [bool](Get-Command act -ErrorAction SilentlyContinue) -and
                     [bool](Get-Command docker -ErrorAction SilentlyContinue) -and
                     -not $env:SKIP_ACT
    if ($script:RunAct) {
        $script:ActResultPath = Join-Path $script:Root 'act-result.txt'
        # Fresh artifact for this run.
        Set-Content -LiteralPath $script:ActResultPath -Value "Dependency License Checker - act integration results`n" -Encoding utf8

        $cases = @(
            @{
                Id    = 'A'
                Desc  = 'package.json, all licenses approved -> COMPLIANT'
                Setup = {
                    param($work)
                    # Default committed ci-input already holds the all-approved package.json.
                    Remove-Item -LiteralPath (Join-Path $work 'ci-input/requirements.txt') -ErrorAction SilentlyContinue
                }
            }
            @{
                Id    = 'B'
                Desc  = 'package.json with a denied (GPL) + an unknown dep -> NON-COMPLIANT'
                Setup = {
                    param($work)
                    Remove-Item -LiteralPath (Join-Path $work 'ci-input/requirements.txt') -ErrorAction SilentlyContinue
                    Copy-Item -LiteralPath (Join-Path $script:Root 'tests/fixtures/caseB-package.json') `
                              -Destination (Join-Path $work 'ci-input/package.json') -Force
                }
            }
            @{
                Id    = 'C'
                Desc  = 'requirements.txt (pip) with an unknown dep -> NON-COMPLIANT'
                Setup = {
                    param($work)
                    # Remove the npm manifest so auto-detect picks requirements.txt.
                    Remove-Item -LiteralPath (Join-Path $work 'ci-input/package.json') -ErrorAction SilentlyContinue
                    Copy-Item -LiteralPath (Join-Path $script:Root 'tests/fixtures/caseC-requirements.txt') `
                              -Destination (Join-Path $work 'ci-input/requirements.txt') -Force
                }
            }
        )

        $script:ActResults = @{}
        foreach ($case in $cases) {
            $r = Invoke-LicenseCheckActCase -CaseId $case.Id -ProjectRoot $script:Root -SetupCiInput $case.Setup
            $script:ActResults[$case.Id] = $r

            $header = "`n========================================`n" +
                      "ACT CASE $($case.Id): $($case.Desc)`n" +
                      "exit code: $($r.ExitCode) | tracked files: $($r.Tracked)`n" +
                      "========================================`n"
            Add-Content -LiteralPath $script:ActResultPath -Value $header -Encoding utf8
            Add-Content -LiteralPath $script:ActResultPath -Value $r.Raw -Encoding utf8
        }
    }
}

Describe 'Workflow file structure' {

    It 'the workflow file exists' {
        Test-Path -LiteralPath $script:WorkflowPath | Should -BeTrue
    }

    It 'has the expected workflow name' {
        $script:Workflow.name | Should -Be 'Dependency License Checker'
    }

    Context 'triggers' {
        It 'triggers on push' { $script:Workflow['on'].Keys | Should -Contain 'push' }
        It 'triggers on pull_request' { $script:Workflow['on'].Keys | Should -Contain 'pull_request' }
        It 'triggers on workflow_dispatch' { $script:Workflow['on'].Keys | Should -Contain 'workflow_dispatch' }
        It 'triggers on a schedule' { $script:Workflow['on'].Keys | Should -Contain 'schedule' }
        It 'uses a valid weekly cron expression' {
            $script:Workflow['on'].schedule[0].cron | Should -Be '0 6 * * 1'
        }
    }

    Context 'permissions and environment' {
        It 'declares least-privilege contents:read permission' {
            $script:Workflow.permissions.contents | Should -Be 'read'
        }
        It 'defines the INPUT_DIR environment variable' {
            $script:Workflow.env.INPUT_DIR | Should -Be 'ci-input'
        }
    }

    Context 'jobs' {
        It 'defines the validate and license-check jobs' {
            $script:Workflow.jobs.Keys | Should -Contain 'validate'
            $script:Workflow.jobs.Keys | Should -Contain 'license-check'
        }
        It 'makes license-check depend on validate (job dependency)' {
            $script:Workflow.jobs['license-check'].needs | Should -Be 'validate'
        }
        It 'runs both jobs on ubuntu-latest' {
            $script:Workflow.jobs.validate['runs-on'] | Should -Be 'ubuntu-latest'
            $script:Workflow.jobs['license-check']['runs-on'] | Should -Be 'ubuntu-latest'
        }
        It 'checks out the repo with actions/checkout@v4 in every job' {
            foreach ($jobName in 'validate', 'license-check') {
                $uses = $script:Workflow.jobs[$jobName].steps | ForEach-Object { $_.uses } | Where-Object { $_ }
                $uses | Should -Contain 'actions/checkout@v4'
            }
        }
        It 'uses shell: pwsh on every run step' {
            foreach ($jobName in 'validate', 'license-check') {
                foreach ($step in $script:Workflow.jobs[$jobName].steps) {
                    if ($null -ne $step.run) {
                        $step.shell | Should -Be 'pwsh' -Because "step '$($step.name)' runs PowerShell"
                    }
                }
            }
        }
    }

    Context 'script references' {
        It 'references the CLI entry script, which exists on disk' {
            $allRun = ($script:Workflow.jobs['license-check'].steps | ForEach-Object { $_.run }) -join "`n"
            $allRun | Should -Match 'Invoke-DependencyLicenseCheck\.ps1'
            Test-Path -LiteralPath (Join-Path $script:Root 'Invoke-DependencyLicenseCheck.ps1') | Should -BeTrue
        }
        It 'references the unit-test file, which exists on disk' {
            $allRun = ($script:Workflow.jobs.validate.steps | ForEach-Object { $_.run }) -join "`n"
            $allRun | Should -Match 'tests/DependencyLicenseChecker\.Tests\.ps1'
            Test-Path -LiteralPath (Join-Path $script:Root 'tests/DependencyLicenseChecker.Tests.ps1') | Should -BeTrue
        }
        It 'references the module file, which exists on disk' {
            Test-Path -LiteralPath (Join-Path $script:Root 'DependencyLicenseChecker.psm1') | Should -BeTrue
        }
    }
}

Describe 'actionlint validation' {
    It 'passes actionlint with exit code 0' {
        $actionlint = Get-Command actionlint -ErrorAction SilentlyContinue
        if (-not $actionlint) { Set-ItResult -Skipped -Because 'actionlint not installed'; return }
        $output = & actionlint $script:WorkflowPath 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($output | Out-String)
    }
}

Describe 'act pipeline integration' -Skip:(-not $script:HasAct) {

    It 'produced the act-result.txt artifact' {
        Test-Path -LiteralPath $script:ActResultPath | Should -BeTrue
        (Get-Content -LiteralPath $script:ActResultPath -Raw).Length | Should -BeGreaterThan 0
    }

    Context 'Case A: package.json, all approved (COMPLIANT)' {
        It 'act exited 0' {
            $script:ActResults['A'].ExitCode | Should -Be 0 -Because $script:ActResults['A'].Clean
        }
        It 'both jobs reported "Job succeeded"' {
            ([regex]::Matches($script:ActResults['A'].Clean, 'Job succeeded')).Count | Should -Be 2
        }
        It 'reports each dependency with its exact license + status' {
            $c = $script:ActResults['A'].Clean
            $c | Should -Match ([regex]::Escape('DEP name=express version=4.18.2 license=MIT status=approved'))
            $c | Should -Match ([regex]::Escape('DEP name=lodash version=4.17.21 license=MIT status=approved'))
            $c | Should -Match ([regex]::Escape('DEP name=jest version=29.7.0 license=MIT status=approved'))
        }
        It 'reports the exact RESULT counts' {
            $script:ActResults['A'].Clean | Should -Match ([regex]::Escape('RESULT approved=3 denied=0 unknown=0 total=3'))
        }
        It 'reports the COMPLIANT verdict' {
            $script:ActResults['A'].Clean | Should -Match ([regex]::Escape('COMPLIANCE: COMPLIANT'))
        }
    }

    Context 'Case B: package.json with denied + unknown (NON-COMPLIANT)' {
        It 'act exited 0 (report mode keeps CI green)' {
            $script:ActResults['B'].ExitCode | Should -Be 0 -Because $script:ActResults['B'].Clean
        }
        It 'both jobs reported "Job succeeded"' {
            ([regex]::Matches($script:ActResults['B'].Clean, 'Job succeeded')).Count | Should -Be 2
        }
        It 'flags the GPL dependency as denied' {
            $script:ActResults['B'].Clean | Should -Match ([regex]::Escape('DEP name=evil-gpl version=1.0.0 license=GPL-3.0 status=denied'))
        }
        It 'flags the unmapped dependency as unknown' {
            $script:ActResults['B'].Clean | Should -Match ([regex]::Escape('DEP name=mystery-pkg version=2.0.0 license=UNKNOWN status=unknown'))
        }
        It 'still approves the MIT dependency' {
            $script:ActResults['B'].Clean | Should -Match ([regex]::Escape('DEP name=express version=4.18.2 license=MIT status=approved'))
        }
        It 'reports the exact RESULT counts' {
            $script:ActResults['B'].Clean | Should -Match ([regex]::Escape('RESULT approved=1 denied=1 unknown=1 total=3'))
        }
        It 'reports the NON-COMPLIANT verdict' {
            $script:ActResults['B'].Clean | Should -Match ([regex]::Escape('COMPLIANCE: NON-COMPLIANT'))
        }
    }

    Context 'Case C: requirements.txt / pip (NON-COMPLIANT)' {
        It 'act exited 0' {
            $script:ActResults['C'].ExitCode | Should -Be 0 -Because $script:ActResults['C'].Clean
        }
        It 'both jobs reported "Job succeeded"' {
            ([regex]::Matches($script:ActResults['C'].Clean, 'Job succeeded')).Count | Should -Be 2
        }
        It 'parses pip specifiers and approves known licenses' {
            $c = $script:ActResults['C'].Clean
            $c | Should -Match ([regex]::Escape('DEP name=requests version=2.31.0 license=Apache-2.0 status=approved'))
            $c | Should -Match ([regex]::Escape('DEP name=flask version=2.0.0 license=BSD-3-Clause status=approved'))
        }
        It 'flags the unmapped pip dependency as unknown' {
            $script:ActResults['C'].Clean | Should -Match ([regex]::Escape('DEP name=unknown-dep version=9.9.9 license=UNKNOWN status=unknown'))
        }
        It 'reports the exact RESULT counts' {
            $script:ActResults['C'].Clean | Should -Match ([regex]::Escape('RESULT approved=2 denied=0 unknown=1 total=3'))
        }
        It 'reports the NON-COMPLIANT verdict' {
            $script:ActResults['C'].Clean | Should -Match ([regex]::Escape('COMPLIANCE: NON-COMPLIANT'))
        }
    }
}
