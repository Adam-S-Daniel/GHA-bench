#Requires -Modules Pester

# Acceptance / integration tests for the Environment Matrix Generator.
#
# Every functional test case is executed END TO END through the GitHub Actions
# workflow using nektos/act. For each case we build an isolated temp git repo
# containing the project files plus that case's fixture config, run
# `act push --rm`, capture the output into act-result.txt, and assert on the
# EXACT expected values produced by the pipeline.
#
# A second set of (fast, no-act) tests validates the static structure of the
# workflow file and that it references the script correctly.

BeforeAll {
    $script:ProjectRoot = $PSScriptRoot
    $script:WorkflowPath = Join-Path $ProjectRoot '.github/workflows/environment-matrix-generator.yml'
    $script:ActResultPath = Join-Path $ProjectRoot 'act-result.txt'
    $script:ScriptPath = Join-Path $ProjectRoot 'MatrixGenerator.ps1'

    # Start each run with a fresh aggregate log.
    Set-Content -LiteralPath $script:ActResultPath -Value "act run log - environment-matrix-generator`n" -Encoding utf8

    # Helper: build an isolated repo for a case, run act, return the result.
    function script:Invoke-ActCase {
        param(
            [Parameter(Mandatory)] [string]$Name,
            [Parameter(Mandatory)] [hashtable]$Config
        )

        $work = Join-Path ([System.IO.Path]::GetTempPath()) ("act-" + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $work | Out-Null
        try {
            # Copy the project files needed to run the workflow.
            Copy-Item (Join-Path $ProjectRoot 'MatrixGenerator.ps1') $work
            Copy-Item (Join-Path $ProjectRoot 'MatrixGenerator.Tests.ps1') $work
            Copy-Item (Join-Path $ProjectRoot '.actrc') $work
            New-Item -ItemType Directory -Path (Join-Path $work '.github/workflows') -Force | Out-Null
            Copy-Item $script:WorkflowPath (Join-Path $work '.github/workflows')
            New-Item -ItemType Directory -Path (Join-Path $work 'fixtures') -Force | Out-Null

            # Write this case's fixture config.
            $Config | ConvertTo-Json -Depth 8 |
                Set-Content -LiteralPath (Join-Path $work 'fixtures/config.json') -Encoding utf8

            # act needs a git repository.
            Push-Location $work
            try {
                git init -q 2>&1 | Out-Null
                git config user.email 'ci@example.com' 2>&1 | Out-Null
                git config user.name 'CI' 2>&1 | Out-Null
                git add -A 2>&1 | Out-Null
                git commit -q -m 'fixture' 2>&1 | Out-Null

                $output = & act push --rm 2>&1 | Out-String
                $code = $LASTEXITCODE
            }
            finally {
                Pop-Location
            }

            # Append clearly-delimited output to the aggregate log.
            $delim = "`n========== CASE: $Name (exit=$code) ==========`n"
            Add-Content -LiteralPath $script:ActResultPath -Value $delim -Encoding utf8
            Add-Content -LiteralPath $script:ActResultPath -Value $output -Encoding utf8

            return [pscustomobject]@{ Output = $output; ExitCode = $code }
        }
        finally {
            if (Test-Path $work) { Remove-Item -Recurse -Force $work }
        }
    }
}

Describe 'Workflow static structure' {
    It 'workflow file exists' {
        Test-Path $script:WorkflowPath | Should -BeTrue
    }

    It 'passes actionlint with exit code 0' {
        & actionlint $script:WorkflowPath 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 0
    }

    It 'declares the expected trigger events' {
        $content = Get-Content $script:WorkflowPath -Raw
        $content | Should -Match '(?m)^on:'
        $content | Should -Match 'push:'
        $content | Should -Match 'pull_request:'
        $content | Should -Match 'workflow_dispatch:'
        $content | Should -Match 'schedule:'
    }

    It 'defines both jobs with a dependency between them' {
        $content = Get-Content $script:WorkflowPath -Raw
        $content | Should -Match '(?m)^\s{2}test:'
        $content | Should -Match '(?m)^\s{2}generate:'
        $content | Should -Match 'needs:\s*test'
    }

    It 'sets least-privilege read permissions' {
        Get-Content $script:WorkflowPath -Raw | Should -Match 'contents:\s*read'
    }

    It 'uses actions/checkout@v4 and references the generator script' {
        $content = Get-Content $script:WorkflowPath -Raw
        $content | Should -Match 'actions/checkout@v4'
        $content | Should -Match 'MatrixGenerator\.ps1'
    }

    It 'references project files that actually exist on disk' {
        Test-Path (Join-Path $script:ProjectRoot 'MatrixGenerator.ps1') | Should -BeTrue
        Test-Path (Join-Path $script:ProjectRoot 'MatrixGenerator.Tests.ps1') | Should -BeTrue
        Test-Path (Join-Path $script:ProjectRoot 'fixtures/config.json') | Should -BeTrue
    }
}

Describe 'Workflow execution through act' {

    It 'Case 1: exclude + include matrix yields exactly size 3' {
        $config = @{
            matrix      = @{
                os      = @('ubuntu-latest', 'windows-latest')
                node    = @(18, 20)
                exclude = @( @{ os = 'windows-latest'; node = 18 } )
                include = @( @{ os = 'ubuntu-latest'; node = 18; coverage = $true } )
            }
            maxParallel = 3
            failFast    = $false
            maxSize     = 50
        }
        $r = script:Invoke-ActCase -Name 'exclude-include' -Config $config

        $r.ExitCode | Should -Be 0
        # Exact expected values from the pipeline output.
        $r.Output | Should -Match '(?m)GENERATED_MATRIX_SIZE=3\s*$'
        $r.Output | Should -Match '(?m)GENERATED_INCLUDE_COUNT=3\s*$'
        $r.Output | Should -Match '(?m)GENERATED_FAIL_FAST=False\s*$'
        $r.Output | Should -Match '(?m)GENERATED_MAX_PARALLEL=3\s*$'
        # Both jobs must report success.
        ([regex]::Matches($r.Output, 'Job succeeded')).Count | Should -BeGreaterOrEqual 2
    }

    It 'Case 2: full cartesian product yields exactly size 6' {
        $config = @{
            matrix   = @{
                os   = @('ubuntu-latest', 'macos-latest')
                node = @(16, 18, 20)
            }
            failFast = $true
        }
        $r = script:Invoke-ActCase -Name 'full-cartesian' -Config $config

        $r.ExitCode | Should -Be 0
        $r.Output | Should -Match '(?m)GENERATED_MATRIX_SIZE=6\s*$'
        $r.Output | Should -Match '(?m)GENERATED_INCLUDE_COUNT=6\s*$'
        $r.Output | Should -Match '(?m)GENERATED_FAIL_FAST=True\s*$'
        ([regex]::Matches($r.Output, 'Job succeeded')).Count | Should -BeGreaterOrEqual 2
    }

    It 'Case 3: include-only matrix yields exactly size 2 with exact JSON' {
        # Ordered hashtables keep the JSON key order deterministic (os, node)
        # so the exact-match assertion below is stable.
        $config = [ordered]@{
            matrix = [ordered]@{
                include = @(
                    [ordered]@{ os = 'ubuntu-latest'; node = 20 }
                    [ordered]@{ os = 'macos-latest'; node = 18 }
                )
            }
        }
        $r = script:Invoke-ActCase -Name 'include-only' -Config $config

        $r.ExitCode | Should -Be 0
        $r.Output | Should -Match '(?m)GENERATED_MATRIX_SIZE=2\s*$'
        $r.Output | Should -Match '(?m)GENERATED_INCLUDE_COUNT=2\s*$'
        $r.Output | Should -Match '(?m)GENERATED_FAIL_FAST=True\s*$'
        # Exact, known-good compacted matrix emitted as a step output.
        $r.Output | Should -Match '::set-output:: matrix=\{"include":\[\{"os":"ubuntu-latest","node":20\},\{"os":"macos-latest","node":18\}\]\}'
        ([regex]::Matches($r.Output, 'Job succeeded')).Count | Should -BeGreaterOrEqual 2
    }
}
