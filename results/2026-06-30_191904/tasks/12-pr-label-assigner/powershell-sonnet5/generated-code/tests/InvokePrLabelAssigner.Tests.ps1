<#
    Integration tests for the Invoke-PrLabelAssigner.ps1 CI entry point.
    These run the script exactly the way the GitHub Actions workflow does
    (as a separate pwsh process against fixture files), so they exercise
    argument parsing, output formatting, GITHUB_OUTPUT/GITHUB_STEP_SUMMARY
    handling, and error propagation together.
#>

BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '..' 'Invoke-PrLabelAssigner.ps1'
    $script:RepoRoot = Join-Path $PSScriptRoot '..'
}

Describe 'Invoke-PrLabelAssigner.ps1' {
    Context 'happy path' {
        BeforeAll {
            $script:WorkDir = Join-Path $TestDrive 'happy-path'
            New-Item -ItemType Directory -Path $script:WorkDir -Force | Out-Null

            $script:FixturePath = Join-Path $script:WorkDir 'changed-files.txt'
            Set-Content -Path $script:FixturePath -Value @('docs/readme.md', 'src/api/handler.test.ts')

            $script:OutputPath = Join-Path $script:WorkDir 'github-output.txt'
            $script:SummaryPath = Join-Path $script:WorkDir 'github-summary.md'
            New-Item -ItemType File -Path $script:OutputPath -Force | Out-Null
            New-Item -ItemType File -Path $script:SummaryPath -Force | Out-Null

            $env:GITHUB_OUTPUT = $script:OutputPath
            $env:GITHUB_STEP_SUMMARY = $script:SummaryPath

            $script:StdOut = & pwsh -NoLogo -NoProfile -File $script:ScriptPath `
                -RulesPath (Join-Path $script:RepoRoot 'rules.json') `
                -FixturePath $script:FixturePath 2>&1
            $script:ExitCode = $LASTEXITCODE
        }

        AfterAll {
            Remove-Item Env:\GITHUB_OUTPUT -ErrorAction SilentlyContinue
            Remove-Item Env:\GITHUB_STEP_SUMMARY -ErrorAction SilentlyContinue
        }

        It 'exits with code 0' {
            $script:ExitCode | Should -Be 0
        }

        It 'prints the exact final label line' {
            $script:StdOut | Should -Contain 'FINAL_LABELS=api,documentation,tests'
        }

        It 'writes the labels to GITHUB_OUTPUT' {
            Get-Content -Path $script:OutputPath -Raw | Should -Match 'labels=api,documentation,tests'
        }

        It 'writes a job summary that lists each label' {
            $summary = Get-Content -Path $script:SummaryPath -Raw
            $summary | Should -Match '## PR Label Assignment'
            $summary | Should -Match '`api`'
            $summary | Should -Match '`documentation`'
            $summary | Should -Match '`tests`'
        }
    }

    Context 'error handling' {
        It 'exits non-zero with a meaningful message when the rules file is missing' {
            $missingRulesPath = Join-Path $TestDrive 'does-not-exist.json'
            $fixturePath = Join-Path $TestDrive 'changed-files-err.txt'
            Set-Content -Path $fixturePath -Value 'docs/readme.md'

            $stdErr = & pwsh -NoLogo -NoProfile -File $script:ScriptPath `
                -RulesPath $missingRulesPath `
                -FixturePath $fixturePath 2>&1
            $exitCode = $LASTEXITCODE

            $exitCode | Should -Not -Be 0
            ($stdErr | Out-String) | Should -Match 'not found'
        }

        It 'exits non-zero when neither a fixture file nor a BaseRef can supply changed files' {
            $rulesPath = Join-Path $script:RepoRoot 'rules.json'
            $missingFixturePath = Join-Path $TestDrive 'no-such-fixture.txt'

            $stdErr = & pwsh -NoLogo -NoProfile -File $script:ScriptPath `
                -RulesPath $rulesPath `
                -FixturePath $missingFixturePath 2>&1
            $exitCode = $LASTEXITCODE

            $exitCode | Should -Not -Be 0
            ($stdErr | Out-String) | Should -Match 'changed files'
        }
    }
}
