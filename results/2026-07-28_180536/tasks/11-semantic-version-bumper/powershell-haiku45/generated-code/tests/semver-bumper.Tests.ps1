BeforeAll {
    . $PSScriptRoot/../src/semver-bumper.ps1
}

Describe "Get-CurrentVersion" {
    Context "Reading version from package.json" {
        It "should parse version from valid package.json" {
            # TEST 1: Parse version from package.json
            $testJson = @{
                version = "1.0.0"
            } | ConvertTo-Json

            $tempFile = New-TemporaryFile
            $testJson | Set-Content -Path $tempFile

            try {
                $version = Get-CurrentVersion -FilePath $tempFile
                $version | Should -Be "1.0.0"
            } finally {
                Remove-Item $tempFile -Force
            }
        }
    }
}

Describe "Get-NextVersion" {
    Context "Bumping patch version for fix commits" {
        It "should bump patch version for 'fix:' commit" {
            # TEST 2: Parse conventional commit and bump patch
            $currentVersion = "1.2.3"
            $commitMessages = @("fix: resolve null reference issue")

            $nextVersion = Get-NextVersion -CurrentVersion $currentVersion -CommitMessages $commitMessages
            $nextVersion | Should -Be "1.2.4"
        }
    }

    Context "Bumping minor version for feature commits" {
        It "should bump minor version for 'feat:' commit" {
            # TEST 3: Bump minor for feature
            $currentVersion = "1.2.3"
            $commitMessages = @("feat: add new authentication method")

            $nextVersion = Get-NextVersion -CurrentVersion $currentVersion -CommitMessages $commitMessages
            $nextVersion | Should -Be "1.3.0"
        }
    }

    Context "Bumping major version for breaking changes" {
        It "should bump major version for 'BREAKING CHANGE:' commit" {
            # TEST 4: Bump major for breaking change
            $currentVersion = "1.2.3"
            $commitMessages = @("refactor: change API interface`n`nBREAKING CHANGE: old interface removed")

            $nextVersion = Get-NextVersion -CurrentVersion $currentVersion -CommitMessages $commitMessages
            $nextVersion | Should -Be "2.0.0"
        }
    }

    Context "Handling multiple commits" {
        It "should determine highest priority bump from multiple commits" {
            # TEST 5: Multiple commits - breaking takes priority
            $currentVersion = "1.0.0"
            $commitMessages = @(
                "fix: small bug",
                "feat: new feature",
                "refactor: cleanup`n`nBREAKING CHANGE: removed deprecated API"
            )

            $nextVersion = Get-NextVersion -CurrentVersion $currentVersion -CommitMessages $commitMessages
            $nextVersion | Should -Be "2.0.0"
        }
    }
}

Describe "Update-VersionFile" {
    Context "Writing new version to package.json" {
        It "should update version in package.json" {
            # TEST 6: Update version in file
            $testJson = @{
                name = "test-app"
                version = "1.0.0"
                description = "test"
            } | ConvertTo-Json

            $tempFile = New-TemporaryFile
            $testJson | Set-Content -Path $tempFile

            try {
                Update-VersionFile -FilePath $tempFile -NewVersion "1.1.0"

                $updated = Get-Content -Path $tempFile | ConvertFrom-Json
                $updated.version | Should -Be "1.1.0"
            } finally {
                Remove-Item $tempFile -Force
            }
        }
    }
}

Describe "Generate-ChangelogEntry" {
    Context "Creating changelog from commits" {
        It "should generate changelog entry from commits" {
            # TEST 7: Generate changelog
            $commitMessages = @(
                "feat: add user registration",
                "fix: correct password validation"
            )
            $version = "1.1.0"

            $changelog = Generate-ChangelogEntry -Version $version -CommitMessages $commitMessages

            $changelog | Should -Match "1.1.0"
            $changelog | Should -Match "add user registration"
            $changelog | Should -Match "correct password validation"
        }
    }
}

Describe "Integration Tests with Test Fixtures" {
    BeforeEach {
        $script:testCases = & $PSScriptRoot/../fixtures/test-cases.ps1
    }

    Context "Running through test fixture scenarios" {
        It "handles patch bump for fix commits" {
            $testCase = $script:testCases | Where-Object { $_.Name -eq "patch-bump-single-fix" }

            $tempFile = New-TemporaryFile
            $testCase.InitialJson | ConvertTo-Json | Set-Content -Path $tempFile

            try {
                $nextVersion = Get-NextVersion -CurrentVersion $testCase.InitialJson.version -CommitMessages $testCase.Commits
                $nextVersion | Should -Be $testCase.ExpectedVersion

                Update-VersionFile -FilePath $tempFile -NewVersion $nextVersion
                $updated = Get-Content -Path $tempFile | ConvertFrom-Json
                $updated.version | Should -Be $testCase.ExpectedVersion
            } finally {
                Remove-Item $tempFile -Force
            }
        }

        It "handles major bump for breaking changes" {
            $testCase = $script:testCases | Where-Object { $_.Name -eq "major-bump-breaking-change" }

            $nextVersion = Get-NextVersion -CurrentVersion $testCase.InitialJson.version -CommitMessages $testCase.Commits
            $nextVersion | Should -Be $testCase.ExpectedVersion
        }

        It "prioritizes major over minor and patch" {
            $testCase = $script:testCases | Where-Object { $_.Name -eq "major-wins-over-minor-and-patch" }

            $nextVersion = Get-NextVersion -CurrentVersion $testCase.InitialJson.version -CommitMessages $testCase.Commits
            $nextVersion | Should -Be $testCase.ExpectedVersion
        }

        It "prioritizes minor over patch" {
            $testCase = $script:testCases | Where-Object { $_.Name -eq "minor-wins-over-patch" }

            $nextVersion = Get-NextVersion -CurrentVersion $testCase.InitialJson.version -CommitMessages $testCase.Commits
            $nextVersion | Should -Be $testCase.ExpectedVersion
        }

        It "handles multiple patches as single bump" {
            $testCase = $script:testCases | Where-Object { $_.Name -eq "multiple-patches" }

            $nextVersion = Get-NextVersion -CurrentVersion $testCase.InitialJson.version -CommitMessages $testCase.Commits
            $nextVersion | Should -Be $testCase.ExpectedVersion
        }

        It "handles pre-1.0 versions correctly" {
            $testCase = $script:testCases | Where-Object { $_.Name -eq "zero-version" }

            $nextVersion = Get-NextVersion -CurrentVersion $testCase.InitialJson.version -CommitMessages $testCase.Commits
            $nextVersion | Should -Be $testCase.ExpectedVersion
        }
    }
}
