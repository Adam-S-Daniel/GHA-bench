#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    End-to-end tests for the PR Label Assigner GitHub Actions workflow.

.DESCRIPTION
    Two groups of tests:

      1. 'Workflow structure' (fast, no Docker) — parses the YAML with
         powershell-yaml and asserts the triggers / jobs / steps / script
         references are correct, and that actionlint passes cleanly.

      2. 'Workflow execution via act' (tagged 'act') — for each test case it
         builds a throwaway git repo containing the project + that case's
         fixture, runs `act push --rm`, appends the output to act-result.txt,
         and asserts:
            * act exited 0
            * the printed LABELS line equals the known-good value
            * every job reports "Job succeeded"

    Run everything:                 Invoke-Pester ./Workflow.Tests.ps1
    Structure tests only (no act):  Invoke-Pester ./Workflow.Tests.ps1 -ExcludeTagFilter act
    act tests only:                 Invoke-Pester ./Workflow.Tests.ps1 -TagFilter act
#>

BeforeDiscovery {
    # Case names only — needed at DISCOVERY time so Pester can expand the
    # -ForEach data-driven `It` blocks. The full case data (fixtures + expected
    # labels) lives in the act Describe's BeforeAll (run time); each case's
    # expected value is stored alongside its result so the `It`s read
    # everything from $script:Run. (In Pester v5, variables set in
    # BeforeDiscovery are NOT guaranteed to survive into the run phase.)
    $script:CaseNames = @('docs-and-tests', 'api-conflict', 'stop-dependencies')
}

BeforeAll {
    $script:ProjectRoot = $PSScriptRoot
    $script:WorkflowPath = Join-Path $script:ProjectRoot '.github/workflows/pr-label-assigner.yml'
    $script:ActResultPath = Join-Path $script:ProjectRoot 'act-result.txt'

    Import-Module powershell-yaml -ErrorAction Stop
    $script:Workflow = Get-Content -LiteralPath $script:WorkflowPath -Raw | ConvertFrom-Yaml

    # Strip ANSI colour codes so output can be parsed reliably.
    function Remove-Ansi {
        param([string]$Text)
        return ($Text -replace "`e\[[0-9;]*m", '')
    }
}

Describe 'Workflow structure' {

    It 'is valid YAML that powershell-yaml can parse' {
        $script:Workflow | Should -Not -BeNullOrEmpty
    }

    It 'defines the expected trigger events' {
        # PyYAML/powershell-yaml interpret the bare key `on:` as the boolean
        # $true, so look it up resiliently.
        $triggers = if ($script:Workflow.ContainsKey('on')) { $script:Workflow['on'] } else { $script:Workflow[$true] }
        $triggers.Keys | Should -Contain 'push'
        $triggers.Keys | Should -Contain 'pull_request'
        $triggers.Keys | Should -Contain 'workflow_dispatch'
        $triggers.Keys | Should -Contain 'schedule'
    }

    It 'declares least-privilege permissions' {
        $script:Workflow.permissions.contents | Should -Be 'read'
        $script:Workflow.permissions.'pull-requests' | Should -Be 'write'
    }

    It 'defines both jobs' {
        $script:Workflow.jobs.Keys | Should -Contain 'test'
        $script:Workflow.jobs.Keys | Should -Contain 'assign-labels'
    }

    It 'wires the job dependency (assign-labels needs test)' {
        $script:Workflow.jobs.'assign-labels'.needs | Should -Be 'test'
    }

    It 'checks out the repo with actions/checkout@v4 in every job' {
        foreach ($jobName in $script:Workflow.jobs.Keys) {
            $uses = $script:Workflow.jobs[$jobName].steps.uses
            $uses | Should -Contain 'actions/checkout@v4'
        }
    }

    It 'invokes the assigner script via pwsh' {
        $runSteps = $script:Workflow.jobs.'assign-labels'.steps |
            Where-Object { $_.ContainsKey('run') }
        ($runSteps.run -join "`n") | Should -Match 'Invoke-PrLabelAssigner\.ps1'
        ($runSteps.shell | Select-Object -Unique) | Should -Contain 'pwsh'
    }

    It 'references the config path through an environment variable' {
        $script:Workflow.env.CONFIG_PATH | Should -Be 'config/labels.json'
    }
}

Describe 'Referenced files exist on disk' {
    It "'<_>' exists" -ForEach @(
        'PrLabelAssigner.psm1'
        'Invoke-PrLabelAssigner.ps1'
        'PrLabelAssigner.Tests.ps1'
        'config/labels.json'
        'fixtures/changed-files.txt'
        '.github/workflows/pr-label-assigner.yml'
    ) {
        Test-Path -LiteralPath (Join-Path $script:ProjectRoot $_) | Should -BeTrue
    }
}

