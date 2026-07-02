BeforeAll {
    . "$PSScriptRoot/New-EnvironmentMatrix.ps1"
}

Describe "New-EnvironmentMatrix" {
    Context "Basic matrix generation" {
        It "generates the full cartesian product of os/version/flags" {
            $config = @{ os = @("ubuntu-latest","windows-latest"); version = @("16","18"); flags = @("stable") }
            $result = New-EnvironmentMatrix -Config $config
            $result.matrix.include.Count | Should -Be 4
            @($result.matrix.include | Where-Object { $_.os -eq "ubuntu-latest" -and $_.version -eq "16" -and $_.flags -eq "stable" }).Count | Should -Be 1
        }
    }

    Context "Include rules" {
        It "adds specific combos via include" {
            $config = @{
                os = @("ubuntu-latest")
                version = @("16")
                flags = @("stable")
                include = @(@{ os = "macos-latest"; version = "20"; flags = "beta" })
            }
            $result = New-EnvironmentMatrix -Config $config
            $result.matrix.include.Count | Should -Be 2
            @($result.matrix.include | Where-Object { $_.os -eq "macos-latest" -and $_.version -eq "20" -and $_.flags -eq "beta" }).Count | Should -Be 1
        }
    }

    Context "Exclude rules" {
        It "removes combos matching exclude" {
            $config = @{
                os = @("ubuntu-latest","windows-latest")
                version = @("16","18")
                flags = @("stable")
                exclude = @(@{ os = "windows-latest"; version = "16" })
            }
            $result = New-EnvironmentMatrix -Config $config
            $result.matrix.include.Count | Should -Be 3
            @($result.matrix.include | Where-Object { $_.os -eq "windows-latest" -and $_.version -eq "16" }).Count | Should -Be 0
        }

        It "applies exclude before include, per fixture with-include-exclude" {
            $config = @{
                os = @("ubuntu-latest","windows-latest")
                version = @("16","18")
                flags = @("stable")
                include = @(@{ os = "macos-latest"; version = "20"; flags = "beta" })
                exclude = @(@{ os = "windows-latest"; version = "16" })
            }
            $result = New-EnvironmentMatrix -Config $config
            $result.matrix.include.Count | Should -Be 4
        }
    }

    Context "max-parallel and fail-fast" {
        It "outputs max-parallel field" {
            $config = @{ os = @("ubuntu-latest"); version = @("16"); flags = @("stable"); maxParallel = 4 }
            $result = New-EnvironmentMatrix -Config $config
            $result.'max-parallel' | Should -Be 4
        }

        It "outputs fail-fast field" {
            $config = @{ os = @("ubuntu-latest"); version = @("16"); flags = @("stable"); failFast = $false }
            $result = New-EnvironmentMatrix -Config $config
            $result.'fail-fast' | Should -Be $false
        }

        It "defaults fail-fast to true when not specified" {
            $config = @{ os = @("ubuntu-latest"); version = @("16"); flags = @("stable") }
            $result = New-EnvironmentMatrix -Config $config
            $result.'fail-fast' | Should -Be $true
        }
    }

    Context "max-size validation" {
        It "throws a meaningful error when matrix exceeds maxSize" {
            $config = @{
                os = @("ubuntu-latest","windows-latest","macos-latest")
                version = @("14","16","18","20")
                flags = @("stable","beta")
                maxSize = 10
            }
            { New-EnvironmentMatrix -Config $config } | Should -Throw "*exceeds*maximum*size*"
        }

        It "does not throw when matrix size is within maxSize" {
            $config = @{ os = @("ubuntu-latest"); version = @("16"); flags = @("stable"); maxSize = 5 }
            { New-EnvironmentMatrix -Config $config } | Should -Not -Throw
        }
    }

    Context "Malformed config error handling" {
        It "throws when config is missing required 'os' key" {
            $config = @{ version = @("16"); flags = @("stable") }
            { New-EnvironmentMatrix -Config $config } | Should -Throw "*os*"
        }

        It "throws when config is missing required 'version' key" {
            $config = @{ os = @("ubuntu-latest"); flags = @("stable") }
            { New-EnvironmentMatrix -Config $config } | Should -Throw "*version*"
        }

        It "throws a meaningful error for null config" {
            { New-EnvironmentMatrix -Config $null } | Should -Throw "*config*"
        }
    }

    Context "JSON output" {
        It "produces valid JSON via New-EnvironmentMatrixJson" {
            $config = @{ os = @("ubuntu-latest"); version = @("16"); flags = @("stable") }
            $json = New-EnvironmentMatrixJson -Config $config
            { $json | ConvertFrom-Json } | Should -Not -Throw
        }
    }
}
