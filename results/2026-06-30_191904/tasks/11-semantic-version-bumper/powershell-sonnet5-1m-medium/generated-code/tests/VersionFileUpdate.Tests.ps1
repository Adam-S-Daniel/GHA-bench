BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'scripts' 'VersionBumper.psm1'
    Import-Module $modulePath -Force
}

Describe 'Update-VersionFile' {
    BeforeEach {
        $script:tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid())
        New-Item -ItemType Directory -Path $tempDir | Out-Null
    }

    AfterEach {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'updates the version field in a version.json file, preserving other fields' {
        $target = Join-Path $tempDir 'version.json'
        Set-Content -Path $target -Value '{"version":"1.2.3","name":"widget"}'

        Update-VersionFile -Path $target -NewVersion '1.3.0'

        $result = Get-Content -Path $target -Raw | ConvertFrom-Json
        $result.version | Should -Be '1.3.0'
        $result.name | Should -Be 'widget'
    }

    It 'updates the version field in a package.json file, preserving other fields' {
        $target = Join-Path $tempDir 'package.json'
        Set-Content -Path $target -Value '{"name":"widget","version":"1.2.3","dependencies":{"lodash":"^4.0.0"}}'

        Update-VersionFile -Path $target -NewVersion '2.0.0'

        $result = Get-Content -Path $target -Raw | ConvertFrom-Json
        $result.version | Should -Be '2.0.0'
        $result.name | Should -Be 'widget'
        $result.dependencies.lodash | Should -Be '^4.0.0'
    }

    It 'throws a meaningful error when the file does not exist' {
        { Update-VersionFile -Path (Join-Path $tempDir 'missing.json') -NewVersion '1.0.0' } |
            Should -Throw '*not found*'
    }
}
