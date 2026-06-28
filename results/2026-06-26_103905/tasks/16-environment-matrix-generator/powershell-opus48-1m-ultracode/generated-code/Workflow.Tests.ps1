# Workflow.Tests.ps1
#
# Verifies the GitHub Actions workflow that ships the matrix generator:
#
#   1. Structure tests  -- parse the workflow YAML and assert it has the expected
#      triggers, permissions, jobs, dependencies and steps, and that every file
#      it references actually exists.
#   2. actionlint       -- assert the workflow passes actionlint (exit code 0).
#   3. act integration  -- run the whole pipeline in Docker via `act push`,
#      capture the output to act-result.txt, and assert on EXACT expected values
#      for every fixture/test case (counts, excluded combos, include extensions,
#      oversize rejection) plus that every job reports "Job succeeded".
#
# Per the task constraints `act` is invoked exactly ONCE: the workflow itself
# exercises every fixture case (basic / exclude / include / oversize) and the
# downstream build job, so a single run validates all cases while staying well
# within the act-invocation budget.
#
# Run with: Invoke-Pester

BeforeAll {
    $script:Root         = $PSScriptRoot
    $script:WorkflowPath = Join-Path $script:Root '.github/workflows/environment-matrix-generator.yml'

    Import-Module powershell-yaml -ErrorAction Stop
    $script:Workflow = ConvertFrom-Yaml (Get-Content -LiteralPath $script:WorkflowPath -Raw)
}

Describe 'Workflow structure' {
    It 'is valid, parseable YAML with a name' {
        $script:Workflow | Should -Not -BeNullOrEmpty
        $script:Workflow['name'] | Should -Be 'Environment Matrix Generator'
    }

    It 'declares the expected trigger events' {
        $triggers = $script:Workflow['on']
        $triggers.Keys | Should -Contain 'push'
        $triggers.Keys | Should -Contain 'pull_request'
        $triggers.Keys | Should -Contain 'workflow_dispatch'
        $triggers.Keys | Should -Contain 'schedule'
    }

    It 'requests least-privilege contents:read permission' {
        $script:Workflow['permissions']['contents'] | Should -Be 'read'
    }

    It 'defines the generate-matrix and build jobs' {
        $script:Workflow['jobs'].Keys | Should -Contain 'generate-matrix'
        $script:Workflow['jobs'].Keys | Should -Contain 'build'
    }

    It 'makes build depend on generate-matrix' {
        $script:Workflow['jobs']['build']['needs'] | Should -Be 'generate-matrix'
    }

    It 'publishes the generated matrix as a job output' {
        $script:Workflow['jobs']['generate-matrix']['outputs']['matrix'] |
            Should -Match 'steps\.basic\.outputs\.matrix'
    }

    It 'consumes the generated matrix in the build job via fromJSON' {
        $matrixExpr = $script:Workflow['jobs']['build']['strategy']['matrix']
        $matrixExpr | Should -Match 'fromJSON\(needs\.generate-matrix\.outputs\.matrix\)'
    }

    It 'uses actions/checkout@v4' {
        $steps = $script:Workflow['jobs']['generate-matrix']['steps']
        ($steps | Where-Object { $_['uses'] -eq 'actions/checkout@v4' }) | Should -Not -BeNullOrEmpty
    }

    It 'invokes the generator script via shell: pwsh' {
        $steps = $script:Workflow['jobs']['generate-matrix']['steps']
        $runSteps = $steps | Where-Object { $_.ContainsKey('run') -and $_['run'] -match 'Invoke-MatrixGenerator\.ps1' }
        $runSteps | Should -Not -BeNullOrEmpty
        foreach ($s in $runSteps) { $s['shell'] | Should -Be 'pwsh' }
    }
}

