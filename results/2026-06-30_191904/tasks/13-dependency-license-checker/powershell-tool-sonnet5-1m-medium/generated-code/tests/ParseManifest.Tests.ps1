# Red/Green TDD - Step 1: parsing dependency manifests.
# This test file is written FIRST, before src/LicenseChecker.psm1 exists.
# Running it now must FAIL (module not found / function not defined).

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'src' 'LicenseChecker.psm1'
    Import-Module $modulePath -Force
}

Describe 'Get-DependenciesFromManifest' {

    Context 'package.json manifests' {
        BeforeAll {
            $fixture = Join-Path $PSScriptRoot '..' 'fixtures' 'package.json'
        }

        It 'extracts dependency names and versions from dependencies' {
            $deps = Get-DependenciesFromManifest -Path $fixture
            $deps | Where-Object { $_.Name -eq 'lodash' } | Select-Object -ExpandProperty Version | Should -Be '4.17.21'
        }

        It 'extracts dependency names and versions from devDependencies' {
            $deps = Get-DependenciesFromManifest -Path $fixture
            $deps | Where-Object { $_.Name -eq 'jest' } | Select-Object -ExpandProperty Version | Should -Be '29.0.0'
        }

        It 'returns the correct total count of dependencies' {
            $deps = Get-DependenciesFromManifest -Path $fixture
            $deps.Count | Should -Be 4
        }
    }

    Context 'requirements.txt manifests' {
        BeforeAll {
            $fixture = Join-Path $PSScriptRoot '..' 'fixtures' 'requirements.txt'
        }

        It 'extracts dependency names and pinned versions' {
            $deps = Get-DependenciesFromManifest -Path $fixture
            $deps | Where-Object { $_.Name -eq 'requests' } | Select-Object -ExpandProperty Version | Should -Be '2.31.0'
        }

        It 'ignores comments and blank lines' {
            $deps = Get-DependenciesFromManifest -Path $fixture
            $deps.Count | Should -Be 3
        }
    }

    Context 'error handling' {
        It 'throws a meaningful error when the file does not exist' {
            { Get-DependenciesFromManifest -Path 'does-not-exist.json' } | Should -Throw '*not found*'
        }

        It 'throws a meaningful error for an unsupported manifest type' {
            $badFixture = Join-Path $PSScriptRoot '..' 'fixtures' 'unsupported.txt'
            { Get-DependenciesFromManifest -Path $badFixture } | Should -Throw '*Unsupported*'
        }
    }
}
