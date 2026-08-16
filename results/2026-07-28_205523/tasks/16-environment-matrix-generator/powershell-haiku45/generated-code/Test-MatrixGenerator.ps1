# Test-MatrixGenerator.ps1
# Pester tests for the GitHub Actions environment matrix generator
# Uses TDD: RED -> GREEN -> REFACTOR

BeforeAll {
    . $PSScriptRoot/New-GitHubActionsMatrix.ps1
}

Describe "New-GitHubActionsMatrix" {
    Context "Basic matrix generation" {
        It "should generate a matrix from simple OS list" {
            $config = @{
                os = @("ubuntu-latest", "windows-latest")
            }

            $matrix = New-GitHubActionsMatrix -Config $config

            $matrix | Should -Not -BeNullOrEmpty
            $matrix.include | Should -HaveCount 2
        }
    }

    Context "Multi-dimensional matrix" {
        It "should create cross product of os and versions" {
            $config = @{
                os = @("ubuntu-latest", "windows-latest")
                node_version = @("18.x", "20.x")
            }

            $matrix = New-GitHubActionsMatrix -Config $config

            # 2 OS × 2 versions = 4 combinations
            $matrix.include | Should -HaveCount 4
        }
    }

    Context "Include/Exclude rules" {
        It "should exclude specified combinations" {
            $config = @{
                os = @("ubuntu-latest", "windows-latest")
                node_version = @("18.x", "20.x")
                exclude = @(
                    @{ os = "windows-latest"; node_version = "18.x" }
                )
            }

            $matrix = New-GitHubActionsMatrix -Config $config

            # 4 combinations - 1 excluded = 3
            $matrix.include | Should -HaveCount 3

            # Verify the excluded combo is not present
            $excluded = $matrix.include | Where-Object { $_.os -eq "windows-latest" -and $_.node_version -eq "18.x" }
            $excluded | Should -BeNullOrEmpty
        }

        It "should include additional specific combinations" {
            $config = @{
                os = @("ubuntu-latest")
                node_version = @("18.x")
                include = @(
                    @{ os = "macos-latest"; node_version = "20.x"; special = $true }
                )
            }

            $matrix = New-GitHubActionsMatrix -Config $config

            # 1 base + 1 include = 2
            $matrix.include | Should -HaveCount 2

            # Verify the included special combo is present
            $special = $matrix.include | Where-Object { $_.os -eq "macos-latest" }
            $special | Should -Not -BeNullOrEmpty
            $special.special | Should -Be $true
        }
    }

    Context "Max parallel configuration" {
        It "should set max-parallel when specified" {
            $config = @{
                os = @("ubuntu-latest")
                max_parallel = 2
            }

            $matrix = New-GitHubActionsMatrix -Config $config

            $matrix."max-parallel" | Should -Be 2
        }
    }

    Context "Fail-fast configuration" {
        It "should set fail-fast when specified" {
            $config = @{
                os = @("ubuntu-latest")
                fail_fast = $false
            }

            $matrix = New-GitHubActionsMatrix -Config $config

            $matrix."fail-fast" | Should -Be $false
        }
    }

    Context "Matrix size validation" {
        It "should validate matrix doesn't exceed maximum size" {
            $config = @{
                os = @("ubuntu-latest", "windows-latest")
                node_version = @("18.x", "20.x")
                python_version = @("3.9", "3.10", "3.11")
                # Would be 2 * 2 * 3 = 12 combinations
                max_matrix_size = 10
            }

            { New-GitHubActionsMatrix -Config $config } | Should -Throw
        }

        It "should allow matrix within maximum size" {
            $config = @{
                os = @("ubuntu-latest", "windows-latest")
                node_version = @("18.x", "20.x")
                max_matrix_size = 10
            }

            $matrix = New-GitHubActionsMatrix -Config $config
            $matrix.include | Should -HaveCount 4
        }
    }

    Context "Output format" {
        It "should return valid JSON structure" {
            $config = @{
                os = @("ubuntu-latest")
                node_version = @("18.x")
            }

            $matrix = New-GitHubActionsMatrix -Config $config

            # Should be PSCustomObject that can be converted to JSON
            $json = $matrix | ConvertTo-Json
            $json | Should -Match '"include"'

            # Verify it can be parsed back
            $parsed = $json | ConvertFrom-Json
            $parsed | Should -Not -BeNullOrEmpty
        }
    }

    Context "Complex scenarios" {
        It "should handle three-dimensional matrix with exclusions and inclusions" {
            $config = @{
                os = @("ubuntu-latest", "windows-latest", "macos-latest")
                node_version = @("18.x", "20.x")
                experimental = @($false, $true)
                exclude = @(
                    @{ os = "windows-latest"; experimental = $true }
                    @{ os = "macos-latest"; node_version = "18.x" }
                )
                include = @(
                    @{ os = "macos-arm64"; node_version = "20.x"; experimental = $false }
                )
                max_parallel = 5
                fail_fast = $true
            }

            $matrix = New-GitHubActionsMatrix -Config $config

            # Base: 3 * 2 * 2 = 12
            # Excluded: 2 (windows-latest+True) + 2 (macos-latest+18.x) = 4
            # After exclusions: 12 - 4 = 8
            # Plus 1 included = 9
            $matrix.include | Should -HaveCount 9
            $matrix."max-parallel" | Should -Be 5
            $matrix."fail-fast" | Should -Be $true
        }
    }

    Context "Error handling" {
        It "should throw on missing required os configuration" {
            $config = @{
                node_version = @("18.x")
            }

            { New-GitHubActionsMatrix -Config $config } | Should -Throw
        }

        It "should throw when matrix exceeds size limit" {
            $config = @{
                os = @("ubuntu-latest", "windows-latest")
                node_version = @("18.x", "20.x")
                max_matrix_size = 2
            }

            { New-GitHubActionsMatrix -Config $config } | Should -Throw
        }
    }
}
