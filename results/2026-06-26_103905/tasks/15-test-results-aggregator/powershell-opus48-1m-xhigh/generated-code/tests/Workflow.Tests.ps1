#requires -Modules Pester

# Workflow tests, split into two groups:
#
#   1. "Workflow file: structure & static validation" (fast, no Docker) — parses the
#      YAML, checks triggers/jobs/steps, verifies referenced script paths exist, and
#      asserts actionlint passes (exit 0).
#
#   2. "End-to-end workflow execution via act" (tagged 'Act', slow) — the MANDATORY
#      act harness. For each fixture case it builds a temp git repo, runs
#      `act push --rm`, appends the output to act-result.txt, and asserts on EXACT
#      expected values plus "Job succeeded".
#
# Run only the fast checks with:   Invoke-Pester ./tests/Workflow.Tests.ps1 -ExcludeTagFilter Act
# Run the full act harness with:    Invoke-Pester ./tests/Workflow.Tests.ps1 -TagFilter Act

BeforeDiscovery {
    # Resolve project layout once so both Describe blocks can use it.
    $script:Root         = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:WorkflowPath = Join-Path $script:Root '.github' 'workflows' 'test-results-aggregator.yml'
}

Describe 'Workflow file: structure & static validation' {
    BeforeAll {
        $script:Root         = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
        $script:WorkflowPath = Join-Path $script:Root '.github' 'workflows' 'test-results-aggregator.yml'
        $script:Text         = Get-Content -LiteralPath $script:WorkflowPath -Raw

        $script:HasYaml = $false
        try { Import-Module powershell-yaml -ErrorAction Stop; $script:HasYaml = $true } catch { }
        if ($script:HasYaml) { $script:Wf = ConvertFrom-Yaml $script:Text }
    }

    It 'workflow file exists' {
        Test-Path -LiteralPath $script:WorkflowPath | Should -BeTrue
    }

    It 'passes actionlint with exit code 0' {
        $out = & actionlint $script:WorkflowPath 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ("actionlint output:`n" + ($out | Out-String))
    }

    It 'declares all expected trigger events' {
        $script:HasYaml | Should -BeTrue
        $on = $script:Wf['on']
        $on.Keys | Should -Contain 'push'
        $on.Keys | Should -Contain 'pull_request'
        $on.Keys | Should -Contain 'workflow_dispatch'
        $on.Keys | Should -Contain 'schedule'
    }

    It 'sets least-privilege permissions (contents: read)' {
        $script:Wf['permissions']['contents'] | Should -Be 'read'
    }

    It 'defines a test job and a dependent aggregate job' {
        $script:Wf['jobs'].Keys | Should -Contain 'test'
        $script:Wf['jobs'].Keys | Should -Contain 'aggregate'
    }

    It 'wires the job dependency (aggregate needs test)' {
        $script:Wf['jobs']['aggregate']['needs'] | Should -Be 'test'
    }

    It 'runs both jobs on ubuntu-latest' {
        $script:Wf['jobs']['test']['runs-on']      | Should -Be 'ubuntu-latest'
        $script:Wf['jobs']['aggregate']['runs-on'] | Should -Be 'ubuntu-latest'
    }

    It 'checks out the repo with actions/checkout@v4 in every job' {
        foreach ($jobName in @('test', 'aggregate')) {
            $uses = @($script:Wf['jobs'][$jobName]['steps'] | ForEach-Object { $_['uses'] }) -join ' '
            $uses | Should -Match 'actions/checkout@v4'
        }
    }

    It 'uses shell: pwsh for PowerShell steps (not pwsh -File/-Command via bash)' {
        $script:Text | Should -Match 'shell:\s*pwsh'
        $script:Text | Should -Not -Match 'pwsh\s+-File'
        $script:Text | Should -Not -Match 'pwsh\s+-Command\s+["'']\./'
    }

    It 'references the aggregator script, which exists on disk' {
        $script:Text | Should -Match '\./Invoke-Aggregator\.ps1'
        Test-Path -LiteralPath (Join-Path $script:Root 'Invoke-Aggregator.ps1') | Should -BeTrue
    }

    It 'references the unit test file, which exists on disk' {
        $script:Text | Should -Match 'tests/TestResultsAggregator\.Tests\.ps1'
        Test-Path -LiteralPath (Join-Path $script:Root 'tests' 'TestResultsAggregator.Tests.ps1') | Should -BeTrue
    }

    It 'references the module, which exists on disk' {
        Test-Path -LiteralPath (Join-Path $script:Root 'TestResultsAggregator.psm1') | Should -BeTrue
    }
}

