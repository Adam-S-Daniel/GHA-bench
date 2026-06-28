<#
.SYNOPSIS
    Workflow structure tests + end-to-end execution tests via `act`.

.DESCRIPTION
    This suite validates the GitHub Actions workflow two ways:

      1. STRUCTURE  — parses the YAML (powershell-yaml), asserts the expected
         triggers / permissions / jobs / steps, confirms the workflow references
         script files that actually exist, and asserts `actionlint` passes.

      2. EXECUTION  — for each test case it builds a throwaway git repo seeded
         with the project files + that case's fixture data, runs `act push --rm`
         in a Docker container, appends the full output to act-result.txt, and
         asserts the act exit code, that every job reports "Job succeeded", and
         the EXACT expected report values for that fixture.

    Run with:  Invoke-Pester -Path ./Workflow.Tests.ps1
    (Requires Docker + act; the act runner image is act-ubuntu-pwsh:latest.)
#>

BeforeDiscovery {
    # ---- Test cases are needed at DISCOVERY time so -ForEach can expand them. --
    # Each case fully describes the fixture files written into the temp repo and
    # the exact values we expect to see in the act output.
    $script:ActCases = @(
        @{
            CaseName        = 'package.json-mixed-report-only'
            # A mixed manifest: 2 approved (MIT), 1 unknown (WTFPL: resolved but
            # unclassified), 1 denied (GPL-3.0 via devDependencies). Report-only
            # (failOnViolation=false) so the job still succeeds despite a denial.
            Files           = @{
                'compliance.config.json' = @'
{
  "manifest": "examples/package.json",
  "licenseDb": "examples/licenses.json",
  "allow": ["MIT", "Apache-2.0", "BSD-3-Clause", "ISC"],
  "deny": ["GPL-3.0", "AGPL-3.0", "GPL-2.0"],
  "failOnViolation": false
}
'@
                'examples/package.json' = @'
{
  "name": "sample-service",
  "version": "1.0.0",
  "dependencies": {
    "express": "^4.18.2",
    "lodash": "4.17.21",
    "left-pad": "1.3.0"
  },
  "devDependencies": {
    "gpl-tool": "2.0.0"
  }
}
'@
                'examples/licenses.json' = @'
{
  "express": "MIT",
  "lodash": "MIT",
  "left-pad": "WTFPL",
  "gpl-tool": "GPL-3.0"
}
'@
            }
            ExpectedSummary = 'Summary: total=4 approved=2 denied=1 unknown=1'
            ExpectedResult  = 'Result: NON-COMPLIANT'
            ExpectedLines   = @(
                '[APPROVED] express@4.18.2 -> MIT'
                '[APPROVED] lodash@4.17.21 -> MIT'
                '[UNKNOWN] left-pad@1.3.0 -> WTFPL'
                '[DENIED] gpl-tool@2.0.0 -> GPL-3.0'
            )
        }
        @{
            CaseName        = 'requirements.txt-all-approved-gate-on'
            # A pip manifest where every dependency is allow-listed. The gate is
            # ON (failOnViolation=true) but denied=0, so the checker exits 0 and
            # the job succeeds — exercising both the requirements parser and the
            # COMPLIANT/gate-pass path.
            Files           = @{
                'compliance.config.json' = @'
{
  "manifest": "examples/requirements.txt",
  "licenseDb": "examples/licenses.json",
  "allow": ["MIT", "Apache-2.0", "BSD-3-Clause", "ISC"],
  "deny": ["GPL-3.0", "AGPL-3.0"],
  "failOnViolation": true
}
'@
                'examples/requirements.txt' = @'
# pip requirements
requests==2.28.1
flask>=2.0
click==8.1.3  # CLI helper
'@
                'examples/licenses.json' = @'
{
  "requests": "Apache-2.0",
  "flask": "BSD-3-Clause",
  "click": "BSD-3-Clause"
}
'@
            }
            ExpectedSummary = 'Summary: total=3 approved=3 denied=0 unknown=0'
            ExpectedResult  = 'Result: COMPLIANT'
            ExpectedLines   = @(
                '[APPROVED] requests@2.28.1 -> Apache-2.0'
                '[APPROVED] flask@2.0 -> BSD-3-Clause'
                '[APPROVED] click@8.1.3 -> BSD-3-Clause'
            )
        }
    )
}

