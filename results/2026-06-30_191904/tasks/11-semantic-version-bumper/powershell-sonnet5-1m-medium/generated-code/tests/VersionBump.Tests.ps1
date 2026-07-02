BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'scripts' 'VersionBumper.psm1'
    Import-Module $modulePath -Force
}

Describe 'Get-NextVersion' {
    It 'bumps the major version and resets minor/patch to 0' {
        Get-NextVersion -CurrentVersion '1.2.3' -BumpType 'major' | Should -Be '2.0.0'
    }

    It 'bumps the minor version and resets patch to 0' {
        Get-NextVersion -CurrentVersion '1.2.3' -BumpType 'minor' | Should -Be '1.3.0'
    }

    It 'bumps the patch version' {
        Get-NextVersion -CurrentVersion '1.2.3' -BumpType 'patch' | Should -Be '1.2.4'
    }

    It 'returns the current version unchanged when there is nothing to release' {
        Get-NextVersion -CurrentVersion '1.2.3' -BumpType 'none' | Should -Be '1.2.3'
    }

    It 'throws a meaningful error for a malformed current version' {
        { Get-NextVersion -CurrentVersion '1.2' -BumpType 'patch' } | Should -Throw '*version*'
    }

    It 'throws a meaningful error for an unrecognized bump type' {
        { Get-NextVersion -CurrentVersion '1.2.3' -BumpType 'sideways' } | Should -Throw
    }
}
