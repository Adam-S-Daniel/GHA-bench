Describe "EnvironmentMatrixGenerator" {
    BeforeAll {
        # Load the script being tested within Pester's scope
        $srcPath = Join-Path $PSScriptRoot ".." "src" "EnvironmentMatrixGenerator.ps1"
        $srcPath = Resolve-Path $srcPath
        . $srcPath
    }
    Context "Basic matrix generation" {
        It "generates a matrix from simple configuration" {
            $config = @{
                os           = @("ubuntu-latest", "windows-latest")
                'node-version' = @("18", "20")
            }

            $result = New-EnvironmentMatrix -Configuration $config

            # Should create a cartesian product: 2 OS * 2 versions = 4 combinations
            $result.include | Measure-Object | Select-Object -ExpandProperty Count | Should -Be 4
        }
    }

    Context "Matrix with include rules" {
        It "adds extra combinations from include list" {
            $config = @{
                os       = @("ubuntu-latest")
                version  = @("18")
                include  = @(
                    @{ os = "macos-latest"; version = "18" }
                )
            }

            $result = New-EnvironmentMatrix -Configuration $config

            # Base: 1 OS * 1 version = 1
            # Include: +1 = 2 total
            $result.include | Measure-Object | Select-Object -ExpandProperty Count | Should -Be 2
        }
    }

    Context "Matrix with exclude rules" {
        It "removes combinations from exclude list" {
            $config = @{
                os      = @("ubuntu-latest", "windows-latest")
                version = @("18", "20")
                exclude = @(
                    @{ os = "windows-latest"; version = "18" }
                )
            }

            $result = New-EnvironmentMatrix -Configuration $config

            # Base: 2 OS * 2 versions = 4
            # Exclude: -1 = 3 total
            $result.include | Measure-Object | Select-Object -ExpandProperty Count | Should -Be 3
        }
    }

    Context "Matrix validation" {
        It "enforces maximum matrix size" {
            $config = @{
                os      = @("ubuntu-latest", "windows-latest", "macos-latest")
                version = @("18", "20", "22")
                arch    = @("x64", "arm64")
                # 3 * 3 * 2 = 18 combinations
            }

            $result = New-EnvironmentMatrix -Configuration $config -MaxMatrixSize 10

            # Should throw error or indicate size exceeded
            $result.valid | Should -Be $false
            $result.error | Should -Match "exceeds maximum"
        }
    }

    Context "Matrix with max-parallel" {
        It "includes max-parallel in strategy" {
            $config = @{
                os = @("ubuntu-latest", "windows-latest")
                version = @("18", "20")
            }

            $result = New-EnvironmentMatrix -Configuration $config -MaxParallel 4

            $result.'max-parallel' | Should -Be 4
        }
    }

    Context "Matrix with fail-fast" {
        It "includes fail-fast in strategy" {
            $config = @{
                os = @("ubuntu-latest", "windows-latest")
            }

            $result = New-EnvironmentMatrix -Configuration $config -FailFast:$true

            $result.'fail-fast' | Should -Be $true
        }
    }

    Context "Output formatting" {
        It "outputs valid JSON" {
            $config = @{
                os = @("ubuntu-latest")
                version = @("18")
            }

            $result = New-EnvironmentMatrix -Configuration $config
            $json = $result | ConvertTo-Json

            # Should not throw
            { $json | ConvertFrom-Json } | Should -Not -Throw
        }
    }

    Context "Error handling" {
        It "returns error for invalid configuration" {
            $config = @{}

            $result = New-EnvironmentMatrix -Configuration $config

            $result.valid | Should -Be $false
            $result.error | Should -Match "empty|no dimensions"
        }
    }
}
