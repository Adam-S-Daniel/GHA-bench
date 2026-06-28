# Workflow.Tests.ps1
#
# Integration + structure test suite for the GitHub Actions workflow.
#
# IMPORTANT: this file lives in integration/ (NOT tests/) on purpose. The
# workflow's own Pester step runs only the tests/ directory, so this file is
# never executed inside the act container -- that would recurse (act inside
# act) and require Docker that the container does not have.
#
# Run locally with:   Invoke-Pester -Path integration/Workflow.Tests.ps1
#
# What it covers:
#   1. Workflow STRUCTURE: parses the YAML and asserts the expected triggers,
#      jobs, job dependencies, permissions, and that referenced script files
#      exist on disk.
#   2. actionlint: asserts the workflow passes actionlint with exit code 0.
#   3. EXECUTION via act: for each test case, builds a throwaway git repo with
#      the project files + that case's fixture, runs `act push --rm`, captures
#      output to act-result.txt, and asserts on EXACT expected report values.

BeforeAll {
    $script:RepoRoot     = Split-Path -Parent $PSScriptRoot
    $script:WorkflowPath = Join-Path $RepoRoot '.github/workflows/dependency-license-checker.yml'
    $script:ActResult    = Join-Path $RepoRoot 'act-result.txt'

    Import-Module powershell-yaml -ErrorAction Stop
    $script:Workflow = Get-Content -LiteralPath $WorkflowPath -Raw | ConvertFrom-Yaml

    # Start each full run with a fresh act-result.txt artifact.
    Set-Content -LiteralPath $ActResult -Value "act-result.txt - dependency-license-checker workflow runs`n" -Encoding utf8

    # ---------------------------------------------------------------------
    # Helper: build an isolated git repo for a test case and run it via act.
    # Returns @{ Output = <string>; ExitCode = <int> }.
    # ---------------------------------------------------------------------
    function Invoke-ActCase {
        param(
            [Parameter(Mandatory)][string]$CaseName,
            [Parameter(Mandatory)][string]$ManifestFileName,  # e.g. package.json / requirements.txt
            [Parameter(Mandatory)][string]$ManifestContent,
            [string]$ManifestEnvOverride                       # value for MANIFEST_PATH, or empty
        )

        $work = Join-Path ([System.IO.Path]::GetTempPath()) ("lc-act-" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $work -Force | Out-Null

        try {
            # Copy the project files the workflow needs into the temp repo.
            foreach ($item in 'src', 'tests', 'config', 'Invoke-LicenseChecker.ps1', '.actrc') {
                Copy-Item -Path (Join-Path $RepoRoot $item) -Destination $work -Recurse -Force
            }
            # Copy the workflow into place.
            New-Item -ItemType Directory -Path (Join-Path $work '.github/workflows') -Force | Out-Null
            Copy-Item -Path $WorkflowPath -Destination (Join-Path $work '.github/workflows') -Force

            # Write this case's fixture manifest.
            New-Item -ItemType Directory -Path (Join-Path $work 'fixtures') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $work "fixtures/$ManifestFileName") -Value $ManifestContent -Encoding utf8

            # Initialise a git repo (act needs a committed repo to simulate push).
            Push-Location $work
            try {
                git init -q
                git config user.email 'ci@example.com'
                git config user.name  'CI'
                git add -A
                git commit -qm "test case: $CaseName"

                $actArgs = @('push', '--rm', '-W', '.github/workflows/dependency-license-checker.yml')
                if ($ManifestEnvOverride) {
                    $actArgs += @('--env', "MANIFEST_PATH=$ManifestEnvOverride")
                }

                $output   = & act @actArgs 2>&1 | Out-String
                $exitCode = $LASTEXITCODE
            }
            finally {
                Pop-Location
            }

            # Append to the act-result.txt artifact with a clear delimiter.
            $delim = "`n" + ('=' * 78) + "`n"
            Add-Content -LiteralPath $ActResult -Value $delim -Encoding utf8
            Add-Content -LiteralPath $ActResult -Value "TEST CASE: $CaseName (exit=$exitCode)" -Encoding utf8
            Add-Content -LiteralPath $ActResult -Value $delim -Encoding utf8
            Add-Content -LiteralPath $ActResult -Value $output -Encoding utf8

            return @{ Output = $output; ExitCode = $exitCode }
        }
        finally {
            Remove-Item -Path $work -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Workflow structure' {

    It 'is valid YAML that parses to a mapping' {
        $Workflow | Should -Not -BeNullOrEmpty
        $Workflow.Keys | Should -Contain 'jobs'
    }

    It 'declares the expected trigger events' {
        # PowerShell-yaml maps the bare YAML key `on:` to the boolean key $true.
        $on = $Workflow[$true]
        if ($null -eq $on) { $on = $Workflow['on'] }
        $on.Keys | Should -Contain 'push'
        $on.Keys | Should -Contain 'pull_request'
        $on.Keys | Should -Contain 'schedule'
        $on.Keys | Should -Contain 'workflow_dispatch'
    }

    It 'sets least-privilege read permissions' {
        $Workflow['permissions']['contents'] | Should -Be 'read'
    }

    It 'defines the unit-tests and compliance-report jobs' {
        $Workflow['jobs'].Keys | Should -Contain 'unit-tests'
        $Workflow['jobs'].Keys | Should -Contain 'compliance-report'
    }

    It 'makes the compliance job depend on the unit-tests job' {
        $Workflow['jobs']['compliance-report']['needs'] | Should -Be 'unit-tests'
    }

    It 'uses actions/checkout@v4 in both jobs' {
        foreach ($job in 'unit-tests', 'compliance-report') {
            $uses = $Workflow['jobs'][$job]['steps'] | ForEach-Object { $_['uses'] }
            ($uses -join ' ') | Should -Match 'actions/checkout@v4'
        }
    }

    It 'runs every run-step with shell: pwsh' {
        foreach ($job in $Workflow['jobs'].Keys) {
            foreach ($step in $Workflow['jobs'][$job]['steps']) {
                if ($step.ContainsKey('run')) {
                    $step['shell'] | Should -Be 'pwsh'
                }
            }
        }
    }

    It 'references script files that exist on disk' {
        Test-Path (Join-Path $RepoRoot 'Invoke-LicenseChecker.ps1') | Should -BeTrue
        Test-Path (Join-Path $RepoRoot 'src/LicenseChecker.psm1')    | Should -BeTrue
        Test-Path (Join-Path $RepoRoot 'config/license-config.json') | Should -BeTrue
        Test-Path (Join-Path $RepoRoot 'config/license-db.json')     | Should -BeTrue
        Test-Path (Join-Path $RepoRoot 'tests/LicenseChecker.Tests.ps1') | Should -BeTrue
    }
}

Describe 'actionlint validation' {
    It 'passes actionlint with exit code 0' {
        $out = & actionlint $WorkflowPath 2>&1
        $LASTEXITCODE | Should -Be 0 -Because "actionlint output: $out"
    }
}

Describe 'Workflow execution via act' {

    Context 'Case 1: all dependencies approved (package.json)' {
        BeforeAll {
            $manifest = @'
{
  "name": "all-approved",
  "version": "1.0.0",
  "dependencies": {
    "express": "^4.18.2",
    "lodash": "4.17.21"
  }
}
'@
            $script:R1 = Invoke-ActCase -CaseName 'all-approved' `
                -ManifestFileName 'package.json' -ManifestContent $manifest
        }

        It 'exits 0' { $R1.ExitCode | Should -Be 0 }
        It 'reports express as APPROVED (MIT)'  { $R1.Output | Should -Match 'express@4\.18\.2 \[MIT\] -> APPROVED' }
        It 'reports lodash as APPROVED (MIT)'   { $R1.Output | Should -Match 'lodash@4\.17\.21 \[MIT\] -> APPROVED' }
        It 'shows the exact summary counts'     { $R1.Output | Should -Match 'Total: 2 \| Approved: 2 \| Denied: 0 \| Unknown: 0' }
        It 'shows an overall PASS verdict'      { $R1.Output | Should -Match 'Compliance: PASS' }
        It 'shows both jobs succeeding' {
            ([regex]::Matches($R1.Output, 'Job succeeded')).Count | Should -BeGreaterOrEqual 2
        }
    }

    Context 'Case 2: a denied license present (package.json)' {
        BeforeAll {
            $manifest = @'
{
  "name": "has-denied",
  "version": "1.0.0",
  "dependencies": {
    "express": "4.18.2",
    "copyleft-lib": "1.0.0"
  }
}
'@
            $script:R2 = Invoke-ActCase -CaseName 'has-denied' `
                -ManifestFileName 'package.json' -ManifestContent $manifest
        }

        It 'exits 0 (report mode does not fail the job)' { $R2.ExitCode | Should -Be 0 }
        It 'reports copyleft-lib as DENIED (GPL-3.0)' { $R2.Output | Should -Match 'copyleft-lib@1\.0\.0 \[GPL-3\.0\] -> DENIED' }
        It 'reports express as APPROVED'              { $R2.Output | Should -Match 'express@4\.18\.2 \[MIT\] -> APPROVED' }
        It 'shows the exact summary counts'           { $R2.Output | Should -Match 'Total: 2 \| Approved: 1 \| Denied: 1 \| Unknown: 0' }
        It 'shows an overall FAIL verdict'            { $R2.Output | Should -Match 'Compliance: FAIL' }
        It 'shows both jobs succeeding' {
            ([regex]::Matches($R2.Output, 'Job succeeded')).Count | Should -BeGreaterOrEqual 2
        }
    }

    Context 'Case 3: an unknown license via requirements.txt' {
        BeforeAll {
            $manifest = @'
flask==2.3.2
ghost-pkg==0.0.1
'@
            $script:R3 = Invoke-ActCase -CaseName 'unknown-requirements' `
                -ManifestFileName 'requirements.txt' -ManifestContent $manifest `
                -ManifestEnvOverride 'fixtures/requirements.txt'
        }

        It 'exits 0' { $R3.ExitCode | Should -Be 0 }
        It 'reports flask as APPROVED (BSD-3-Clause)' { $R3.Output | Should -Match 'flask@2\.3\.2 \[BSD-3-Clause\] -> APPROVED' }
        It 'reports ghost-pkg as UNKNOWN'             { $R3.Output | Should -Match 'ghost-pkg@0\.0\.1 \[UNKNOWN\] -> UNKNOWN' }
        It 'shows the exact summary counts'           { $R3.Output | Should -Match 'Total: 2 \| Approved: 1 \| Denied: 0 \| Unknown: 1' }
        It 'shows PASS (unknown licenses do not break compliance, only denied do)' {
            $R3.Output | Should -Match 'Compliance: PASS'
        }
        It 'shows both jobs succeeding' {
            ([regex]::Matches($R3.Output, 'Job succeeded')).Count | Should -BeGreaterOrEqual 2
        }
    }
}