BeforeAll {
    $script:RepoRoot     = $PSScriptRoot
    $script:WorkflowPath = Join-Path $RepoRoot '.github/workflows/dependency-license-checker.yml'
    $script:ActResult    = Join-Path $RepoRoot 'act-result.txt'

    Import-Module powershell-yaml -ErrorAction Stop

    # Resolve external tools (fall back to the well-known install location).
    $script:ActExe        = (Get-Command act        -ErrorAction SilentlyContinue).Source
    $script:ActionlintExe = (Get-Command actionlint -ErrorAction SilentlyContinue).Source
    $script:GitExe        = (Get-Command git        -ErrorAction SilentlyContinue).Source
    if (-not $script:ActExe)        { $script:ActExe        = Join-Path $HOME '.local/bin/act' }
    if (-not $script:ActionlintExe) { $script:ActionlintExe = Join-Path $HOME '.local/bin/actionlint' }
    if (-not $script:GitExe)        { $script:GitExe        = 'git' }

    # Parse the workflow once. powershell-yaml 0.4+ parses the `on:` key as the
    # string "on" (not the YAML 1.1 boolean true); handle both defensively.
    $script:Workflow = Get-Content -LiteralPath $WorkflowPath -Raw | ConvertFrom-Yaml
    $script:Triggers = if ($Workflow.ContainsKey('on')) { $Workflow['on'] } else { $Workflow[$true] }

    # Start a fresh act-result.txt for this run.
    Set-Content -LiteralPath $ActResult -Value "ACT RESULTS for dependency-license-checker workflow" -Encoding utf8

    # ---- Helper: build a temp repo for a case, run act, record the output. ----
    function script:Invoke-ActCase {
        param(
            [Parameter(Mandatory)][string]$CaseName,
            [Parameter(Mandatory)][hashtable]$Files
        )

        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "dlc-act-$([System.Guid]::NewGuid().ToString('N'))"
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null

        # Files the workflow needs from the project.
        Copy-Item (Join-Path $RepoRoot 'DependencyLicenseChecker.ps1')       $tmp
        Copy-Item (Join-Path $RepoRoot 'DependencyLicenseChecker.Tests.ps1') $tmp
        New-Item -ItemType Directory -Path (Join-Path $tmp '.github/workflows') -Force | Out-Null
        Copy-Item $WorkflowPath (Join-Path $tmp '.github/workflows/')
        if (Test-Path (Join-Path $RepoRoot '.actrc')) { Copy-Item (Join-Path $RepoRoot '.actrc') $tmp }

        # Per-case fixture files (may include nested paths like examples/...).
        foreach ($rel in $Files.Keys) {
            $dest    = Join-Path $tmp $rel
            $destDir = Split-Path $dest -Parent
            if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
            Set-Content -LiteralPath $dest -Value $Files[$rel] -Encoding utf8
        }

        $out  = ''
        $code = -1
        Push-Location $tmp
        try {
            # A committed git repo on branch 'main' so the push event matches the
            # workflow's branch filter.
            & $GitExe -c init.defaultBranch=main init -q
            & $GitExe config user.email 'ci-test@example.com'
            & $GitExe config user.name  'CI Test'
            & $GitExe add -A
            & $GitExe -c commit.gpgsign=false commit -q -m "fixture: $CaseName"

            # Run the workflow in Docker. -P maps the runner image; offline action
            # mode + no image pull keep it hermetic (checkout@v4 is pre-cached).
            $out = & $ActExe push --rm `
                -P 'ubuntu-latest=act-ubuntu-pwsh:latest' `
                --pull=false --action-offline-mode 2>&1 | Out-String
            $code = $LASTEXITCODE
        } finally {
            Pop-Location
        }

        # Append this case's output to the required artifact.
        $header = @"

================================================================================
ACT CASE: $CaseName  (act exit code: $code)
================================================================================
"@
        Add-Content -LiteralPath $ActResult -Value $header
        Add-Content -LiteralPath $ActResult -Value $out

        # Best-effort cleanup (act copies the workspace, so the host dir is free).
        Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue

        return @{ Output = $out; ExitCode = $code }
    }
}

