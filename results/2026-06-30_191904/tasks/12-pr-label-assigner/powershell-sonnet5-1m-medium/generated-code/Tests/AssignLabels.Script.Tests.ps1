# Pester tests for the Assign-Labels.ps1 CLI entrypoint.
# Written before the script existed (red), then implemented to pass (green).

BeforeAll {
    $script:ScriptPath = "$PSScriptRoot/../Assign-Labels.ps1"
    $script:ConfigPath = "$PSScriptRoot/../labels.config.json"
}

Describe 'Assign-Labels.ps1' {
    It 'exists at the expected path' {
        Test-Path -LiteralPath $script:ScriptPath | Should -BeTrue
    }

    It 'prints a sorted JSON array of labels for a mocked changed-files list' {
        $changedFiles = Join-Path $TestDrive 'changed-files.json'
        '["docs/readme.md", "src/api/users.js", "src/api/users.test.js"]' | Set-Content -LiteralPath $changedFiles

        $output = & $script:ScriptPath -ChangedFilesPath $changedFiles -ConfigPath $script:ConfigPath
        $json = $output | ConvertFrom-Json
        @($json) | Should -Be @('api', 'documentation', 'tests')
    }

    It 'prints an empty JSON array when no files match any rule' {
        $changedFiles = Join-Path $TestDrive 'changed-files-none.json'
        '["random.xyz"]' | Set-Content -LiteralPath $changedFiles

        $output = & $script:ScriptPath -ChangedFilesPath $changedFiles -ConfigPath $script:ConfigPath
        $json = $output | ConvertFrom-Json
        @($json).Count | Should -Be 0
    }

    It 'writes a "labels=" line to GITHUB_OUTPUT when the env var is set' {
        $changedFiles = Join-Path $TestDrive 'changed-files2.json'
        '["docs/readme.md"]' | Set-Content -LiteralPath $changedFiles
        $outputFile = Join-Path $TestDrive 'gh-output.txt'
        New-Item -ItemType File -Path $outputFile -Force | Out-Null

        $env:GITHUB_OUTPUT = $outputFile
        try {
            & $script:ScriptPath -ChangedFilesPath $changedFiles -ConfigPath $script:ConfigPath | Out-Null
        }
        finally {
            Remove-Item Env:GITHUB_OUTPUT -ErrorAction SilentlyContinue
        }

        $content = Get-Content -LiteralPath $outputFile -Raw
        $content | Should -Match 'labels='
        $content | Should -Match 'documentation'
    }

    It 'throws a meaningful error when the changed-files path does not exist' {
        { & $script:ScriptPath -ChangedFilesPath (Join-Path $TestDrive 'missing.json') -ConfigPath $script:ConfigPath } | Should -Throw '*not found*'
    }
}
