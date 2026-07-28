# Test suite for SemanticVersionBumper using Pester
# TDD approach: failing tests written first, then implementation follows

BeforeAll {
    # Source the implementation module
    . $PSScriptRoot/SemanticVersionBumper.ps1
}

Describe "ParseVersion" {
    Context "Parse semantic version from package.json" {
        It "should parse version from valid package.json" {
            $testContent = @"
{
  "name": "test-app",
  "version": "1.2.3",
  "description": "Test"
}
"@
            $version = ParseVersion -JsonContent $testContent
            $version | Should -Be "1.2.3"
        }

        It "should handle version with pre-release tags" {
            $testContent = @"
{
  "version": "1.2.3-alpha.1"
}
"@
            $version = ParseVersion -JsonContent $testContent
            $version | Should -Be "1.2.3-alpha.1"
        }

        It "should throw on invalid JSON" {
            $testContent = "{ invalid json }"
            { ParseVersion -JsonContent $testContent } | Should -Throw
        }

        It "should throw when version field missing" {
            $testContent = @"
{
  "name": "test-app"
}
"@
            { ParseVersion -JsonContent $testContent } | Should -Throw
        }
    }
}

Describe "ConvertVersionToSemanticParts" {
    Context "Parse semantic version string into parts" {
        It "should parse major.minor.patch" {
            $parts = ConvertVersionToSemanticParts -Version "1.2.3"
            $parts.Major | Should -Be 1
            $parts.Minor | Should -Be 2
            $parts.Patch | Should -Be 3
        }

        It "should parse version with prerelease" {
            $parts = ConvertVersionToSemanticParts -Version "1.2.3-beta.1"
            $parts.Major | Should -Be 1
            $parts.Minor | Should -Be 2
            $parts.Patch | Should -Be 3
            $parts.PreRelease | Should -Be "beta.1"
        }

        It "should parse version with metadata" {
            $parts = ConvertVersionToSemanticParts -Version "1.2.3+build.123"
            $parts.Major | Should -Be 1
            $parts.Minor | Should -Be 2
            $parts.Patch | Should -Be 3
            $parts.Metadata | Should -Be "build.123"
        }

        It "should throw on invalid version format" {
            { ConvertVersionToSemanticParts -Version "invalid" } | Should -Throw
        }
    }
}

Describe "DetermineNextVersion" {
    Context "Calculate next version from commits" {
        It "should bump patch for fix commits" {
            $commits = @(
                @{ Type = "fix"; Subject = "Fix button alignment" }
            )
            $nextVersion = DetermineNextVersion -CurrentVersion "1.0.0" -Commits $commits
            $nextVersion | Should -Be "1.0.1"
        }

        It "should bump minor for feature commits" {
            $commits = @(
                @{ Type = "feat"; Subject = "Add user authentication" }
            )
            $nextVersion = DetermineNextVersion -CurrentVersion "1.0.0" -Commits $commits
            $nextVersion | Should -Be "1.1.0"
        }

        It "should bump major for breaking changes" {
            $commits = @(
                @{ Type = "feat"; Subject = "Remove legacy API"; Body = "BREAKING CHANGE: API changed" }
            )
            $nextVersion = DetermineNextVersion -CurrentVersion "1.0.0" -Commits $commits
            $nextVersion | Should -Be "2.0.0"
        }

        It "should prioritize major over minor over patch" {
            $commits = @(
                @{ Type = "fix"; Subject = "Fix bug" }
                @{ Type = "feat"; Subject = "Add feature" }
                @{ Type = "feat"; Subject = "Breaking change"; Body = "BREAKING CHANGE: removed endpoint" }
            )
            $nextVersion = DetermineNextVersion -CurrentVersion "1.0.0" -Commits $commits
            $nextVersion | Should -Be "2.0.0"
        }

        It "should handle no commits (no bump)" {
            $commits = @()
            $nextVersion = DetermineNextVersion -CurrentVersion "1.0.0" -Commits $commits
            $nextVersion | Should -Be "1.0.0"
        }

        It "should handle multiple fix and feature commits" {
            $commits = @(
                @{ Type = "fix"; Subject = "Fix bug 1" }
                @{ Type = "fix"; Subject = "Fix bug 2" }
                @{ Type = "feat"; Subject = "Add feature 1" }
            )
            $nextVersion = DetermineNextVersion -CurrentVersion "1.2.3" -Commits $commits
            $nextVersion | Should -Be "1.3.0"
        }
    }
}

