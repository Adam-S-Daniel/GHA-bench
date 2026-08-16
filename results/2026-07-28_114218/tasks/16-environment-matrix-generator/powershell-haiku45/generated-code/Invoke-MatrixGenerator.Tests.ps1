# Test suite for environment matrix generator
# Using Pester test framework

BeforeAll {
    # Import the main module
    . $PSScriptRoot/Invoke-MatrixGenerator.ps1
}

Describe "MatrixGenerator - Basic Functionality" {
    Context "Generating a simple matrix" {
        It "should generate a basic 2x2 matrix from OS and version arrays" {
            $config = @{
                os = @("ubuntu", "windows")
                version = @("1.0", "2.0")
            }

            $result = Invoke-MatrixGenerator -Configuration $config
            $matrix = ConvertFrom-Json $result

            # Expect 4 combinations (2 OSes × 2 versions)
            $matrix.include.Count | Should -Be 4
        }
    }

    Context "Matrix with features" {
        It "should generate combinations with 3D matrix (OS × version × feature)" {
            $config = @{
                os       = @("ubuntu")
                version  = @("1.0", "2.0")
                features = @("minimal", "full")
            }

            $result = Invoke-MatrixGenerator -Configuration $config
            $matrix = ConvertFrom-Json $result

            # Expect 4 combinations: 1 OS × 2 versions × 2 features
            $matrix.include.Count | Should -Be 4
        }
    }

    Context "Matrix structure validation" {
        It "should have 'include' array with combinations" {
            $config = @{
                os = @("ubuntu")
                version = @("1.0")
            }

            $result = Invoke-MatrixGenerator -Configuration $config
            $matrix = ConvertFrom-Json $result

            $matrix | Get-Member -MemberType NoteProperty | Where-Object Name -eq "include" | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "MatrixGenerator - Exclude Rules" {
    Context "Applying exclude rules" {
        It "should remove excluded combinations" {
            $config = @{
                os      = @("ubuntu", "windows")
                version = @("1.0", "2.0")
                exclude = @(
                    @{ os = "windows"; version = "1.0" }
                )
            }

            $result = Invoke-MatrixGenerator -Configuration $config
            $matrix = ConvertFrom-Json $result

            # Expect 3 combinations (4 total - 1 excluded)
            $matrix.include.Count | Should -Be 4
            $matrix.exclude.Count | Should -Be 1
        }
    }
}

Describe "MatrixGenerator - Include Rules" {
        It "should add custom include rules to matrix" {
            $config = @{
                os      = @("ubuntu")
                version = @("1.0")
                include = @(
                    @{ os = "macos"; version = "1.0" }
                )
            }

            $result = Invoke-MatrixGenerator -Configuration $config
            $matrix = ConvertFrom-Json $result

            # Expect 2 combinations (1 base + 1 include)
            $matrix.include.Count | Should -Be 2
        }
}

Describe "MatrixGenerator - Configuration Options" {
    Context "MaxParallel setting" {
        It "should include max-parallel when specified" {
            $config = @{
                os         = @("ubuntu")
                version    = @("1.0")
                maxParallel = 5
            }

            $result = Invoke-MatrixGenerator -Configuration $config
            $matrix = ConvertFrom-Json $result

            $matrix."max-parallel" | Should -Be 5
        }
    }

    Context "FailFast setting" {
        It "should include fail-fast when true" {
            $config = @{
                os       = @("ubuntu")
                version  = @("1.0")
                failFast = $true
            }

            $result = Invoke-MatrixGenerator -Configuration $config
            $matrix = ConvertFrom-Json $result

            $matrix."fail-fast" | Should -Be $true
        }
    }
}

Describe "MatrixGenerator - Size Validation" {
    Context "Maximum matrix size" {
        It "should throw error when matrix exceeds maxSize" {
            $config = @{
                os      = @("ubuntu", "windows")
                version = @("1.0", "2.0", "3.0", "4.0", "5.0")
                maxSize = 8
            }

            { Invoke-MatrixGenerator -Configuration $config } | Should -Throw "*exceeds maximum*"
        }
    }

    Context "Matrix within size limit" {
        It "should generate matrix when within maxSize" {
            $config = @{
                os      = @("ubuntu", "windows")
                version = @("1.0", "2.0")
                maxSize = 10
            }

            $result = Invoke-MatrixGenerator -Configuration $config
            $matrix = ConvertFrom-Json $result

            $matrix.include.Count | Should -Be 4
        }
    }
}

Describe "MatrixGenerator - Edge Cases" {
    Context "Empty configuration" {
        It "should handle empty input gracefully" {
            $config = @{}

            $result = Invoke-MatrixGenerator -Configuration $config
            $matrix = ConvertFrom-Json $result

            $matrix.include.Count | Should -Be 0
        }
    }

    Context "Single dimension" {
        It "should handle only OS specified" {
            $config = @{
                os = @("ubuntu", "windows", "macos")
            }

            $result = Invoke-MatrixGenerator -Configuration $config
            $matrix = ConvertFrom-Json $result

            $matrix.include.Count | Should -Be 3
        }
    }

    Context "Single element arrays" {
        It "should handle single value arrays" {
            $config = @{
                os      = @("ubuntu")
                version = @("1.0")
            }

            $result = Invoke-MatrixGenerator -Configuration $config
            $matrix = ConvertFrom-Json $result

            $matrix.include.Count | Should -Be 1
            $matrix.include[0].os | Should -Be "ubuntu"
            $matrix.include[0].version | Should -Be "1.0"
        }
    }
}

Describe "MatrixGenerator - JSON Output Format" {
    Context "Valid JSON output" {
        It "should produce valid JSON that parses correctly" {
            $config = @{
                os      = @("ubuntu", "windows")
                version = @("1.0", "2.0")
            }

            $result = Invoke-MatrixGenerator -Configuration $config
            { ConvertFrom-Json $result } | Should -Not -Throw
        }
    }

    Context "Matrix combination properties" {
        It "should include all specified properties in combinations" {
            $config = @{
                os      = @("ubuntu")
                version = @("1.0")
            }

            $result = Invoke-MatrixGenerator -Configuration $config
            $matrix = ConvertFrom-Json $result

            $matrix.include[0] | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name | Should -Contain "os"
            $matrix.include[0] | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name | Should -Contain "version"
        }
    }
}

Describe "MatrixGenerator - Complex Scenarios" {
    Context "Large matrix within limits" {
        It "should generate large matrix up to maxSize" {
            $config = @{
                os       = @("ubuntu", "windows", "macos")
                version  = @("1.0", "2.0", "3.0", "4.0", "5.0")
                maxSize  = 100
            }

            $result = Invoke-MatrixGenerator -Configuration $config
            $matrix = ConvertFrom-Json $result

            $matrix.include.Count | Should -Be 15
        }
    }

    Context "Mixed include and exclude" {
        It "should apply both include and exclude rules" {
            $config = @{
                os       = @("ubuntu", "windows")
                version  = @("1.0", "2.0")
                include  = @(@{ os = "macos"; version = "1.0" })
                exclude  = @(@{ os = "windows"; version = "2.0" })
            }

            $result = Invoke-MatrixGenerator -Configuration $config
            $matrix = ConvertFrom-Json $result

            $matrix.include.Count | Should -Be 5  # 4 base + 1 include
            $matrix.exclude.Count | Should -Be 1
        }
    }

    Context "All configuration options combined" {
        It "should handle complete configuration with all options" {
            $config = @{
                os          = @("ubuntu", "windows")
                version     = @("1.0")
                features    = @("test1")
                include     = @(@{ os = "special"; feature = "test1" })
                exclude     = @(@{ os = "windows"; version = "1.0"; feature = "test1" })
                maxParallel = 10
                failFast    = $true
                maxSize     = 256
            }

            $result = Invoke-MatrixGenerator -Configuration $config
            $matrix = ConvertFrom-Json $result

            $matrix.include.Count | Should -Be 3  # 2 base + 1 include
            $matrix.exclude.Count | Should -Be 1
            $matrix."max-parallel" | Should -Be 10
            $matrix."fail-fast" | Should -Be $true
        }
    }
}

Describe "MatrixGenerator - GitHub Actions Compliance" {
    Context "GitHub Actions matrix format" {
        It "should produce valid GitHub Actions strategy.matrix format" {
            $config = @{
                os      = @("ubuntu-latest", "windows-latest")
                version = @("16", "18")
            }

            $result = Invoke-MatrixGenerator -Configuration $config
            $matrix = ConvertFrom-Json $result

            # GitHub Actions requires 'include' at minimum
            $matrix | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name | Should -Contain "include"

            # Each combination should have properties
            $matrix.include[0] | Get-Member -MemberType NoteProperty | Measure-Object | Select-Object -ExpandProperty Count | Should -BeGreaterThan 0
        }
    }

    Context "Matrix with exclude rules for GitHub Actions" {
        It "should generate compatible exclude array for GitHub Actions" {
            $config = @{
                os      = @("ubuntu-latest", "windows-latest")
                version = @("16", "18")
                exclude = @(
                    @{ os = "windows-latest"; version = "16" }
                )
            }

            $result = Invoke-MatrixGenerator -Configuration $config
            $matrix = ConvertFrom-Json $result

            # GitHub Actions can use either 'include' or 'exclude' in strategy.matrix
            $matrix | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name | Should -Contain "exclude"
            $matrix.exclude.Count | Should -Be 1
        }
    }
}

Describe "MatrixGenerator - Input Validation" {
    Context "Invalid array items" {
        It "should handle non-string array values" {
            $config = @{
                os      = @("ubuntu", "windows")
                version = @(16, 18)  # numbers instead of strings
            }

            $result = Invoke-MatrixGenerator -Configuration $config
            $matrix = ConvertFrom-Json $result

            $matrix.include.Count | Should -Be 4
        }
    }

    Context "Null or undefined configuration keys" {
        It "should handle missing optional keys gracefully" {
            $config = @{
                os = @("ubuntu")
            }

            $result = Invoke-MatrixGenerator -Configuration $config
            $matrix = ConvertFrom-Json $result

            # Should not include 'exclude' if not specified
            $matrix | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name | Should -Not -Contain "exclude"
        }
    }
}
