#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
    END-TO-END PIPELINE TESTS via `act` (nektos/act).

    Every label-assignment scenario is exercised through the REAL GitHub Actions
    workflow — not by calling the script directly. For each test case the harness:

      1. Builds a throwaway git repo containing the project files plus that
         case's fixture (the simulated changed-file list) and an expected-labels
         assertion file.
      2. Runs `act push --rm` against it (exactly one act invocation per case).
      3. Appends the full act output to act-result.txt (clearly delimited).
      4. Asserts: act exited 0, every job reported "Job succeeded", the
         LABELS_BEGIN/LABELS_END frame matches the case's EXACT expected labels
         (in order), and the in-workflow assertion fired (ASSERTION_PASSED).

    Pester runs Discovery and Run in separate passes and does NOT carry
    top-level functions/variables (or BeforeDiscovery state) into Run. So all
    helper functions and the act loop live inside the Describe-level BeforeAll
    (Run phase), and per-case results are published via $script:Results, which
    the It blocks read. Discovery provides only the case list for -ForEach.

    Run just this suite with:
        Invoke-Pester -Path ./tests/Act.Workflow.Tests.ps1
#>

# Case list for Discovery (drives -ForEach + Context titles). The Run phase
# rebuilds the same list independently; expected labels are re-asserted from the
# Run-phase copy, so any drift between the two surfaces as a failure.
BeforeDiscovery {
    $cases = @(
        @{ Name = 'docs-only' }
        @{ Name = 'api-tests-and-group-conflict' }
        @{ Name = 'no-match' }
    )
}