Describe "ParseCommitMessage" {
    Context "Parse conventional commit messages" {
        It "should parse fix commit" {
            $commit = @"
fix: correct typo in button label

The button label had a typo that was confusing users.
"@
            $parsed = ParseCommitMessage -Message $commit
            $parsed.Type | Should -Be "fix"
            $parsed.Subject | Should -Be "correct typo in button label"
        }

        It "should parse feat commit" {
            $commit = @"
feat: add user authentication

Implements JWT-based authentication.
"@
            $parsed = ParseCommitMessage -Message $commit
            $parsed.Type | Should -Be "feat"
            $parsed.Subject | Should -Be "add user authentication"
        }

        It "should parse breaking change" {
            $commit = @"
feat: refactor authentication API

BREAKING CHANGE: /api/auth endpoint now requires POST instead of GET
"@
            $parsed = ParseCommitMessage -Message $commit
            $parsed.Type | Should -Be "feat"
            $parsed.Body | Should -Match "BREAKING CHANGE"
        }

        It "should handle commit without scope" {
            $commit = "fix: update dependencies"
            $parsed = ParseCommitMessage -Message $commit
            $parsed.Type | Should -Be "fix"
            $parsed.Subject | Should -Be "update dependencies"
            $parsed.Scope | Should -Be $null
        }

        It "should handle commit with scope" {
            $commit = "fix(auth): handle token expiration"
            $parsed = ParseCommitMessage -Message $commit
            $parsed.Type | Should -Be "fix"
            $parsed.Scope | Should -Be "auth"
            $parsed.Subject | Should -Be "handle token expiration"
        }

        It "should throw on invalid format" {
            $commit = "invalid commit message"
            { ParseCommitMessage -Message $commit } | Should -Throw
        }
    }
}

Describe "GenerateChangelog" {
    Context "Generate changelog from commits" {
        It "should generate changelog for fix commit" {
            $commits = @(
                @{ Type = "fix"; Scope = "ui"; Subject = "Fix button alignment" }
            )
            $changelog = GenerateChangelog -Commits $commits -Version "1.0.1"
            $changelog | Should -Match "1.0.1"
            $changelog | Should -Match "Bug Fixes"
            $changelog | Should -Match "button alignment"
        }

        It "should group commits by type" {
            $commits = @(
                @{ Type = "feat"; Scope = "auth"; Subject = "Add OAuth support" }
                @{ Type = "feat"; Scope = "api"; Subject = "Add rate limiting" }
                @{ Type = "fix"; Scope = "ui"; Subject = "Fix button styling" }
            )
            $changelog = GenerateChangelog -Commits $commits -Version "1.1.0"
            $changelog | Should -Match "Features"
            $changelog | Should -Match "Bug Fixes"
            $changelog | Should -Match "OAuth"
            $changelog | Should -Match "rate limiting"
            $changelog | Should -Match "button styling"
        }

        It "should format changelog entry with scope" {
            $commits = @(
                @{ Type = "feat"; Scope = "auth"; Subject = "Add session management" }
            )
            $changelog = GenerateChangelog -Commits $commits -Version "1.1.0"
            $changelog | Should -Match "auth"
        }
    }
}

Describe "UpdateVersionFile" {
    Context "Update version in package.json" {
        It "should update version in JSON" {
            $testJson = @"
{
  "name": "test-app",
  "version": "1.0.0",
  "description": "Test"
}
"@
            $updated = UpdateVersionFile -JsonContent $testJson -NewVersion "1.1.0"
            $updated | Should -Match '"version": "1.1.0"'
            $updated | Should -Match '"name": "test-app"'
        }

        It "should preserve JSON structure" {
            $testJson = @"
{
  "name": "test-app",
  "version": "1.0.0",
  "dependencies": {
    "lodash": "^4.17.0"
  }
}
"@
            $updated = UpdateVersionFile -JsonContent $testJson -NewVersion "2.0.0"
            $obj = $updated | ConvertFrom-Json
            $obj.version | Should -Be "2.0.0"
            $obj.dependencies.lodash | Should -Be "^4.17.0"
        }
    }
}

Describe "Integration Tests" {
    Context "Full workflow" {
        BeforeEach {
            # Create temp directory for test fixtures
            $script:TestDir = New-Item -ItemType Directory -Path ([System.IO.Path]::GetTempPath() + [guid]::NewGuid())
        }

        AfterEach {
            Remove-Item -Recurse -Force $script:TestDir -ErrorAction SilentlyContinue
        }

        It "should bump version and generate changelog for feature commits" {
            # Setup
            $packageJson = @"
{
  "name": "test-app",
  "version": "1.0.0"
}
"@
            $packageFile = Join-Path $script:TestDir "package.json"
            Set-Content -Path $packageFile -Value $packageJson

            $commits = @(
                @{ Type = "feat"; Scope = $null; Subject = "Add new feature" }
            )

            # Execute
            $newVersion = DetermineNextVersion -CurrentVersion "1.0.0" -Commits $commits
            $changelog = GenerateChangelog -Commits $commits -Version $newVersion

            # Assert
            $newVersion | Should -Be "1.1.0"
            $changelog | Should -Match "1.1.0"
            $changelog | Should -Match "new feature"
        }
    }
}
