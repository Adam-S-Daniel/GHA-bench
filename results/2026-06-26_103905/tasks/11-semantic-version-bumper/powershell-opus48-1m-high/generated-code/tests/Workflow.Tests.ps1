#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

#
# Workflow.Tests.ps1
#
# Two kinds of tests for the GitHub Actions workflow:
#
#   1. Structure tests  - parse the workflow YAML and assert its triggers, jobs,
#                         steps and script references are correct, and that
#                         actionlint validates it cleanly. (fast, no Docker)
#
#   2. act integration  - for every test case, build an isolated temp git repo
#                         containing the project + that case's fixture data, run
#                         the workflow with `act push --rm`, capture the output to
#                         act-result.txt, and assert on the EXACT expected version
#                         the pipeline produced. (slow, requires Docker)
#
# Per the task, all script behaviour is exercised THROUGH the pipeline here.
#

BeforeAll {
    $script:RepoRoot     = Split-Path -Parent $PSScriptRoot
    $script:WorkflowPath = Join-Path $script:RepoRoot '.github/workflows/semantic-version-bumper.yml'
    $script:ResultFile   = Join-Path $script:RepoRoot 'act-result.txt'

    Import-Module powershell-yaml -ErrorAction Stop
    $script:Workflow = ConvertFrom-Yaml (Get-Content -Raw -Path $script:WorkflowPath)

    # The act image is built locally; map it explicitly and skip docker pulls.
    $script:ActImage = 'act-ubuntu-pwsh:latest'
    $script:ActArgs  = @('push', '--rm', '--pull=false',
                         '-P', "ubuntu-latest=$script:ActImage")

    # Runs the workflow in an isolated, committed temp git repo seeded with the
    # given version-file contents and commit-log fixture. Returns the act exit
    # code and combined output.
    function script:Invoke-ActCase {
        param(
            [string]$VersionFileName,   # e.g. 'VERSION' or 'package.json'
            [string]$VersionContent,    # initial file contents
            [string]$FixtureName        # fixture file under fixtures/ to use as commits.log
        )

        $temp = Join-Path ([System.IO.Path]::GetTempPath()) ("svb-act-" + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $temp -Force | Out-Null
        try {
            # Copy the project under test into the temp repo.
            foreach ($item in @('src', 'tests', 'fixtures', 'Invoke-VersionBump.ps1')) {
                Copy-Item -Path (Join-Path $script:RepoRoot $item) -Destination $temp -Recurse -Force
            }
            New-Item -ItemType Directory -Path (Join-Path $temp '.github/workflows') -Force | Out-Null
            Copy-Item -Path $script:WorkflowPath -Destination (Join-Path $temp '.github/workflows') -Force

            # Seed this case's version source and commit-log fixture.
            Set-Content -Path (Join-Path $temp $VersionFileName) -Value $VersionContent -NoNewline
            Copy-Item -Path (Join-Path $script:RepoRoot "fixtures/$FixtureName") `
                      -Destination (Join-Path $temp 'commits.log') -Force

            # act's checkout uses the committed tree, so commit everything.
            Push-Location $temp
            try {
                git init -q              2>&1 | Out-Null
                git config user.email 'ci@example.com' | Out-Null
                git config user.name  'ci'             | Out-Null
                git add -A               2>&1 | Out-Null
                git commit -qm 'fixture' 2>&1 | Out-Null

                # When the version source is package.json, override the env input.
                $extra = @()
                if ($VersionFileName -ne 'VERSION') {
                    $extra = @('--env', "VERSION_FILE=$VersionFileName")
                }

                $output = & act @script:ActArgs @extra 2>&1 | Out-String
                $code   = $LASTEXITCODE
            }
            finally {
                Pop-Location
            }

            return [pscustomobject]@{ ExitCode = $code; Output = $output }
        }
        finally {
            Remove-Item -Path $temp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # Append a clearly delimited block for a case to act-result.txt.
    function script:Add-ActResult {
        param([string]$Name, [int]$ExitCode, [string]$Output)
        $banner = ('=' * 78)
        $block = @(
            $banner,
            "TEST CASE: $Name",
            "ACT EXIT CODE: $ExitCode",
            $banner,
            $Output,
            ''
        ) -join [Environment]::NewLine
        Add-Content -Path $script:ResultFile -Value $block
    }
}

Describe 'Workflow structure' {
    It 'is valid YAML that parses to a mapping' {
        $script:Workflow | Should -BeOfType [System.Collections.IDictionary]
    }

    It 'has the expected name' {
        $script:Workflow['name'] | Should -Be 'Semantic Version Bumper'
    }

    It 'declares all required trigger events' {
        $on = $script:Workflow['on']
        $on.Keys | Should -Contain 'push'
        $on.Keys | Should -Contain 'pull_request'
        $on.Keys | Should -Contain 'schedule'
        $on.Keys | Should -Contain 'workflow_dispatch'
    }

    It 'sets least-privilege contents:read permissions' {
        $script:Workflow['permissions']['contents'] | Should -Be 'read'
    }

    It 'defines both the test and bump jobs' {
        $script:Workflow['jobs'].Keys | Should -Contain 'test'
        $script:Workflow['jobs'].Keys | Should -Contain 'bump'
    }

    It 'makes the bump job depend on the test job' {
        $script:Workflow['jobs']['bump']['needs'] | Should -Be 'test'
    }

    It 'runs both jobs on ubuntu-latest' {
        $script:Workflow['jobs']['test']['runs-on'] | Should -Be 'ubuntu-latest'
        $script:Workflow['jobs']['bump']['runs-on'] | Should -Be 'ubuntu-latest'
    }

    It 'checks out the repo with actions/checkout@v4 in every job' {
        foreach ($jobName in @('test', 'bump')) {
            $uses = $script:Workflow['jobs'][$jobName]['steps'] | ForEach-Object { $_['uses'] }
            $uses | Should -Contain 'actions/checkout@v4'
        }
    }

    It 'uses the pwsh shell for run steps (not pwsh -Command from bash)' {
        $runSteps = $script:Workflow['jobs']['bump']['steps'] | Where-Object { $_.ContainsKey('run') }
        $runSteps.Count | Should -BeGreaterThan 0
        foreach ($step in $runSteps) {
            $step['shell'] | Should -Be 'pwsh'
        }
    }

    It 'references the Invoke-VersionBump.ps1 entry script' {
        (Get-Content -Raw -Path $script:WorkflowPath) | Should -Match 'Invoke-VersionBump\.ps1'
    }

    It 'references the Pester test file' {
        (Get-Content -Raw -Path $script:WorkflowPath) | Should -Match 'SemanticVersionBumper\.Tests\.ps1'
    }
}

Describe 'Referenced script files exist on disk' {
    It 'has the entry script <_>' -ForEach @(
        'Invoke-VersionBump.ps1',
        'src/SemanticVersionBumper.psm1',
        'tests/SemanticVersionBumper.Tests.ps1'
    ) {
        Test-Path (Join-Path $script:RepoRoot $_) | Should -BeTrue
    }
}

Describe 'actionlint validation' {
    It 'passes actionlint with exit code 0' {
        $out = & actionlint $script:WorkflowPath 2>&1
        $code = $LASTEXITCODE
        if ($code -ne 0) { Write-Host ($out | Out-String) }
        $code | Should -Be 0
    }
}

Describe 'Pipeline execution via act' {
    BeforeAll {
        # Start a fresh results artifact for this run.
        Set-Content -Path $script:ResultFile -Value "act-result.txt - generated by tests/Workflow.Tests.ps1`n"
    }

    # Each case drives a different bump outcome and asserts the EXACT version the
    # pipeline must produce for that known input.
    $cases = @(
        @{ Name = 'minor-feat';   VersionFileName = 'VERSION';      VersionContent = '1.1.0'; Fixture = 'feat.log';     ExpectedVersion = '1.2.0'; ExpectedType = 'minor'; ExpectedBumped = 'True' }
        @{ Name = 'patch-fix';    VersionFileName = 'VERSION';      VersionContent = '2.4.1'; Fixture = 'fix.log';      ExpectedVersion = '2.4.2'; ExpectedType = 'patch'; ExpectedBumped = 'True' }
        @{ Name = 'major-break';  VersionFileName = 'VERSION';      VersionContent = '1.5.9'; Fixture = 'breaking.log'; ExpectedVersion = '2.0.0'; ExpectedType = 'major'; ExpectedBumped = 'True' }
        @{ Name = 'none-chore';   VersionFileName = 'VERSION';      VersionContent = '3.3.3'; Fixture = 'none.log';     ExpectedVersion = '3.3.3'; ExpectedType = 'none';  ExpectedBumped = 'False' }
    )

    It '<Name>: bumps <VersionContent> to exactly <ExpectedVersion> (<ExpectedType>)' -ForEach $cases {
        $run = script:Invoke-ActCase -VersionFileName $VersionFileName `
            -VersionContent $VersionContent -FixtureName $Fixture
        script:Add-ActResult -Name $Name -ExitCode $run.ExitCode -Output $run.Output

        # 1. act itself must succeed.
        $run.ExitCode | Should -Be 0 -Because "act push should exit 0 for case '$Name'"

        # 2. Every job must report success (test job + bump job).
        ([regex]::Matches($run.Output, 'Job succeeded')).Count |
            Should -BeGreaterOrEqual 2 -Because 'both the test and bump jobs must succeed'

        # 3. EXACT expected values produced by the pipeline.
        $run.Output | Should -Match "new_version=$([regex]::Escape($ExpectedVersion))"
        $run.Output | Should -Match "bump_type=$([regex]::Escape($ExpectedType))"
        $run.Output | Should -Match "bumped=$([regex]::Escape($ExpectedBumped))"
    }

    It 'wrote the act-result.txt artifact' {
        Test-Path $script:ResultFile | Should -BeTrue
        (Get-Content -Raw -Path $script:ResultFile).Length | Should -BeGreaterThan 0
    }
}
