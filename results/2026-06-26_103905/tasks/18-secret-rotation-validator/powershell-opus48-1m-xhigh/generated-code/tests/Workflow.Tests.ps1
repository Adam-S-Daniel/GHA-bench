# Workflow.Tests.ps1
#
# Two groups of tests for the GitHub Actions integration:
#
#   1. Structure / lint tests (tag 'Structure') -- fast, no Docker. They parse
#      the workflow YAML, assert its shape (triggers, jobs, steps, matrix,
#      dependencies), confirm it references files that actually exist, and run
#      actionlint as a subprocess asserting a clean exit.
#
#   2. Act integration test (tag 'Act') -- runs the ENTIRE workflow in Docker via
#      `act push`. Because the workflow uses a matrix over every fixture, a
#      SINGLE act invocation exercises every test case. The run is performed once
#      in BeforeAll; the full transcript is written to act-result.txt (a required
#      artifact) and every per-fixture assertion is made against that captured
#      output -- asserting EXACT expected counts, exit code 0, and that every job
#      reports "Job succeeded".
#
# Run fast checks only:   Invoke-Pester ./tests/Workflow.Tests.ps1 -Tag Structure
# Run the act check:      Invoke-Pester ./tests/Workflow.Tests.ps1 -Tag Act

BeforeDiscovery {
    $script:RepoRoot     = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:WorkflowPath = Join-Path $script:RepoRoot '.github/workflows/secret-rotation-validator.yml'
}

Describe 'Workflow structure' -Tag 'Structure' {

    BeforeAll {
        Import-Module powershell-yaml -ErrorAction Stop
        $script:RepoRoot     = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
        $script:WorkflowPath = Join-Path $script:RepoRoot '.github/workflows/secret-rotation-validator.yml'
        $script:Raw          = Get-Content -LiteralPath $script:WorkflowPath -Raw
        $script:Wf           = $script:Raw | ConvertFrom-Yaml

        # The YAML key `on` can be coerced to a boolean by some parsers; resolve
        # the triggers map whichever way it landed.
        $script:Triggers =
            if ($script:Wf.ContainsKey('on'))   { $script:Wf['on'] }
            elseif ($script:Wf.ContainsKey($true)) { $script:Wf[$true] }
            else { @{} }
    }

    It 'is valid, parseable YAML with a name' {
        $script:Wf            | Should -Not -BeNullOrEmpty
        $script:Wf.name       | Should -Be 'Secret Rotation Validator'
    }

    It 'declares all four expected trigger events' {
        foreach ($t in 'push', 'pull_request', 'schedule', 'workflow_dispatch') {
            $script:Triggers.ContainsKey($t) | Should -BeTrue -Because "trigger '$t' must be present"
        }
    }

    It 'defines a schedule with a cron expression' {
        $script:Triggers['schedule'][0].cron | Should -Match '^\s*\d|\*'
    }

    It 'exposes a workflow_dispatch format input for selecting output format' {
        $inputs = $script:Triggers['workflow_dispatch'].inputs
        $inputs.ContainsKey('format')         | Should -BeTrue
        $inputs.format.options                | Should -Contain 'markdown'
        $inputs.format.options                | Should -Contain 'json'
    }

    It 'grants least-privilege read-only contents permission' {
        $script:Wf.permissions.contents | Should -Be 'read'
    }

    It 'sets a workflow-level env var pointing at the validator script' {
        $script:Wf.env.VALIDATOR_SCRIPT | Should -Be './Invoke-SecretRotationValidator.ps1'
    }

    It 'defines validate and report jobs' {
        $script:Wf.jobs.Keys | Should -Contain 'validate'
        $script:Wf.jobs.Keys | Should -Contain 'report'
    }

    It 'runs validate as a matrix over every fixture' {
        $fixtures = $script:Wf.jobs.validate.strategy.matrix.fixture
        $fixtures | Should -Contain 'healthy'
        $fixtures | Should -Contain 'mixed'
        $fixtures | Should -Contain 'all-expired'
    }

    It 'makes the report job depend on validate (job dependency)' {
        # `needs` may be a scalar or a list depending on YAML form.
        @($script:Wf.jobs.report.needs) | Should -Contain 'validate'
    }

    It 'checks out the repo with actions/checkout@v4' {
        $uses = $script:Wf.jobs.validate.steps | ForEach-Object { $_.uses } | Where-Object { $_ }
        $uses | Should -Contain 'actions/checkout@v4'
    }

    It 'runs its PowerShell steps with shell: pwsh (not pwsh -File from bash)' {
        $pwshSteps = $script:Wf.jobs.validate.steps | Where-Object { $_.shell -eq 'pwsh' }
        @($pwshSteps).Count | Should -BeGreaterThan 0
        # No step should shell out to `pwsh -File`/`pwsh -Command` from bash.
        foreach ($step in $script:Wf.jobs.validate.steps) {
            if ($step.run) { $step.run | Should -Not -Match 'pwsh\s+-(File|Command)' }
        }
    }
}

