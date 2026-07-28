# Test suite for semantic version bumper using Pester

BeforeAll {
    # Import the module/functions to test
    . $PSScriptRoot/version-bumper.ps1
}

Describe "Parse-SemanticVersion" {
    It "parses a valid semantic version string" {
        $version = Parse-SemanticVersion "1.2.3"
        $version.Major | Should -Be 1
        $version.Minor | Should -Be 2
        $version.Patch | Should -Be 3
    }

    It "parses version with leading 'v'" {
        $version = Parse-SemanticVersion "v2.0.0"
        $version.Major | Should -Be 2
        $version.Minor | Should -Be 0
        $version.Patch | Should -Be 0
    }

    It "throws error for invalid version" {
        { Parse-SemanticVersion "invalid" } | Should -Throw
    }
}

Describe "Get-NextVersion" {
    It "bumps patch version for fix commits" {
        $current = [PSCustomObject]@{ Major = 1; Minor = 2; Patch = 3 }
        $next = Get-NextVersion -CurrentVersion $current -CommitType "fix"
        $next.Major | Should -Be 1
        $next.Minor | Should -Be 2
        $next.Patch | Should -Be 4
    }

    It "bumps minor version for feature commits" {
        $current = [PSCustomObject]@{ Major = 1; Minor = 2; Patch = 3 }
        $next = Get-NextVersion -CurrentVersion $current -CommitType "feat"
        $next.Major | Should -Be 1
        $next.Minor | Should -Be 3
        $next.Patch | Should -Be 0
    }

    It "bumps major version for breaking changes" {
        $current = [PSCustomObject]@{ Major = 1; Minor = 2; Patch = 3 }
        $next = Get-NextVersion -CurrentVersion $current -CommitType "breaking"
        $next.Major | Should -Be 2
        $next.Minor | Should -Be 0
        $next.Patch | Should -Be 0
    }
}

Describe "Format-Version" {
    It "formats version object as string" {
        $version = [PSCustomObject]@{ Major = 1; Minor = 2; Patch = 3 }
        $formatted = Format-Version $version
        $formatted | Should -Be "1.2.3"
    }
}

Describe "Parse-ConventionalCommits" {
    It "identifies feat commits as minor bump" {
        $commits = @(
            "feat: add new feature"
        )
        $type = Parse-ConventionalCommits -CommitMessages $commits
        $type | Should -Be "feat"
    }

    It "identifies fix commits as patch bump" {
        $commits = @(
            "fix: correct bug"
        )
        $type = Parse-ConventionalCommits -CommitMessages $commits
        $type | Should -Be "fix"
    }

    It "identifies breaking changes as major bump" {
        $commits = @(
            "feat: new feature`n`nBREAKING CHANGE: removes old API"
        )
        $type = Parse-ConventionalCommits -CommitMessages $commits
        $type | Should -Be "breaking"
    }

    It "prioritizes breaking > feat > fix" {
        $commits = @(
            "fix: small bug",
            "feat: new feature",
            "BREAKING CHANGE: removes API"
        )
        $type = Parse-ConventionalCommits -CommitMessages $commits
        $type | Should -Be "breaking"
    }
}

Describe "Generate-ChangelogEntry" {
    It "generates changelog entry from commits" {
        $commits = @(
            "feat: add authentication module",
            "fix: correct timezone handling"
        )
        $entry = Generate-ChangelogEntry -CommitMessages $commits -Version "1.3.0"
        $entry | Should -Match "1.3.0"
        $entry | Should -Match "feat"
        $entry | Should -Match "fix"
    }
}

Describe "Update-PackageJsonVersion" {
    It "updates version in package.json" {
        $tempDir = [System.IO.Path]::GetTempPath()
        $testDir = Join-Path $tempDir "pester-test-$(Get-Random)"
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null

        $packageJson = @{
            name = "test-package"
            version = "1.0.0"
            description = "Test package"
        } | ConvertTo-Json

        $filePath = Join-Path $testDir "package.json"
        Set-Content -Path $filePath -Value $packageJson

        Update-PackageJsonVersion -FilePath $filePath -NewVersion "1.1.0"

        $updated = Get-Content $filePath -Raw | ConvertFrom-Json
        $updated.version | Should -Be "1.1.0"

        Remove-Item -Path $testDir -Recurse -Force
    }
}

Describe "Get-GitCommitsSince" {
    It "retrieves commit messages from git" {
        # This test is light since it depends on git state
        # We'll just verify the function doesn't error on a real repo
        { Get-GitCommitsSince -Since "HEAD~10" } | Should -Not -Throw
    }
}

Describe "Invoke-SemanticVersionBump" {
    It "bumps version and generates changelog" {
        $tempDir = [System.IO.Path]::GetTempPath()
        $testDir = Join-Path $tempDir "pester-bump-$(Get-Random)"
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null

        $packageJson = @{
            name = "test-pkg"
            version = "1.0.0"
        } | ConvertTo-Json

        $filePath = Join-Path $testDir "package.json"
        Set-Content -Path $filePath -Value $packageJson

        $commits = @("feat: new feature", "fix: bug fix")

        $result = Invoke-SemanticVersionBump `
            -PackageJsonPath $filePath `
            -CommitMessages $commits `
            -GenerateChangelog:$false

        $result.NewVersion | Should -Be "1.1.0"

        $updated = Get-Content $filePath -Raw | ConvertFrom-Json
        $updated.version | Should -Be "1.1.0"

        Remove-Item -Path $testDir -Recurse -Force
    }
}
