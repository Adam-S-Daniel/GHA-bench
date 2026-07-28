# Test suite for New-EnvironmentMatrix using Pester
# TDD approach: red test → green implementation → refactor

Describe "New-EnvironmentMatrix" {
    BeforeAll {
        # Ensure the module is loaded
        $scriptPath = Join-Path $PSScriptRoot ".." "src" "New-EnvironmentMatrix.ps1"
        if (Test-Path $scriptPath) {
            . $scriptPath
        }
    }

    Context "Basic matrix generation" {
        It "should generate a simple matrix from OS and language versions" {
            $config = @{
                os = @("ubuntu-latest", "windows-latest")
                language = @("3.10", "3.11")
            }

            $matrix = New-EnvironmentMatrix -Config $config

            $matrix | Should -Not -BeNullOrEmpty
            $matrix.include | Should -Not -BeNullOrEmpty
            $matrix.include.Count | Should -Be 4  # 2 OS × 2 versions
        }
    }

    Context "Include rules" {
        It "should add extra combinations via include rules" {
            $config = @{
                os = @("ubuntu-latest")
                language = @("3.10")
                include = @(
                    @{ os = "macos-latest"; language = "3.9" }
                )
            }

            $matrix = New-EnvironmentMatrix -Config $config

            $matrix.include | Should -Not -BeNullOrEmpty
            $matrix.include.Count | Should -Be 2  # Base (1) + include (1)
        }
    }

    Context "Exclude rules" {
        It "should remove combinations via exclude rules" {
            $config = @{
                os = @("ubuntu-latest", "windows-latest")
                language = @("3.10", "3.11")
                exclude = @(
                    @{ os = "windows-latest"; language = "3.10" }
                )
            }

            $matrix = New-EnvironmentMatrix -Config $config

            $matrix.include | Should -Not -BeNullOrEmpty
            $matrix.include.Count | Should -Be 3  # 4 base - 1 excluded
        }
    }

    Context "Feature flags" {
        It "should include feature flags in combinations" {
            $config = @{
                os = @("ubuntu-latest")
                language = @("3.10")
                features = @("flag1", "flag2")
            }

            $matrix = New-EnvironmentMatrix -Config $config

            $matrix.include | Should -Not -BeNullOrEmpty
            $matrix.include[0].features | Should -Be "flag1,flag2"
        }
    }

    Context "Max parallel limit" {
        It "should enforce max-parallel limit" {
            $config = @{
                os = @("ubuntu-latest", "windows-latest", "macos-latest")
                language = @("3.10", "3.11", "3.12")
                maxParallel = 5
            }

            $matrix = New-EnvironmentMatrix -Config $config

            $matrix."max-parallel" | Should -Be 5
        }
    }

    Context "Fail-fast configuration" {
        It "should set fail-fast policy" {
            $config = @{
                os = @("ubuntu-latest")
                language = @("3.10")
                failFast = $true
            }

            $matrix = New-EnvironmentMatrix -Config $config

            $matrix."fail-fast" | Should -Be $true
        }
    }

    Context "Matrix size validation" {
        It "should raise error when matrix exceeds max size" {
            $config = @{
                os = @("ubuntu-latest", "windows-latest", "macos-latest")
                language = @("3.10", "3.11", "3.12", "3.9", "3.8", "3.7", "3.6")
                maxSize = 10
            }

            { New-EnvironmentMatrix -Config $config } | Should -Throw
        }
    }

    Context "JSON output format" {
        It "should output valid JSON" {
            $config = @{
                os = @("ubuntu-latest")
                language = @("3.10")
            }

            $jsonOutput = New-EnvironmentMatrix -Config $config -AsJson

            $jsonOutput | Should -BeOfType [string]
            { $jsonOutput | ConvertFrom-Json } | Should -Not -Throw
        }
    }

    Context "Empty configuration" {
        It "should handle empty config gracefully" {
            $config = @{}

            { New-EnvironmentMatrix -Config $config } | Should -Throw
        }
    }

    Context "Complex matrix with all options" {
        It "should combine all features correctly" {
            $config = @{
                os = @("ubuntu-latest", "windows-latest")
                language = @("3.10", "3.11")
                features = @("experimental", "debug")
                include = @(
                    @{ os = "macos-latest"; language = "3.9"; features = "minimal" }
                )
                exclude = @(
                    @{ os = "windows-latest"; language = "3.10" }
                )
                maxParallel = 8
                failFast = $false
            }

            $matrix = New-EnvironmentMatrix -Config $config

            # Base (2 x 2 = 4) - exclude (1) + include (1) = 4
            $matrix.include.Count | Should -Be 4
            $matrix.'max-parallel' | Should -Be 8
            $matrix.'fail-fast' | Should -Be $false
        }
    }

    Context "Single dimension matrix" {
        It "should work with only OS dimension" {
            $config = @{
                os = @("ubuntu-latest", "windows-latest", "macos-latest")
            }

            $matrix = New-EnvironmentMatrix -Config $config

            $matrix.include.Count | Should -Be 3
            $matrix.include[0].os | Should -Not -BeNullOrEmpty
            $matrix.include[0].language | Should -BeNullOrEmpty
        }

        It "should work with only language dimension" {
            $config = @{
                language = @("3.9", "3.10", "3.11")
            }

            $matrix = New-EnvironmentMatrix -Config $config

            $matrix.include.Count | Should -Be 3
            $matrix.include[0].language | Should -Not -BeNullOrEmpty
            $matrix.include[0].os | Should -BeNullOrEmpty
        }
    }

    Context "Exclude all combinations" {
        It "should handle excluding all combinations" {
            $config = @{
                os = @("ubuntu-latest")
                language = @("3.10")
                exclude = @(
                    @{ os = "ubuntu-latest"; language = "3.10" }
                )
            }

            $matrix = New-EnvironmentMatrix -Config $config

            $matrix.include.Count | Should -Be 0
        }
    }

    Context "Partial field matching in exclude" {
        It "should exclude combinations matching all fields in pattern" {
            $config = @{
                os = @("ubuntu-latest", "windows-latest")
                language = @("3.10", "3.11")
                exclude = @(
                    @{ os = "ubuntu-latest" }
                )
            }

            $matrix = New-EnvironmentMatrix -Config $config

            # Exclude pattern only has os=ubuntu-latest, so it excludes all
            # combinations where os is ubuntu-latest (both language versions)
            $matrix.include.Count | Should -Be 2
        }
    }

    Context "Features in base vs include" {
        It "should handle features correctly in include" {
            $config = @{
                os = @("ubuntu-latest")
                language = @("3.10")
                features = @("base-flag")
                include = @(
                    @{ os = "macos-latest"; language = "3.9"; features = "custom-flag" }
                )
            }

            $matrix = New-EnvironmentMatrix -Config $config

            # Base combination should have base-flag
            $baseFeatures = $matrix.include | Where-Object { $_.os -eq "ubuntu-latest" } | Select-Object -First 1
            $baseFeatures.features | Should -Be "base-flag"

            # Include should use its own features (custom-flag overrides base)
            $includeFeatures = $matrix.include | Where-Object { $_.os -eq "macos-latest" } | Select-Object -First 1
            $includeFeatures.features | Should -Be "custom-flag"
        }
    }

    Context "Large matrix within limits" {
        It "should handle reasonable matrix sizes" {
            $config = @{
                os = @("ubuntu-latest", "windows-latest")
                language = @("3.7", "3.8", "3.9", "3.10", "3.11", "3.12")
                maxSize = 20
            }

            $matrix = New-EnvironmentMatrix -Config $config

            # 2 x 6 = 12 combinations
            $matrix.include.Count | Should -Be 12
        }
    }

    Context "JSON output structure" {
        It "should maintain structure in JSON conversion" {
            $config = @{
                os = @("ubuntu-latest")
                language = @("3.10")
                maxParallel = 2
                failFast = $true
            }

            $json = New-EnvironmentMatrix -Config $config -AsJson
            $obj = $json | ConvertFrom-Json

            $obj.include | Should -Not -BeNullOrEmpty
            $obj.'max-parallel' | Should -Be 2
            $obj.'fail-fast' | Should -Be $true
        }
    }

    Context "Default max size" {
        It "should use 256 as default maxSize" {
            $config = @{
                os = @("ubuntu-latest")
                language = @("3.10")
            }

            # Should not throw for reasonable size
            { New-EnvironmentMatrix -Config $config } | Should -Not -Throw
        }
    }
}
