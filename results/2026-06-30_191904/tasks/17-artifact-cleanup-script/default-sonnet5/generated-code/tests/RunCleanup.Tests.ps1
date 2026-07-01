# Pester tests for the run-cleanup.ps1 CLI wrapper: JSON config loading,
# error handling, and end-to-end summary output.

BeforeAll {
    $script:ScriptPath = "$PSScriptRoot/../src/run-cleanup.ps1"
    $script:TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("artifact-cleanup-tests-" + [System.Guid]::NewGuid())
    New-Item -ItemType Directory -Path $script:TempDir | Out-Null
}

AfterAll {
    Remove-Item -Path $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'run-cleanup.ps1 error handling' {

    It 'throws a meaningful error when the config file does not exist' {
        { & $script:ScriptPath -ConfigPath "$script:TempDir/does-not-exist.json" } |
            Should -Throw '*Config file not found*'
    }

    It 'throws a meaningful error when the config file is not valid JSON' {
        $badPath = Join-Path $script:TempDir 'bad.json'
        Set-Content -Path $badPath -Value '{ this is not json'

        { & $script:ScriptPath -ConfigPath $badPath } |
            Should -Throw '*Failed to parse JSON*'
    }

    It 'throws a meaningful error when required policy fields are missing' {
        $incompletePath = Join-Path $script:TempDir 'incomplete.json'
        Set-Content -Path $incompletePath -Value (@{
            now = '2026-07-01T00:00:00Z'
            artifacts = @()
        } | ConvertTo-Json)

        { & $script:ScriptPath -ConfigPath $incompletePath } |
            Should -Throw '*policy*'
    }
}

Describe 'run-cleanup.ps1 end-to-end' {

    It 'prints a summary matching the computed retention plan' {
        $configPath = Join-Path $script:TempDir 'valid.json'
        $config = @{
            now = '2026-07-01T00:00:00Z'
            dryRun = $false
            policy = @{
                maxAgeDays = 30
                maxTotalSizeBytes = 1000000000
                keepLatestN = 1
            }
            artifacts = @(
                @{ id='keep'; name='a'; sizeBytes=10000000; createdAt='2026-06-30T00:00:00Z'; workflowName='CI'; workflowRunId='r2' }
                @{ id='drop'; name='a'; sizeBytes=20000000; createdAt='2026-01-01T00:00:00Z'; workflowName='CI'; workflowRunId='r1' }
            )
        }
        Set-Content -Path $configPath -Value ($config | ConvertTo-Json -Depth 5)

        $output = & $script:ScriptPath -ConfigPath $configPath | Out-String

        $output | Should -Match 'Total artifacts scanned: 2'
        $output | Should -Match 'Artifacts retained: 1'
        $output | Should -Match 'Artifacts deleted: 1'
        $output | Should -Match 'Total space reclaimed: 20000000 bytes \(20\.00 MB\)'
        $output | Should -Not -Match 'DRY RUN'
    }
}