Describe 'Workflow references existing files' -Tag 'Structure' {

    BeforeAll {
        $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    }

    It 'references a validator script that exists on disk' {
        Test-Path (Join-Path $script:RepoRoot 'Invoke-SecretRotationValidator.ps1') | Should -BeTrue
    }

    It 'references the core module that exists on disk' {
        Test-Path (Join-Path $script:RepoRoot 'SecretRotation.psm1') | Should -BeTrue
    }

    It 'references fixture files that all exist on disk' {
        foreach ($name in 'healthy', 'mixed', 'all-expired') {
            Test-Path (Join-Path $script:RepoRoot "fixtures/$name.json") |
                Should -BeTrue -Because "fixtures/$name.json must exist"
        }
    }
}

Describe 'actionlint validation' -Tag 'Structure' {

    BeforeAll {
        $script:RepoRoot     = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
        $script:WorkflowPath = Join-Path $script:RepoRoot '.github/workflows/secret-rotation-validator.yml'
    }

    It 'passes actionlint with exit code 0' {
        if (-not (Get-Command actionlint -ErrorAction SilentlyContinue)) {
            Set-ItResult -Skipped -Because 'actionlint is not installed'
            return
        }
        $output = & actionlint $script:WorkflowPath 2>&1
        $code = $LASTEXITCODE
        if ($code -ne 0) { Write-Host ($output | Out-String) }
        $code | Should -Be 0
    }
}