Describe 'Workflow file structure' {

    It 'exists at the expected path' {
        Test-Path -LiteralPath $WorkflowPath | Should -BeTrue
    }

    It 'is valid YAML with a workflow name' {
        $Workflow | Should -Not -BeNullOrEmpty
        $Workflow['name'] | Should -Be 'Dependency License Checker'
    }

    It 'declares the expected trigger events' {
        $Triggers.Keys | Should -Contain 'push'
        $Triggers.Keys | Should -Contain 'pull_request'
        $Triggers.Keys | Should -Contain 'workflow_dispatch'
        $Triggers.Keys | Should -Contain 'schedule'
    }

    It 'sets least-privilege permissions (contents: read)' {
        $Workflow['permissions']['contents'] | Should -Be 'read'
    }

    It 'defines the CONFIG_PATH environment variable' {
        $Workflow['env']['CONFIG_PATH'] | Should -Be 'compliance.config.json'
    }

    It 'defines both the test and compliance jobs' {
        $Workflow['jobs'].Keys | Should -Contain 'test'
        $Workflow['jobs'].Keys | Should -Contain 'compliance'
    }

    It 'makes the compliance job depend on the test job' {
        $Workflow['jobs']['compliance']['needs'] | Should -Be 'test'
    }

    It 'runs jobs on ubuntu-latest' {
        $Workflow['jobs']['test']['runs-on']       | Should -Be 'ubuntu-latest'
        $Workflow['jobs']['compliance']['runs-on'] | Should -Be 'ubuntu-latest'
    }

    It 'uses actions/checkout@v4 in both jobs' {
        foreach ($job in 'test', 'compliance') {
            $uses = $Workflow['jobs'][$job]['steps'] | ForEach-Object { $_['uses'] }
            $uses | Should -Contain 'actions/checkout@v4'
        }
    }

    It 'uses shell: pwsh for every run step (PowerShell mode requirement)' {
        foreach ($job in $Workflow['jobs'].Keys) {
            foreach ($step in $Workflow['jobs'][$job]['steps']) {
                if ($step.ContainsKey('run')) {
                    $step['shell'] | Should -Be 'pwsh' -Because "step '$($step['name'])' runs PowerShell"
                }
            }
        }
    }

    It 'references the checker script, which exists on disk' {
        $raw = Get-Content -LiteralPath $WorkflowPath -Raw
        $raw | Should -Match 'DependencyLicenseChecker\.ps1'
        Test-Path -LiteralPath (Join-Path $RepoRoot 'DependencyLicenseChecker.ps1') | Should -BeTrue
    }

    It 'references the unit-test file, which exists on disk' {
        $raw = Get-Content -LiteralPath $WorkflowPath -Raw
        $raw | Should -Match 'DependencyLicenseChecker\.Tests\.ps1'
        Test-Path -LiteralPath (Join-Path $RepoRoot 'DependencyLicenseChecker.Tests.ps1') | Should -BeTrue
    }

    It 'references a config file that exists on disk' {
        Test-Path -LiteralPath (Join-Path $RepoRoot 'compliance.config.json') | Should -BeTrue
    }

    It 'passes actionlint with exit code 0' {
        $alOut = & $ActionlintExe $WorkflowPath 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 0 -Because "actionlint output:`n$alOut"
    }
}

Describe 'Workflow execution via act' {

    # -ForEach a hashtable exposes each key as a variable ($CaseName, $Files,
    # $ExpectedSummary, $ExpectedResult, $ExpectedLines) inside the blocks below.
    Context 'case <CaseName>' -ForEach $ActCases {

        BeforeAll {
            # Run act once per case; assertions below read the captured result.
            $script:Result = Invoke-ActCase -CaseName $CaseName -Files $Files
        }

        It 'act exits with code 0' {
            $Result.ExitCode | Should -Be 0 -Because "act output:`n$($Result.Output)"
        }

        It 'reports "Job succeeded" for both jobs' {
            $Result.Output | Should -Match 'Job succeeded'
            $Result.Output | Should -Not -Match 'Job failed'
            ([regex]::Matches($Result.Output, 'Job succeeded')).Count |
                Should -BeGreaterOrEqual 2 -Because 'the test job and the compliance job must both succeed'
        }

        It 'runs the Pester unit tests in the pipeline with zero failures' {
            $Result.Output | Should -Match 'Tests Passed: 26'
            $Result.Output | Should -Match 'Failed: 0'
        }

        It 'prints the EXACT expected summary line' {
            $Result.Output | Should -Match ([regex]::Escape($ExpectedSummary))
        }

        It 'prints the EXACT expected compliance result' {
            $Result.Output | Should -Match ([regex]::Escape($ExpectedResult))
        }

        It 'prints every EXACT expected per-dependency status line' {
            foreach ($line in $ExpectedLines) {
                $Result.Output | Should -Match ([regex]::Escape($line)) `
                    -Because "expected dependency line '$line' in act output"
            }
        }
    }
}

AfterAll {
    Write-Host "act-result.txt written to: $script:ActResult"
}
