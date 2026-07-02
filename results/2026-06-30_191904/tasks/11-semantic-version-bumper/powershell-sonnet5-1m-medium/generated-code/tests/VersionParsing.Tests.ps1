# RED: first failing test — Get-CurrentVersion does not exist yet.
BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'scripts' 'VersionBumper.psm1'
    Import-Module $modulePath -Force
}

Describe 'Get-CurrentVersion' {
    It 'reads the version string from a version.json fixture' {
        $fixture = Join-Path $PSScriptRoot 'fixtures' 'version.json'
        $version = Get-CurrentVersion -Path $fixture
        $version | Should -Be '1.2.3'
    }

    It 'reads the version string from a package.json fixture' {
        $fixture = Join-Path $PSScriptRoot 'fixtures' 'package.json'
        $version = Get-CurrentVersion -Path $fixture
        $version | Should -Be '2.0.1'
    }

    It 'throws a meaningful error when the file does not exist' {
        { Get-CurrentVersion -Path (Join-Path $PSScriptRoot 'fixtures' 'does-not-exist.json') } |
            Should -Throw '*not found*'
    }

    It 'throws a meaningful error when no version field is present' {
        $fixture = Join-Path $PSScriptRoot 'fixtures' 'no-version.json'
        { Get-CurrentVersion -Path $fixture } | Should -Throw '*version*'
    }
}