Describe 'Act end-to-end pipeline' -Tag 'Act' {

    BeforeAll {
        $script:RepoRoot      = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
        $script:ActResultPath = Join-Path $script:RepoRoot 'act-result.txt'

        # Known-good expected RESULT lines per fixture (exact values).
        $script:Expected = @{
            'healthy'     = 'RESULT fixture=healthy expired=0 warning=0 ok=3 total=3'
            'mixed'       = 'RESULT fixture=mixed expired=2 warning=2 ok=1 total=5'
            'all-expired' = 'RESULT fixture=all-expired expired=2 warning=0 ok=0 total=2'
        }
        # Expected JSON-OK confirmation lines emitted by the second step.
        $script:ExpectedJson = @{
            'healthy'     = 'JSON OK for healthy: expired=0 warning=0 ok=3 total=3'
            'mixed'       = 'JSON OK for mixed: expired=2 warning=2 ok=1 total=5'
            'all-expired' = 'JSON OK for all-expired: expired=2 warning=0 ok=0 total=2'
        }

        $script:ActAvailable =
            [bool](Get-Command act -ErrorAction SilentlyContinue) -and
            [bool](Get-Command docker -ErrorAction SilentlyContinue)

        $script:ActOutput = ''
        $script:ActExit   = -1

        # Start the artifact fresh for this run (the file is appended to below).
        if (Test-Path $script:ActResultPath) { Remove-Item -LiteralPath $script:ActResultPath -Force }

        if ($script:ActAvailable) {
            # --- 1. assemble an isolated temp git repo with just our files ----
            $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("srv-act-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $tmp -Force | Out-Null
            try {
                foreach ($item in 'Invoke-SecretRotationValidator.ps1', 'SecretRotation.psm1', 'fixtures', '.github', '.actrc') {
                    $src = Join-Path $script:RepoRoot $item
                    if (Test-Path $src) {
                        Copy-Item -Path $src -Destination $tmp -Recurse -Force
                    }
                }

                Push-Location $tmp
                try {
                    # --- 2. commit so actions/checkout has something to clone ---
                    git init -q 2>&1 | Out-Null
                    git config user.email 'test@example.com' 2>&1 | Out-Null
                    git config user.name  'Test Runner'       2>&1 | Out-Null
                    git add -A 2>&1 | Out-Null
                    git commit -q -m 'secret rotation validator test fixture' 2>&1 | Out-Null

                    # --- 3. run the whole workflow in Docker, capture all output
                    # --pull=false: the act-ubuntu-pwsh image is built locally and
                    # is not in any registry, so a (default) force-pull would fail
                    # with a registry auth error. The local image is already present.
                    $script:ActOutput = (& act push --rm --pull=false 2>&1 | Out-String)
                    $script:ActExit   = $LASTEXITCODE
                }
                finally {
                    Pop-Location
                }
            }
            finally {
                if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
            }

            # --- 4. persist the required artifact (always, even on failure) ----
            $header = @(
                '================================================================'
                "ACT RUN  (single 'act push' invocation; matrix covers all fixtures)"
                "Timestamp : $(Get-Date -Format o)"
                "Exit code : $script:ActExit"
                '================================================================'
            ) -join [Environment]::NewLine

            $sections = foreach ($name in $script:Expected.Keys) {
                $resultLine = ($script:ActOutput -split "`r?`n" | Where-Object { $_ -match [regex]::Escape($script:Expected[$name]) } | Select-Object -First 1)
                @(
                    ''
                    "---- TEST CASE: $name ----"
                    "Expected RESULT : $($script:Expected[$name])"
                    "Found in output : $([bool]$resultLine)"
                    ($resultLine ? "Matched line    : $($resultLine.Trim())" : 'Matched line    : <none>')
                ) -join [Environment]::NewLine
            }

            $jobSucceeded = ([regex]::Matches($script:ActOutput, 'Job succeeded')).Count

            $body = @(
                $header
                ''
                '---- RAW ACT OUTPUT ----'
                $script:ActOutput
                ''
                '---- PER-FIXTURE ASSERTIONS ----'
                ($sections -join [Environment]::NewLine)
                ''
                "Jobs reporting 'Job succeeded': $jobSucceeded"
                '================================================================'
                ''
            ) -join [Environment]::NewLine

            Add-Content -LiteralPath $script:ActResultPath -Value $body -Encoding utf8
        }
    }

    It 'has act and docker available' {
        $script:ActAvailable | Should -BeTrue -Because 'the benchmark environment pre-installs act + Docker'
    }

    It 'produces the act-result.txt artifact' {
        Test-Path $script:ActResultPath | Should -BeTrue
        (Get-Item $script:ActResultPath).Length | Should -BeGreaterThan 0
    }

    It 'completes the act run with exit code 0' {
        $script:ActExit | Should -Be 0
    }

    It 'reports Job succeeded for every job (3 validate legs + 1 report)' {
        $count = ([regex]::Matches($script:ActOutput, 'Job succeeded')).Count
        $count | Should -BeGreaterOrEqual 4
    }

    It 'never reports a failed job' {
        $script:ActOutput | Should -Not -Match 'Job failed'
    }

    It 'emits the exact RESULT line for fixture <_>' -ForEach @('healthy', 'mixed', 'all-expired') {
        $expectedLine = $script:Expected[$_]
        $script:ActOutput | Should -Match ([regex]::Escape($expectedLine))
    }

    It 'emits the exact JSON-format confirmation for fixture <_>' -ForEach @('healthy', 'mixed', 'all-expired') {
        $expectedLine = $script:ExpectedJson[$_]
        $script:ActOutput | Should -Match ([regex]::Escape($expectedLine))
    }

    It 'renders a markdown report heading in the pipeline output' {
        $script:ActOutput | Should -Match 'Secret Rotation Report'
    }
}
