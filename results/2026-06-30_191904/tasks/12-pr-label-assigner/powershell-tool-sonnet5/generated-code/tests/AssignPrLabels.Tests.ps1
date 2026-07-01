# Pester tests for the Assign-PrLabels.ps1 CLI entry point, the script the
# GitHub Actions workflow actually invokes. Written before the script
# existed (red/green TDD) to pin down its contract: stdout format,
# $GITHUB_OUTPUT / $GITHUB_STEP_SUMMARY integration, and error handling.

BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '..' 'Assign-PrLabels.ps1'
    $script:RulesPath = Join-Path $PSScriptRoot '..' 'label-rules.json'
    $script:FixturesDir = Join-Path $PSScriptRoot '..' 'fixtures'
}

Describe 'Assign-PrLabels.ps1' {
    It 'prints the exact final label set for the docs-only fixture' {
        $changedFiles = Join-Path $script:FixturesDir 'case1-docs.json'
        $output = & $script:ScriptPath -ChangedFilesPath $changedFiles -RulesPath $script:RulesPath | Out-String
        $output | Should -Match 'Final labels: documentation'
    }

    It 'prints the exact final label set for the api-and-tests fixture' {
        $changedFiles = Join-Path $script:FixturesDir 'case2-api-and-tests.json'
        $output = & $script:ScriptPath -ChangedFilesPath $changedFiles -RulesPath $script:RulesPath | Out-String
        $output | Should -Match 'Final labels: api, source, tests'
    }

    It 'prints the exact final label set for the priority-conflict fixture' {
        $changedFiles = Join-Path $script:FixturesDir 'case3-priority-conflict.json'
        $output = & $script:ScriptPath -ChangedFilesPath $changedFiles -RulesPath $script:RulesPath | Out-String
        $output | Should -Match 'Final labels: api, documentation'
    }

    It 'throws a meaningful error when the changed-files fixture is missing' {
        $missing = Join-Path $script:FixturesDir 'does-not-exist.json'
        { & $script:ScriptPath -ChangedFilesPath $missing -RulesPath $script:RulesPath } | Should -Throw '*not found*'
    }

    It 'writes a labels= line to $GITHUB_OUTPUT when it is set' {
        $changedFiles = Join-Path $script:FixturesDir 'case1-docs.json'
        $outputFile = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid())
        New-Item -ItemType File -Path $outputFile -Force | Out-Null
        try {
            $env:GITHUB_OUTPUT = $outputFile
            & $script:ScriptPath -ChangedFilesPath $changedFiles -RulesPath $script:RulesPath | Out-Null
            (Get-Content -Path $outputFile -Raw) | Should -Match 'labels=documentation'
        }
        finally {
            Remove-Item Env:\GITHUB_OUTPUT -ErrorAction SilentlyContinue
            Remove-Item -Path $outputFile -Force -ErrorAction SilentlyContinue
        }
    }
}
