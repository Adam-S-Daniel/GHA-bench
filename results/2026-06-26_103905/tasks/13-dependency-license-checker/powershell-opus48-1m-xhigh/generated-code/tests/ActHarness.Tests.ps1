#requires -Modules Pester
<#
    ActHarness.Tests.ps1

    End-to-end test harness that exercises the dependency-license-checker
    EXCLUSIVELY through the GitHub Actions pipeline, using `act` (nektos/act).

    For every test case the harness:
        1. creates a throwaway git repo containing the project files plus the
           case's fixture manifest,
        2. runs `act push --rm` against the workflow (injecting the manifest
           path via `--env MANIFEST_FILE=...`),
        3. captures the combined output and appends it (clearly delimited) to
           ../act-result.txt,
        4. asserts the act process exited 0, that both jobs report
           "Job succeeded", and that the rendered report contains the EXACT
           expected per-dependency lines and summary counts for that input.

    All three `act` runs happen once, inside the single BeforeAll, so running
    this file performs exactly three `act push` invocations regardless of how
    many assertions reference the captured output.
#>

BeforeAll {
    $script:RepoRoot   = Split-Path $PSScriptRoot -Parent
    $script:ResultFile = Join-Path $script:RepoRoot 'act-result.txt'
    $script:Image      = 'act-ubuntu-pwsh:latest'
    $script:ActExe     = (Get-Command act -ErrorAction Stop).Source

    # Disable ANSI colour so captured act output is plain text we can match on.
    $env:NO_COLOR = '1'

    # Project files copied into every throwaway repo. The act-orchestrating
    # tests themselves are intentionally NOT copied so the in-container Pester
    # run only sees the unit tests.
    $script:ProjectItems = @(
        'LicenseChecker.psm1',
        'Invoke-LicenseCheck.ps1',
        'config',
        'fixtures',
        'examples',
        '.github',
        '.actrc'
    )

    # The three end-to-end cases with their pre-computed, known-good output.
    $script:Cases = @(
        @{
            Name         = 'case-a-mixed-package'
            ManifestSrc  = Join-Path $script:RepoRoot 'cases/case-a-mixed-package/manifest.json'
            ManifestRel  = 'ci-input/manifest.json'
            ExpectLines  = @(
                'DEP | express | ^4.18.2 | MIT | Approved',
                'DEP | gpl-tool | 1.2.0 | GPL-3.0 | Denied',
                'DEP | mystery-pkg | ^2.0.0 | Unknown | Unknown',
                'SUMMARY | Total: 3 | Approved: 1 | Denied: 1 | Unknown: 1',
                'RESULT: FAIL'
            )
        },
        @{
            Name         = 'case-b-requirements'
            ManifestSrc  = Join-Path $script:RepoRoot 'cases/case-b-requirements/manifest.txt'
            ManifestRel  = 'ci-input/manifest.txt'
            ExpectLines  = @(
                'DEP | requests | 2.31.0 | Apache-2.0 | Approved',
                'DEP | flask | 2.0.0 | BSD-3-Clause | Approved',
                'DEP | copyleft-pkg | 1.0.0 | GPL-2.0 | Denied',
                'SUMMARY | Total: 3 | Approved: 2 | Denied: 1 | Unknown: 0',
                'RESULT: FAIL'
            )
        },
        @{
            Name         = 'case-c-all-approved'
            ManifestSrc  = Join-Path $script:RepoRoot 'cases/case-c-all-approved/manifest.json'
            ManifestRel  = 'ci-input/manifest.json'
            ExpectLines  = @(
                'DEP | express | ^4.18.2 | MIT | Approved',
                'DEP | lodash | ^4.17.21 | MIT | Approved',
                'DEP | chalk | 5.3.0 | MIT | Approved',
                'SUMMARY | Total: 3 | Approved: 3 | Denied: 0 | Unknown: 0',
                'RESULT: PASS'
            )
        }
    )

    # Helper: build a throwaway git repo for a case and run the workflow in act.
    function Invoke-ActCase {
        param([hashtable]$Case)

        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("act-" + [System.Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null

        try {
            # Copy project files into the throwaway repo.
            foreach ($item in $script:ProjectItems) {
                $src = Join-Path $script:RepoRoot $item
                if (Test-Path -LiteralPath $src) {
                    Copy-Item -LiteralPath $src -Destination $tmp -Recurse -Force
                }
            }
            # Copy ONLY the unit-test file the workflow runs.
            New-Item -ItemType Directory -Path (Join-Path $tmp 'tests') -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'tests/LicenseChecker.Tests.ps1') `
                      -Destination (Join-Path $tmp 'tests') -Force

            # Drop in this case's fixture manifest at the exact path the workflow
            # reads (ci-input/manifest.<ext>), creating the parent directory.
            $manifestDest = Join-Path $tmp $Case.ManifestRel
            New-Item -ItemType Directory -Path (Split-Path $manifestDest -Parent) -Force | Out-Null
            Copy-Item -LiteralPath $Case.ManifestSrc -Destination $manifestDest -Force

            # Initialise a throwaway git repo on 'main' and commit everything so
            # actions/checkout@v4 has a committed tree to check out.
            Push-Location $tmp
            try {
                git init -b main --quiet 2>&1 | Out-Null
                git add -A 2>&1 | Out-Null
                git -c user.name='ci' -c user.email='ci@example.com' commit -q -m 'fixture' 2>&1 | Out-Null

                $actArgs = @(
                    'push', '--rm',
                    '-P', "ubuntu-latest=$script:Image",
                    '--pull=false',
                    '--env', "MANIFEST_FILE=$($Case.ManifestRel)",
                    '-W', '.github/workflows/dependency-license-checker.yml'
                )

                $output   = & $script:ActExe @actArgs 2>&1 | Out-String
                $exitCode = $LASTEXITCODE
            }
            finally {
                Pop-Location
            }

            return [pscustomobject]@{
                ExitCode = $exitCode
                Output   = $output
            }
        }
        finally {
            Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # --- Run every case once and persist the output to act-result.txt --------
    "=== act-result.txt :: dependency-license-checker e2e run ===" |
        Set-Content -LiteralPath $script:ResultFile -Encoding utf8

    $script:Results = @{}
    foreach ($case in $script:Cases) {
        $res = Invoke-ActCase -Case $case
        $script:Results[$case.Name] = $res

        $delimiter = @(
            '',
            '################################################################',
            "## TEST CASE: $($case.Name)",
            "## manifest : $($case.ManifestRel)",
            "## act exit : $($res.ExitCode)",
            '################################################################'
        ) -join "`n"

        Add-Content -LiteralPath $script:ResultFile -Value $delimiter
        Add-Content -LiteralPath $script:ResultFile -Value $res.Output
    }
}

Describe 'Dependency license checker (end-to-end via act)' {

    It 'produced the act-result.txt artifact' {
        Test-Path -LiteralPath $script:ResultFile | Should -BeTrue
        (Get-Content -LiteralPath $script:ResultFile -Raw).Length | Should -BeGreaterThan 0
    }

    Context 'case-a-mixed-package (package.json: approved + denied + unknown)' {
        BeforeAll { $script:R = $script:Results['case-a-mixed-package'] }

        It 'act exited with code 0' { $script:R.ExitCode | Should -Be 0 }

        It 'both jobs reported "Job succeeded"' {
            ([regex]::Matches($script:R.Output, 'Job succeeded')).Count | Should -BeGreaterOrEqual 2
        }

        It 'output contains the exact expected report lines' {
            foreach ($line in @(
                    'DEP | express | ^4.18.2 | MIT | Approved',
                    'DEP | gpl-tool | 1.2.0 | GPL-3.0 | Denied',
                    'DEP | mystery-pkg | ^2.0.0 | Unknown | Unknown',
                    'SUMMARY | Total: 3 | Approved: 1 | Denied: 1 | Unknown: 1',
                    'RESULT: FAIL'
                )) {
                $script:R.Output.Contains($line) | Should -BeTrue -Because "expected '$line'"
            }
        }
    }

    Context 'case-b-requirements (requirements.txt: 2 approved + 1 denied)' {
        BeforeAll { $script:R = $script:Results['case-b-requirements'] }

        It 'act exited with code 0' { $script:R.ExitCode | Should -Be 0 }

        It 'both jobs reported "Job succeeded"' {
            ([regex]::Matches($script:R.Output, 'Job succeeded')).Count | Should -BeGreaterOrEqual 2
        }

        It 'output contains the exact expected report lines' {
            foreach ($line in @(
                    'DEP | requests | 2.31.0 | Apache-2.0 | Approved',
                    'DEP | flask | 2.0.0 | BSD-3-Clause | Approved',
                    'DEP | copyleft-pkg | 1.0.0 | GPL-2.0 | Denied',
                    'SUMMARY | Total: 3 | Approved: 2 | Denied: 1 | Unknown: 0',
                    'RESULT: FAIL'
                )) {
                $script:R.Output.Contains($line) | Should -BeTrue -Because "expected '$line'"
            }
        }
    }

    Context 'case-c-all-approved (package.json: all approved -> PASS)' {
        BeforeAll { $script:R = $script:Results['case-c-all-approved'] }

        It 'act exited with code 0' { $script:R.ExitCode | Should -Be 0 }

        It 'both jobs reported "Job succeeded"' {
            ([regex]::Matches($script:R.Output, 'Job succeeded')).Count | Should -BeGreaterOrEqual 2
        }

        It 'output contains the exact expected report lines' {
            foreach ($line in @(
                    'DEP | express | ^4.18.2 | MIT | Approved',
                    'DEP | lodash | ^4.17.21 | MIT | Approved',
                    'DEP | chalk | 5.3.0 | MIT | Approved',
                    'SUMMARY | Total: 3 | Approved: 3 | Denied: 0 | Unknown: 0',
                    'RESULT: PASS'
                )) {
                $script:R.Output.Contains($line) | Should -BeTrue -Because "expected '$line'"
            }
        }

        It 'did NOT flag the clean manifest as failing' {
            # A clean manifest must report PASS and never FAIL.
            $script:R.Output.Contains('RESULT: PASS') | Should -BeTrue
            $script:R.Output.Contains('RESULT: FAIL') | Should -BeFalse
        }
    }
}