Describe 'Workflow references existing files' {
    It 'references a generator script that exists' {
        Test-Path -LiteralPath (Join-Path $script:Root 'Invoke-MatrixGenerator.ps1') | Should -BeTrue
    }

    It 'references a module that exists' {
        Test-Path -LiteralPath (Join-Path $script:Root 'MatrixGenerator.psm1') | Should -BeTrue
    }

    It 'references fixture configs that exist' {
        foreach ($f in 'basic', 'exclude', 'include', 'oversize') {
            Test-Path -LiteralPath (Join-Path $script:Root "fixtures/$f.config.json") | Should -BeTrue
        }
    }
}

Describe 'actionlint' {
    It 'passes actionlint with exit code 0' {
        $actionlint = Get-Command actionlint -ErrorAction SilentlyContinue
        if (-not $actionlint) { Set-ItResult -Skipped -Because 'actionlint is not installed'; return }

        $output = & actionlint $script:WorkflowPath 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($output -join "`n")
    }
}

Describe 'Pipeline execution via act' {
    BeforeAll {
        $script:ActOutput  = ''
        $script:ActExit    = $null
        $script:ResultFile = Join-Path $script:Root 'act-result.txt'

        $haveAct    = [bool](Get-Command act -ErrorAction SilentlyContinue)
        $haveDocker = [bool](Get-Command docker -ErrorAction SilentlyContinue)
        $script:CanRunAct = $haveAct -and $haveDocker

        if ($script:CanRunAct) {
            # --- Build an isolated temp git repo with just the project files. ---
            $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("matrixact-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $tmp -Force | Out-Null
            try {
                Copy-Item (Join-Path $script:Root 'Invoke-MatrixGenerator.ps1') $tmp
                Copy-Item (Join-Path $script:Root 'MatrixGenerator.psm1') $tmp
                Copy-Item (Join-Path $script:Root '.actrc') $tmp
                Copy-Item (Join-Path $script:Root 'fixtures') $tmp -Recurse
                $wfDir = Join-Path $tmp '.github/workflows'
                New-Item -ItemType Directory -Path $wfDir -Force | Out-Null
                Copy-Item $script:WorkflowPath $wfDir

                Push-Location $tmp
                try {
                    git init -q 2>&1 | Out-Null
                    git -c user.name=test -c user.email=test@test add -A 2>&1 | Out-Null
                    git -c user.name=test -c user.email=test@test commit -qm 'matrix generator test' 2>&1 | Out-Null

                    # Single act run -- exercises every fixture case and the build job.
                    # --pull=false keeps act on the locally-built pwsh image.
                    $script:ActOutput = (& act push --rm --pull=false 2>&1 | Out-String)
                    $script:ActExit = $LASTEXITCODE
                }
                finally {
                    Pop-Location
                }
            }
            finally {
                Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
            }

            # --- Persist the required artifact, with a clear per-case index. ---
            $header = @(
                '=== Environment Matrix Generator -- act push results ==='
                "Generated by Workflow.Tests.ps1   exit-code=$script:ActExit"
                ''
                'Test cases exercised in this single act run:'
                '  [basic]    fixtures/basic.config.json    -> expect 2 combinations'
                '  [exclude]  fixtures/exclude.config.json  -> expect 5 combinations (macos+node18 excluded)'
                '  [include]  fixtures/include.config.json  -> expect 2 combinations (coverage + experimental)'
                '  [oversize] fixtures/oversize.config.json -> expect rejection (15 > max-size 10)'
                '  [build]    consumes the basic matrix     -> 2 fan-out build jobs'
                ''
                '----- BEGIN act output -----'
            ) -join [Environment]::NewLine
            $footer = [Environment]::NewLine + '----- END act output -----' + [Environment]::NewLine
            Set-Content -LiteralPath $script:ResultFile -Value ($header + [Environment]::NewLine + $script:ActOutput + $footer) -Encoding utf8
        }
    }

    It 'produced the act-result.txt artifact' {
        if (-not $script:CanRunAct) { Set-ItResult -Skipped -Because 'act/docker not available'; return }
        Test-Path -LiteralPath $script:ResultFile | Should -BeTrue
    }

    It 'completed with act exit code 0' {
        if (-not $script:CanRunAct) { Set-ItResult -Skipped -Because 'act/docker not available'; return }
        $script:ActExit | Should -Be 0 -Because $script:ActOutput
    }

    It 'reports every job as succeeded (generate-matrix + 2 build jobs)' {
        if (-not $script:CanRunAct) { Set-ItResult -Skipped -Because 'act/docker not available'; return }
        $succeeded = ([regex]::Matches($script:ActOutput, 'Job succeeded')).Count
        $succeeded | Should -BeGreaterOrEqual 3
        $script:ActOutput | Should -Not -Match 'Job failed'
    }

    It 'expands the basic matrix to exactly 2 combinations' {
        if (-not $script:CanRunAct) { Set-ItResult -Skipped -Because 'act/docker not available'; return }
        $script:ActOutput | Should -Match 'MATRIX_COUNT\[basic\.config\.json\]=2'
    }

    It 'applies exclude rules: 5 combinations and macos-latest/node18 removed' {
        if (-not $script:CanRunAct) { Set-ItResult -Skipped -Because 'act/docker not available'; return }
        $script:ActOutput | Should -Match 'MATRIX_COUNT\[exclude\.config\.json\]=5'
        # Pull the exclude case's matrix JSON line and assert the excluded combo is gone.
        $line = ($script:ActOutput -split "`n" | Where-Object { $_ -match 'MATRIX_INCLUDE\[exclude\.config\.json\]=' }) -join ''
        $line | Should -Not -BeNullOrEmpty
        $json = ($line -replace '.*MATRIX_INCLUDE\[exclude\.config\.json\]=', '').Trim()
        $combos = ($json | ConvertFrom-Json).include
        @($combos).Count | Should -Be 5
        ($combos | Where-Object { $_.os -eq 'macos-latest' -and $_.node -eq 18 }) | Should -BeNullOrEmpty
        ($combos | Where-Object { $_.os -eq 'macos-latest' -and $_.node -eq 20 }) | Should -Not -BeNullOrEmpty
    }

    It 'applies include rules: coverage extension + standalone experimental combo' {
        if (-not $script:CanRunAct) { Set-ItResult -Skipped -Because 'act/docker not available'; return }
        $script:ActOutput | Should -Match 'MATRIX_COUNT\[include\.config\.json\]=2'
        $line = ($script:ActOutput -split "`n" | Where-Object { $_ -match 'MATRIX_INCLUDE\[include\.config\.json\]=' }) -join ''
        $json = ($line -replace '.*MATRIX_INCLUDE\[include\.config\.json\]=', '').Trim()
        $combos = ($json | ConvertFrom-Json).include
        $base = $combos | Where-Object { $_.os -eq 'ubuntu-latest' -and $_.node -eq 20 }
        $base.coverage | Should -BeTrue
        $extra = $combos | Where-Object { $_.os -eq 'windows-latest' -and $_.node -eq 22 }
        $extra.experimental | Should -BeTrue
    }

    It 'rejects the oversized matrix with a count-bearing message' {
        if (-not $script:CanRunAct) { Set-ItResult -Skipped -Because 'act/docker not available'; return }
        $script:ActOutput | Should -Match 'OVERSIZE_REJECTED=true'
        $script:ActOutput | Should -Match 'OVERSIZE_MESSAGE=.*15 combinations.*exceeds.*10'
    }

    It 'fans the generated matrix out into the build job (exact combos)' {
        if (-not $script:CanRunAct) { Set-ItResult -Skipped -Because 'act/docker not available'; return }
        $script:ActOutput | Should -Match 'BUILD_COMBO os=ubuntu-latest node=20'
        $script:ActOutput | Should -Match 'BUILD_COMBO os=windows-latest node=20'
    }
}