Describe 'PR Label Assigner end-to-end via act' {

    BeforeAll {
        # ---- Helper functions (defined in the Run scope where they are used) ----

        function Initialize-ActWorkRepo {
            param(
                [Parameter(Mandatory)] [string]   $Source,
                [Parameter(Mandatory)] [string]   $Dest,
                [Parameter(Mandatory)] [string[]] $ChangedFiles,
                [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $ExpectedLabels
            )
            foreach ($item in @('PRLabelAssigner.psm1', 'Invoke-PRLabelAssigner.ps1', 'labeler-rules.json', '.actrc', '.github', 'tests')) {
                $src = Join-Path $Source $item
                if (Test-Path -LiteralPath $src) {
                    Copy-Item -LiteralPath $src -Destination $Dest -Recurse -Force
                }
            }
            # Write the per-case fixtures fresh (do NOT copy the repo's samples).
            $fixtureDir = Join-Path $Dest 'fixtures'
            New-Item -ItemType Directory -Path $fixtureDir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $fixtureDir 'changed-files.txt') -Value ($ChangedFiles -join "`n") -Encoding utf8
            $expectedContent = if ($ExpectedLabels.Count -eq 0) { '# no labels expected' } else { $ExpectedLabels -join "`n" }
            Set-Content -LiteralPath (Join-Path $fixtureDir 'expected-labels.txt') -Value $expectedContent -Encoding utf8

            Push-Location $Dest
            try {
                git init -q 2>&1 | Out-Null
                git config user.email 'harness@example.com' 2>&1 | Out-Null
                git config user.name  'PR Label Harness'    2>&1 | Out-Null
                git config commit.gpgsign false             2>&1 | Out-Null
                git checkout -q -b main 2>&1 | Out-Null
                git add -A 2>&1 | Out-Null
                git commit -q -m 'fixture commit' 2>&1 | Out-Null
            }
            finally { Pop-Location }
        }

        function Invoke-ActPush {
            param([Parameter(Mandatory)] [string] $WorkDir)
            Push-Location $WorkDir
            try {
                # Capture stdout+stderr together; the copied .actrc maps
                # ubuntu-latest -> the pwsh-enabled image. --pull=false: that
                # image is built locally and never pushed to a registry, so a
                # (default) force-pull would fail with "pull access denied".
                $output = & act push --rm --pull=false --container-architecture linux/amd64 2>&1
                return [pscustomobject]@{
                    ExitCode = $LASTEXITCODE
                    Lines    = @($output | ForEach-Object { [string]$_ })
                }
            }
            finally { Pop-Location }
        }

        function Get-FramedLabel {
            param([Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $Lines)
            $labels  = [System.Collections.Generic.List[string]]::new()
            $inFrame = $false
            foreach ($raw in $Lines) {
                $clean = $raw   -replace "`e\[[0-9;]*m", ''   # ESC-style ANSI
                $clean = $clean -replace '\x1b\[[0-9;]*m', '' # belt-and-suspenders
                $clean = $clean -replace '^.*?\|\s?', ''      # drop act's '[Job]  | ' prefix
                $clean = $clean.Trim()
                if     ($clean -ceq 'LABELS_END')   { $inFrame = $false; continue }
                elseif ($inFrame)                   { if ($clean) { $labels.Add($clean) } }
                elseif ($clean -ceq 'LABELS_BEGIN') { $inFrame = $true }
            }
            # Plain (unrolled) return so a caller's @(...) wrap stays flat rather
            # than nesting the array inside a single-element array.
            return $labels.ToArray()
        }

        # ---- Environment / tooling ----
        $script:RepoRoot   = Split-Path $PSScriptRoot -Parent
        $script:ResultFile = Join-Path $script:RepoRoot 'act-result.txt'
        foreach ($tool in 'act', 'docker', 'git') {
            if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
                throw "Required tool '$tool' not found on PATH."
            }
        }

        # ---- Test cases (single source of truth for inputs + expectations) ----
        # Expectations match labeler-rules.json and were verified against the
        # script directly before any act run.
        $runCases = @(
            @{
                Name           = 'docs-only'
                ChangedFiles   = @('docs/intro.md', 'docs/guide/setup.md')
                ExpectedLabels = @('documentation')
            },
            @{
                # api/backend(50) -> tests(40) -> documentation(10), then the
                # 'area' group resolves to area/api(9) over area/core(5)
                # (conflict resolution). README.md adds 'documentation' via **/*.md.
                Name           = 'api-tests-and-group-conflict'
                ChangedFiles   = @('src/api/users.ps1', 'src/api/users.test.ps1', 'README.md')
                ExpectedLabels = @('api', 'backend', 'tests', 'documentation', 'area/api')
            },
            @{
                Name           = 'no-match'
                ChangedFiles   = @('LICENSE', '.gitignore')
                ExpectedLabels = @()
            }
        )

        # ---- Run every case through act exactly once; cache parsed results. ----
        "PR Label Assigner - act results" | Set-Content -LiteralPath $script:ResultFile -Encoding utf8
        $script:Results = @{}

        foreach ($case in $runCases) {
            $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("pr-label-act-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $tmp -Force | Out-Null
            try {
                Initialize-ActWorkRepo -Source $script:RepoRoot -Dest $tmp `
                    -ChangedFiles   $case.ChangedFiles `
                    -ExpectedLabels $case.ExpectedLabels

                $run = Invoke-ActPush -WorkDir $tmp

                $expectedDisplay = if ($case.ExpectedLabels.Count -eq 0) { '<none>' } else { $case.ExpectedLabels -join ', ' }
                $header = @"

================================================================================
Test case      : $($case.Name)
ChangedFiles   : $($case.ChangedFiles -join ', ')
ExpectedLabels : $expectedDisplay
act exit code  : $($run.ExitCode)
================================================================================
"@
                Add-Content -LiteralPath $script:ResultFile -Value $header -Encoding utf8
                Add-Content -LiteralPath $script:ResultFile -Value ($run.Lines -join "`n") -Encoding utf8

                $script:Results[$case.Name] = [pscustomobject]@{
                    ExitCode       = $run.ExitCode
                    Labels         = @(Get-FramedLabel -Lines $run.Lines)
                    ExpectedLabels = @($case.ExpectedLabels)
                    JobsSucceeded  = @($run.Lines | Where-Object { $_ -match 'Job succeeded' }).Count
                    SawAssertion   = @($run.Lines | Where-Object { $_ -match 'ASSERTION_PASSED' }).Count -ge 1
                }
            }
            finally {
                Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'produced act-result.txt' {
        Test-Path -LiteralPath $script:ResultFile | Should -BeTrue
    }

    Context 'case <Name>' -ForEach $cases {

        It 'act exited with code 0' {
            $script:Results[$Name].ExitCode | Should -Be 0
        }

        It 'both jobs reported "Job succeeded"' {
            $script:Results[$Name].JobsSucceeded | Should -BeGreaterOrEqual 2
        }

        It 'the in-workflow assertion fired (ASSERTION_PASSED)' {
            $script:Results[$Name].SawAssertion | Should -BeTrue
        }

        It 'emitted exactly the expected labels, in order' {
            $r = $script:Results[$Name]
            ($r.Labels -join '|') | Should -BeExactly ($r.ExpectedLabels -join '|')
        }
    }
}