Describe 'actionlint validation' {
    It 'passes actionlint with exit code 0' {
        $null = & actionlint $script:WorkflowPath 2>&1
        $LASTEXITCODE | Should -Be 0
    }
}

Describe 'Workflow execution via act' -Tag 'act' {

    BeforeAll {
        # Full case data, defined here (run phase) so it is guaranteed present.
        # Each Expected value is derived from config/labels.json.
        $cases = @(
            @{
                Name     = 'docs-and-tests'
                Files    = @('docs/intro.md', 'docs/guide/setup.md', 'README.md', 'src/utils/helper.test.js')
                Expected = 'tests,source,documentation'
            }
            @{
                Name     = 'api-conflict'
                Files    = @('src/api/users.js', 'src/api/orders.js', 'src/components/Button.tsx')
                Expected = 'api,backend,source'
            }
            @{
                Name     = 'stop-dependencies'
                Files    = @('package.json', 'config/database.json', '.github/workflows/deploy.yml')
                Expected = 'dependencies,ci,config'
            }
        )

        # Files/dirs copied into each throwaway repo. Workflow.Tests.ps1 is
        # deliberately EXCLUDED so the harness can never invoke act inside act.
        $filesToCopy = @('PrLabelAssigner.psm1', 'Invoke-PrLabelAssigner.ps1', 'PrLabelAssigner.Tests.ps1', '.actrc')
        $dirsToCopy = @('config', 'fixtures', '.github')

        # Fresh act-result.txt for this run.
        Set-Content -LiteralPath $script:ActResultPath -Value "act run log - PR Label Assigner`n" -Encoding utf8

        $script:Run = @{}

        foreach ($case in $cases) {
            # --- 1. Build a throwaway git repo with project files + fixture ---
            $repo = Join-Path ([System.IO.Path]::GetTempPath()) ("pr-label-act-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $repo -Force | Out-Null

            foreach ($f in $filesToCopy) {
                Copy-Item -LiteralPath (Join-Path $script:ProjectRoot $f) -Destination $repo -Force
            }
            foreach ($d in $dirsToCopy) {
                Copy-Item -LiteralPath (Join-Path $script:ProjectRoot $d) -Destination $repo -Recurse -Force
            }

            # This case's fixture data overwrites the default changed-file list.
            $fixturePath = Join-Path $repo 'fixtures/changed-files.txt'
            Set-Content -LiteralPath $fixturePath -Value ($case.Files -join "`n") -Encoding utf8

            # Commit so actions/checkout@v4 has something to check out.
            & git -C $repo init -q
            & git -C $repo config user.email 'ci@example.com'
            & git -C $repo config user.name 'CI'
            & git -C $repo add -A
            & git -C $repo commit -q -m "fixture: $($case.Name)"

            # --- 2. Run act, capturing combined output + exit code ---
            $actArgs = @(
                'push', '--rm',
                '--pull=false',                # use the local custom image as-is
                '--action-offline-mode',       # use the cached actions/checkout@v4
                '-P', 'ubuntu-latest=act-ubuntu-pwsh:latest'
            )
            Push-Location $repo
            try {
                $raw = (& act @actArgs 2>&1 | Out-String)
                $code = $LASTEXITCODE
            }
            finally {
                Pop-Location
            }

            $clean = Remove-Ansi -Text $raw
            $script:Run[$case.Name] = @{ Exit = $code; Output = $clean; Expected = $case.Expected }

            # --- 3. Append clearly-delimited output to act-result.txt ---
            $delim = ('=' * 70)
            Add-Content -LiteralPath $script:ActResultPath -Encoding utf8 -Value @(
                $delim
                "TEST CASE: $($case.Name)"
                "CHANGED FILES: $($case.Files -join ', ')"
                "EXPECTED LABELS: $($case.Expected)"
                "ACT EXIT CODE: $code"
                $delim
                $clean
                ''
            )

            # Best-effort cleanup of the throwaway repo.
            Remove-Item -LiteralPath $repo -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'act exited 0 for case <_>' -ForEach $script:CaseNames {
        $script:Run[$_].Exit | Should -Be 0
    }

    It 'emitted the exact LABELS for case <_>' -ForEach $script:CaseNames {
        $result = $script:Run[$_]
        # Match the script's own LABELS= line, not the STEP-OUTPUT-LABELS= echo.
        $m = [regex]::Match($result.Output, '(?<![\w-])LABELS=(?<v>[A-Za-z0-9,_-]*)')
        $m.Success | Should -BeTrue -Because "the workflow should print a LABELS= line for $_"
        $m.Groups['v'].Value | Should -Be $result.Expected
    }

    It 'every job reported success for case <_>' -ForEach $script:CaseNames {
        $out = $script:Run[$_].Output
        $out | Should -Not -Match 'Job failed'
        # Two jobs (test + assign-labels) must each report success.
        ([regex]::Matches($out, 'Job succeeded')).Count | Should -BeGreaterOrEqual 2
    }
}