Describe 'End-to-end workflow execution via act' -Tag 'Act' {
    BeforeAll {
        $script:Root       = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
        $script:ResultFile = Join-Path $script:Root 'act-result.txt'

        # Strip ANSI color codes so exact-value assertions are robust against act's coloring.
        function Remove-Ansi {
            param([string]$Text)
            return ($Text -replace "`e\[[0-9;]*m", '')
        }

        # Build a temp git repo (project files + this case's fixture data), run act, and
        # append the delimited output to act-result.txt. Returns exit code + cleaned output.
        function Invoke-ActCase {
            param(
                [string]$CaseName,
                [string]$FixturesSource,   # dir whose .xml/.json files become the workflow input
                [string]$Root,
                [string]$ResultFile
            )

            $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("act-trf-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $tmp | Out-Null
            try {
                # Copy the project skeleton, but NOT root fixtures/ (set per case below).
                foreach ($item in @('TestResultsAggregator.psm1', 'Invoke-Aggregator.ps1', '.actrc')) {
                    Copy-Item -LiteralPath (Join-Path $Root $item) -Destination $tmp
                }
                Copy-Item -LiteralPath (Join-Path $Root '.github') -Destination $tmp -Recurse
                Copy-Item -LiteralPath (Join-Path $Root 'tests')   -Destination $tmp -Recurse

                # Populate the workflow's input dir (root fixtures/) from this case's fixtures.
                $fixturesDir = Join-Path $tmp 'fixtures'
                New-Item -ItemType Directory -Path $fixturesDir | Out-Null
                Get-ChildItem -LiteralPath $FixturesSource -File |
                    Where-Object { $_.Extension -in @('.xml', '.json') } |
                    ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $fixturesDir }

                # act needs a committed tree to run the push event.
                Push-Location $tmp
                try {
                    git init -q              2>&1 | Out-Null
                    git config user.email 'ci@example.com' 2>&1 | Out-Null
                    git config user.name  'CI'             2>&1 | Out-Null
                    git add -A               2>&1 | Out-Null
                    git commit -q -m "fixture: $CaseName"  2>&1 | Out-Null

                    # --pull=false uses the local act-ubuntu-pwsh image (mapped in .actrc)
                    # instead of trying to pull the registry-less tag.
                    $output = & act push --rm --pull=false 2>&1 | Out-String
                    $code   = $LASTEXITCODE
                }
                finally { Pop-Location }

                $delim = ('=' * 78)
                $block = (@(
                    $delim
                    "ACT TEST CASE: $CaseName"
                    "act exit code: $code"
                    $delim
                    $output
                    ''
                ) -join "`n")
                Add-Content -LiteralPath $ResultFile -Value $block -Encoding utf8

                return [PSCustomObject]@{
                    CaseName    = $CaseName
                    ExitCode    = $code
                    Output      = $output
                    CleanOutput = (Remove-Ansi $output)
                }
            }
            finally {
                Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        # Fresh artifact file for this run.
        Set-Content -LiteralPath $script:ResultFile `
            -Value "act-result log — Test Results Aggregator workflow`n" -Encoding utf8

        $caseAFixtures = Join-Path $script:Root 'fixtures'                  # Case A: flaky matrix
        $caseBFixtures = Join-Path $PSScriptRoot 'fixtures' 'caseB'         # Case B: all-green

        # Two cases, run once each = exactly two `act push` invocations.
        $script:resA = Invoke-ActCase -CaseName 'A-flaky-matrix' -FixturesSource $caseAFixtures -Root $script:Root -ResultFile $script:ResultFile
        $script:resB = Invoke-ActCase -CaseName 'B-all-green'    -FixturesSource $caseBFixtures -Root $script:Root -ResultFile $script:ResultFile
    }

    Context 'Case A — flaky matrix (3 files: 2 JUnit XML + 1 JSON)' {
        It 'act exits 0' {
            $script:resA.ExitCode | Should -Be 0 -Because $script:resA.CleanOutput
        }
        It 'both jobs report "Job succeeded"' {
            ([regex]::Matches($script:resA.CleanOutput, 'Job succeeded')).Count | Should -BeGreaterOrEqual 2
        }
        It 'runs the unit tests inside the pipeline' {
            $script:resA.CleanOutput | Should -Match 'unit tests passed'
        }
        It 'aggregates exactly 3 files' {
            $script:resA.CleanOutput | Should -Match 'FILES_PARSED=3'
        }
        It 'computes exact totals (15 / 8 / 4 / 3)' {
            $script:resA.CleanOutput | Should -Match 'TOTAL_TESTS=15'
            $script:resA.CleanOutput | Should -Match 'PASSED=8'
            $script:resA.CleanOutput | Should -Match 'FAILED=4'
            $script:resA.CleanOutput | Should -Match 'SKIPPED=3'
        }
        It 'computes exact total duration (2.46s)' {
            $script:resA.CleanOutput | Should -Match 'DURATION_SECONDS=2\.46'
        }
        It 'detects exactly one flaky test: Net.fetch' {
            $script:resA.CleanOutput | Should -Match 'FLAKY_COUNT=1'
            $script:resA.CleanOutput | Should -Match 'FLAKY_TESTS=Net\.fetch'
        }
        It 'reports overall FAILED and renders the markdown verdict' {
            $script:resA.CleanOutput | Should -Match 'OVERALL=FAILED'
            $script:resA.CleanOutput | Should -Match '\*\*FAILED\*\*'
        }
    }

    Context 'Case B — all-green (2 files: 1 JSON + 1 JUnit XML, no flaky)' {
        It 'act exits 0' {
            $script:resB.ExitCode | Should -Be 0 -Because $script:resB.CleanOutput
        }
        It 'both jobs report "Job succeeded"' {
            ([regex]::Matches($script:resB.CleanOutput, 'Job succeeded')).Count | Should -BeGreaterOrEqual 2
        }
        It 'aggregates exactly 2 files' {
            $script:resB.CleanOutput | Should -Match 'FILES_PARSED=2'
        }
        It 'computes exact totals (4 / 4 / 0 / 0)' {
            $script:resB.CleanOutput | Should -Match 'TOTAL_TESTS=4'
            $script:resB.CleanOutput | Should -Match 'PASSED=4'
            $script:resB.CleanOutput | Should -Match 'FAILED=0'
            $script:resB.CleanOutput | Should -Match 'SKIPPED=0'
        }
        It 'computes exact total duration (1.05s)' {
            $script:resB.CleanOutput | Should -Match 'DURATION_SECONDS=1\.05'
        }
        It 'detects zero flaky tests' {
            $script:resB.CleanOutput | Should -Match 'FLAKY_COUNT=0'
            $script:resB.CleanOutput | Should -Match 'FLAKY_TESTS=\(none\)'
        }
        It 'reports overall PASSED and renders the markdown verdict' {
            $script:resB.CleanOutput | Should -Match 'OVERALL=PASSED'
            $script:resB.CleanOutput | Should -Match '\*\*PASSED\*\*'
        }
    }

    Context 'act-result.txt artifact' {
        It 'exists and contains both delimited test cases' {
            Test-Path -LiteralPath $script:ResultFile | Should -BeTrue
            $content = Get-Content -LiteralPath $script:ResultFile -Raw
            $content | Should -Match 'ACT TEST CASE: A-flaky-matrix'
            $content | Should -Match 'ACT TEST CASE: B-all-green'
        }
    }
}
