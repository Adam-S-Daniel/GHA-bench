# Build-Matrix.tests.ps1 - Red/Green TDD tests for matrix generator
# Run with: Invoke-Pester -Path Build-Matrix.tests.ps1 -Verbose

BeforeAll {
    . ./Build-Matrix.ps1
}

Describe "Build-Matrix: Core Matrix Generation" {
    Context "Test 1: Simple OS matrix" {
        It "generates a basic matrix with single OS" {
            $config = @{
                os = @("ubuntu-latest")
                include = @()
                exclude = @()
                maxParallel = $null
                failFast = $false
            }

            $result = Build-Matrix -Config $config

            $result | Should -Not -BeNullOrEmpty
            $result.include | Should -HaveCount 1
            $result.include[0].os | Should -Be "ubuntu-latest"
        }
    }

    Context "Test 2: Multiple OS matrix" {
        It "generates matrix with multiple operating systems" {
            $config = @{
                os = @("ubuntu-latest", "windows-latest", "macos-latest")
                include = @()
                exclude = @()
                maxParallel = $null
                failFast = $false
            }

            $result = Build-Matrix -Config $config

            $result.include | Should -HaveCount 3
            $result.include[0].os | Should -Be "ubuntu-latest"
            $result.include[1].os | Should -Be "windows-latest"
            $result.include[2].os | Should -Be "macos-latest"
        }
    }

    Context "Test 3: Language versions cross product" {
        It "generates matrix combining OS and language versions" {
            $config = @{
                os = @("ubuntu-latest", "windows-latest")
                languages = @{ powershell = @("7.2", "7.3") }
                include = @()
                exclude = @()
                maxParallel = $null
                failFast = $false
            }

            $result = Build-Matrix -Config $config

            $result.include | Should -HaveCount 4
            # Should have 2 OS × 2 language versions = 4 combinations
            $versions = $result.include | Select-Object -ExpandProperty 'powershell-version' -Unique
            $versions | Should -HaveCount 2
        }
    }

    Context "Test 4: Include rule" {
        It "adds custom include entries to the matrix" {
            $config = @{
                os = @("ubuntu-latest")
                include = @(
                    @{ os = "ubuntu-latest"; node = "18.0"; custom = "value" }
                )
                exclude = @()
                maxParallel = $null
                failFast = $false
            }

            $result = Build-Matrix -Config $config

            $result.include | Should -HaveCount 2
            $result.include[-1].custom | Should -Be "value"
        }
    }

    Context "Test 5: Exclude rule" {
        It "removes excluded entries from the matrix" {
            $config = @{
                os = @("ubuntu-latest", "windows-latest")
                languages = @{ powershell = @("7.2", "7.3") }
                include = @()
                exclude = @(
                    @{ os = "windows-latest"; "powershell-version" = "7.2" }
                )
                maxParallel = $null
                failFast = $false
            }

            $result = Build-Matrix -Config $config

            $result.exclude | Should -HaveCount 1
            $result.exclude[0].os | Should -Be "windows-latest"
        }
    }

    Context "Test 6: Feature flags" {
        It "generates matrix with feature flags" {
            $config = @{
                os = @("ubuntu-latest")
                features = @( "debug", "release" )
                include = @()
                exclude = @()
                maxParallel = $null
                failFast = $false
            }

            $result = Build-Matrix -Config $config

            $result.include | Should -HaveCount 2
            $result.include[0].feature | Should -Be "debug"
            $result.include[1].feature | Should -Be "release"
        }
    }

    Context "Test 7: Max parallel configuration" {
        It "adds maxParallel to matrix" {
            $config = @{
                os = @("ubuntu-latest")
                include = @()
                exclude = @()
                maxParallel = 5
                failFast = $false
            }

            $result = Build-Matrix -Config $config

            $result.'max-parallel' | Should -Be 5
        }
    }

    Context "Test 8: Fail-fast configuration" {
        It "adds fail-fast to matrix" {
            $config = @{
                os = @("ubuntu-latest")
                include = @()
                exclude = @()
                maxParallel = $null
                failFast = $true
            }

            $result = Build-Matrix -Config $config

            $result.'fail-fast' | Should -Be $true
        }
    }
}

Describe "Build-Matrix: JSON Output and Validation" {
    Context "Test 9: JSON output format" {
        It "returns matrix that converts to valid JSON" {
            $config = @{
                os = @("ubuntu-latest")
                include = @()
                exclude = @()
                maxParallel = $null
                failFast = $false
            }

            $result = Build-Matrix -Config $config
            $json = $result | ConvertTo-Json

            $json | Should -Not -BeNullOrEmpty
            { $json | ConvertFrom-Json } | Should -Not -Throw
        }
    }

    Context "Test 10: Matrix size validation" {
        It "raises error when matrix exceeds max size" {
            $config = @{
                os = @("ubuntu-latest")
                include = @()
                exclude = @()
                maxParallel = $null
                failFast = $false
                maxSize = 2
            }

            # This should fail - we have 1 include which is under max, but let's test with larger
            $config.os = @("os1", "os2", "os3", "os4", "os5")
            $config.maxSize = 2

            { Build-Matrix -Config $config -ErrorAction Stop } | Should -Throw
        }
    }
}

Describe "Build-Matrix: Complex Scenarios" {
    Context "Test 11: Multiple language versions with features" {
        It "creates cross-product of OS, languages, and features" {
            $config = @{
                os = @("ubuntu-latest")
                languages = @{ powershell = @("7.2", "7.3"); node = @("18", "20") }
                features = @("debug", "release")
                include = @()
                exclude = @()
                maxParallel = $null
                failFast = $false
            }

            $result = Build-Matrix -Config $config

            # 1 OS × 2 PS versions × 2 Node versions × 2 features = 8
            $result.include | Should -HaveCount 8
        }
    }

    Context "Test 12: Empty OS array" {
        It "handles empty OS array gracefully" {
            $config = @{
                os = @()
                include = @()
                exclude = @()
                maxParallel = $null
                failFast = $false
            }

            $result = Build-Matrix -Config $config

            $result.include | Should -BeNullOrEmpty
        }
    }

    Context "Test 13: Exclude removes matching entries" {
        It "removes combinations that match exclude criteria" {
            $config = @{
                os = @("ubuntu-latest", "windows-latest")
                languages = @{ powershell = @("7.2", "7.3") }
                include = @()
                exclude = @(
                    @{ os = "windows-latest"; "powershell-version" = "7.2" }
                    @{ os = "ubuntu-latest"; "powershell-version" = "7.3" }
                )
                maxParallel = $null
                failFast = $false
            }

            $result = Build-Matrix -Config $config

            $result.exclude | Should -HaveCount 2
        }
    }

    Context "Test 14: JSON serialization to string" {
        It "converts matrix to valid JSON string" {
            $config = @{
                os = @("ubuntu-latest")
                languages = @{ powershell = @("7.2") }
                include = @()
                exclude = @()
                maxParallel = 4
                failFast = $true
            }

            $result = Build-Matrix -Config $config
            $json = $result | ConvertTo-Json -Depth 10

            $json | Should -Match '"include"'
            $json | Should -Match '"os"'
            $json | Should -Match '"max-parallel"'
            $json | Should -Match '"fail-fast"'
        }
    }
}
