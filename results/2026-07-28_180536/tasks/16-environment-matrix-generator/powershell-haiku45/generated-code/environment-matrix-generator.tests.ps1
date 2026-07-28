# Pester test suite for environment-matrix-generator
# Uses red/green TDD: each test is written to fail first, then code is added to make it pass

Describe "Environment Matrix Generator" {

    BeforeAll {
        # Import the function under test
        . "$PSScriptRoot/environment-matrix-generator.ps1"
    }

    Context "Basic matrix generation" {

        It "should generate a basic matrix with single OS" {
            $config = @{
                operatingSystems = @("ubuntu-latest")
                maxParallel = 5
                failFast = $false
            }

            $result = New-EnvironmentMatrix -Config $config

            $result | Should -Not -BeNullOrEmpty
            $result.include | Should -HaveCount 1
            $result.include[0].os | Should -Be "ubuntu-latest"
        }

        It "should generate a matrix with multiple OSes" {
            $config = @{
                operatingSystems = @("ubuntu-latest", "windows-latest", "macos-latest")
                maxParallel = 5
                failFast = $false
            }

            $result = New-EnvironmentMatrix -Config $config

            $result.include | Should -HaveCount 3
            $result.include[0].os | Should -Be "ubuntu-latest"
            $result.include[1].os | Should -Be "windows-latest"
            $result.include[2].os | Should -Be "macos-latest"
        }
    }

    Context "Language version combinations" {

        It "should generate matrix with single language version" {
            $config = @{
                operatingSystems = @("ubuntu-latest")
                languageVersions = @("1.0", "2.0")
                maxParallel = 5
                failFast = $false
            }

            $result = New-EnvironmentMatrix -Config $config

            # Should create combination of OS x versions = 2 entries
            $result.include | Should -HaveCount 2
            $result.include[0].languageVersion | Should -Be "1.0"
            $result.include[1].languageVersion | Should -Be "2.0"
        }

        It "should generate matrix with OS and language version combinations" {
            $config = @{
                operatingSystems = @("ubuntu-latest", "windows-latest")
                languageVersions = @("1.0", "2.0")
                maxParallel = 5
                failFast = $false
            }

            $result = New-EnvironmentMatrix -Config $config

            # Should create all combinations: 2 OS x 2 versions = 4 entries
            $result.include | Should -HaveCount 4
        }
    }

    Context "Feature flags" {

        It "should generate matrix with feature flags" {
            $config = @{
                operatingSystems = @("ubuntu-latest")
                features = @("feature-a", "feature-b")
                maxParallel = 5
                failFast = $false
            }

            $result = New-EnvironmentMatrix -Config $config

            # Should create all combinations of flags: 2^2 = 4
            # Combinations: [], [a], [b], [a,b]
            $result.include | Should -HaveCount 4
            # Check that at least one entry has both features
            ($result.include | Where-Object { $_.features -contains "feature-a" -and $_.features -contains "feature-b" }) | Should -Not -BeNullOrEmpty
        }

        It "should support feature flag combinations correctly" {
            $config = @{
                operatingSystems = @("ubuntu-latest")
                features = @("debug", "release")
                maxParallel = 5
                failFast = $false
            }

            $result = New-EnvironmentMatrix -Config $config

            $result.include | Should -HaveCount 4  # 2^2: [none], [debug], [release], [debug,release]
        }
    }

    Context "Include and exclude rules" {

        It "should support include rules" {
            $config = @{
                operatingSystems = @("ubuntu-latest")
                languageVersions = @("1.0")
                include = @(
                    @{ os = "macos-latest"; languageVersion = "1.0"; special = $true }
                )
                maxParallel = 5
                failFast = $false
            }

            $result = New-EnvironmentMatrix -Config $config

            # Base matrix + 1 include = 2 total
            $result.include | Should -HaveCount 2
            $result.include[-1].os | Should -Be "macos-latest"
            $result.include[-1].special | Should -Be $true
        }

        It "should support exclude rules" {
            $config = @{
                operatingSystems = @("ubuntu-latest", "windows-latest", "macos-latest")
                languageVersions = @("1.0", "2.0")
                exclude = @(
                    @{ os = "windows-latest"; languageVersion = "1.0" }
                )
                maxParallel = 5
                failFast = $false
            }

            $result = New-EnvironmentMatrix -Config $config

            # 3 OS x 2 versions = 6, minus 1 excluded = 5
            $result.include | Should -HaveCount 5
            ($result.include | Where-Object { $_.os -eq "windows-latest" -and $_.languageVersion -eq "1.0" }) | Should -BeNullOrEmpty
        }
    }

    Context "Configuration options" {

        It "should set maxParallel when provided" {
            $config = @{
                operatingSystems = @("ubuntu-latest")
                maxParallel = 3
                failFast = $false
            }

            $result = New-EnvironmentMatrix -Config $config

            $result.maxParallel | Should -Be 3
        }

        It "should set failFast when provided" {
            $config = @{
                operatingSystems = @("ubuntu-latest")
                maxParallel = 5
                failFast = $true
            }

            $result = New-EnvironmentMatrix -Config $config

            $result.failFast | Should -Be $true
        }
    }

    Context "Matrix size validation" {

        It "should validate matrix doesn't exceed maxSize" {
            $config = @{
                operatingSystems = @("ubuntu-latest", "windows-latest", "macos-latest")
                languageVersions = @("1.0", "2.0")
                maxSize = 5  # Will be exceeded: 3 OS x 2 versions = 6
                maxParallel = 5
                failFast = $false
            }

            { New-EnvironmentMatrix -Config $config } | Should -Throw "*Matrix size*exceeds*"
        }

        It "should allow matrix within maxSize" {
            $config = @{
                operatingSystems = @("ubuntu-latest", "windows-latest")
                languageVersions = @("1.0")
                maxSize = 5
                maxParallel = 5
                failFast = $false
            }

            $result = New-EnvironmentMatrix -Config $config
            $result.include | Should -HaveCount 2
        }
    }

    Context "Output format" {

        It "should output valid JSON format" {
            $config = @{
                operatingSystems = @("ubuntu-latest")
                maxParallel = 5
                failFast = $false
            }

            $result = New-EnvironmentMatrix -Config $config
            $json = $result | ConvertTo-Json

            $json | Should -Not -BeNullOrEmpty
            { $json | ConvertFrom-Json } | Should -Not -Throw
        }

        It "should have include array in output" {
            $config = @{
                operatingSystems = @("ubuntu-latest")
                maxParallel = 5
                failFast = $false
            }

            $result = New-EnvironmentMatrix -Config $config

            $result.PSObject.Properties.Name | Should -Contain "include"
            $result.include | Should -Not -BeNullOrEmpty
        }
    }

    Context "Error handling" {

        It "should throw on missing operatingSystems" {
            $config = @{
                maxParallel = 5
                failFast = $false
            }

            { New-EnvironmentMatrix -Config $config } | Should -Throw "*operatingSystems*required*"
        }

        It "should throw on empty operatingSystems" {
            $config = @{
                operatingSystems = @()
                maxParallel = 5
                failFast = $false
            }

            { New-EnvironmentMatrix -Config $config } | Should -Throw "*cannot be empty*"
        }

        It "should throw on invalid config" {
            { New-EnvironmentMatrix -Config $null } | Should -Throw "*Config*required*"
        }
    }

    Context "Standalone script execution" {

        It "should execute as standalone script with JSON output" {
            $configJson = @{
                operatingSystems = @("ubuntu-latest")
                maxParallel = 5
                failFast = $false
            } | ConvertTo-Json

            # Simulate file-based config for standalone execution
            $tempConfigFile = New-TemporaryFile
            $configJson | Set-Content $tempConfigFile

            try {
                # This would be executed as: pwsh -File environment-matrix-generator.ps1 -ConfigPath config.json
                # But in the test, we're testing the function directly
                $result = New-EnvironmentMatrix -Config ([pscustomobject]($configJson | ConvertFrom-Json))
                $result | Should -Not -BeNullOrEmpty
            }
            finally {
                Remove-Item $tempConfigFile -Force
            }
        }
    }
}
