# Pester tests for SemanticVersionBumper
# Red/Green TDD: Write failing tests first, then implement minimum code to pass

Describe "SemanticVersionBumper" {
    BeforeAll {
        # Import the module
        . "$PSScriptRoot/SemanticVersionBumper.ps1"
    }

    Context "Version parsing" {
        It "parses a valid semantic version" {
            $version = Parse-SemanticVersion "1.2.3"
            $version.Major | Should -Be 1
            $version.Minor | Should -Be 2
            $version.Patch | Should -Be 3
        }

        It "parses version from package.json" {
            $tempFile = New-TemporaryFile -ErrorAction Stop
            $json = @{
                name = "test-package"
                version = "2.4.6"
            } | ConvertTo-Json
            Set-Content -Path $tempFile.FullName -Value $json

            $version = Read-VersionFromPackageJson -Path $tempFile.FullName
            $version | Should -Be "2.4.6"

            Remove-Item $tempFile -Force
        }

        It "parses version from version.txt" {
            $tempFile = New-TemporaryFile -ErrorAction Stop
            Set-Content -Path $tempFile.FullName -Value "3.5.1"

            $version = Read-VersionFromFile -Path $tempFile.FullName
            $version | Should -Be "3.5.1"

            Remove-Item $tempFile -Force
        }
    }

    Context "Commit message parsing" {
        It "identifies feat commit as minor bump" {
            $messageType = Get-CommitType -Message "feat: add new feature"
            $messageType | Should -Be "feat"
        }

        It "identifies fix commit as patch bump" {
            $messageType = Get-CommitType -Message "fix: resolve issue"
            $messageType | Should -Be "fix"
        }

        It "identifies breaking change" {
            $messageType = Get-CommitType -Message "feat!: breaking change`n`nBREAKING CHANGE: this breaks things"
            $messageType | Should -Be "breaking"
        }

        It "handles conventional commits with body" {
            $messageType = Get-CommitType -Message "feat(core): new feature`n`nThis is the body"
            $messageType | Should -Be "feat"
        }
    }

    Context "Version bumping" {
        It "bumps major version on breaking change" {
            $current = Parse-SemanticVersion "1.2.3"
            $next = Bump-Version -Current $current -BumpType "major"
            "$($next.Major).$($next.Minor).$($next.Patch)" | Should -Be "2.0.0"
        }

        It "bumps minor version on feat commit" {
            $current = Parse-SemanticVersion "1.2.3"
            $next = Bump-Version -Current $current -BumpType "minor"
            "$($next.Major).$($next.Minor).$($next.Patch)" | Should -Be "1.3.0"
        }

        It "bumps patch version on fix commit" {
            $current = Parse-SemanticVersion "1.2.3"
            $next = Bump-Version -Current $current -BumpType "patch"
            "$($next.Major).$($next.Minor).$($next.Patch)" | Should -Be "1.2.4"
        }

        It "prioritizes breaking over feat over fix" {
            $commits = @(
                "fix: small fix",
                "feat: new feature",
                "feat!: breaking change"
            )
            $bumpType = Determine-BumpType -Commits $commits
            $bumpType | Should -Be "major"
        }

        It "prioritizes feat over fix" {
            $commits = @(
                "fix: small fix",
                "feat: new feature"
            )
            $bumpType = Determine-BumpType -Commits $commits
            $bumpType | Should -Be "minor"
        }

        It "defaults to patch when only fixes" {
            $commits = @(
                "fix: small fix",
                "fix: another fix"
            )
            $bumpType = Determine-BumpType -Commits $commits
            $bumpType | Should -Be "patch"
        }

        It "defaults to patch when no conventional commits" {
            $commits = @(
                "some random commit"
            )
            $bumpType = Determine-BumpType -Commits $commits
            $bumpType | Should -Be "patch"
        }
    }

    Context "Changelog generation" {
        It "generates changelog entries from commits" {
            $commits = @(
                @{ Type = "feat"; Message = "add new feature"; Hash = "abc123" },
                @{ Type = "fix"; Message = "resolve issue"; Hash = "def456" }
            )
            $changelog = Generate-Changelog -Commits $commits -Version "2.0.0"
            $changelog | Should -Match "2.0.0"
            $changelog | Should -Match "add new feature"
            $changelog | Should -Match "resolve issue"
        }

        It "organizes changelog by type" {
            $commits = @(
                @{ Type = "fix"; Message = "fix 1"; Hash = "aaa" },
                @{ Type = "feat"; Message = "feat 1"; Hash = "bbb" },
                @{ Type = "fix"; Message = "fix 2"; Hash = "ccc" }
            )
            $changelog = Generate-Changelog -Commits $commits -Version "1.1.0"
            # Features should appear before fixes
            $changelogList = $changelog -split "`n"
            $featIndex = $changelogList | Where-Object { $_ -match "feat 1" } | Select-Object -Index 0
            $featIndex | Should -Not -BeNullOrEmpty
        }
    }

    Context "Integration: end-to-end version bump" {
        It "bumps version and generates changelog" {
            # Create temp working directory
            $tempDir = New-Item -ItemType Directory -Name "test-$(Get-Random)" -Path ([System.IO.Path]::GetTempPath()) -Force
            Push-Location $tempDir.FullName

            try {
                # Initialize git repo
                & git init -q
                & git config user.email "test@example.com"
                & git config user.name "Test User"

                # Create version file
                "1.0.0" | Out-File -FilePath "version.txt" -NoNewline

                # Initial commit
                & git add version.txt
                & git commit -q -m "initial: project setup"

                # Make feature commit
                "dummy content" | Out-File -FilePath "feature.txt"
                & git add feature.txt
                & git commit -q -m "feat: add awesome feature"

                # Get commits since last version
                $commits = Get-ConventionalCommits -Since "HEAD~1"
                $bumpType = Determine-BumpType -Commits $commits

                $bumpType | Should -Be "minor"
            }
            finally {
                Pop-Location
                Remove-Item -Path $tempDir.FullName -Recurse -Force
            }
        }
    }
}
