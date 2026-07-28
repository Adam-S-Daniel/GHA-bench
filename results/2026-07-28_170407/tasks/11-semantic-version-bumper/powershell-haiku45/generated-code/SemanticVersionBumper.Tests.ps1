BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot "SemanticVersionBumper.ps1"
    if (Test-Path $ModulePath) {
        . $ModulePath
    }
}

Describe "Version Parsing" {
    It "parses a valid semantic version string" {
        $version = Parse-Version "1.2.3"
        $version.Major | Should -Be 1
        $version.Minor | Should -Be 2
        $version.Patch | Should -Be 3
    }

    It "parses a semantic version with leading 'v'" {
        $version = Parse-Version "v1.2.3"
        $version.Major | Should -Be 1
        $version.Minor | Should -Be 2
        $version.Patch | Should -Be 3
    }

    It "throws on invalid version format" {
        { Parse-Version "invalid" } | Should -Throw
    }
}

Describe "Commit Type Detection" {
    It "detects 'feat' as minor bump" {
        $type = Get-CommitType "feat: add new feature"
        $type | Should -Be "minor"
    }

    It "detects 'fix' as patch bump" {
        $type = Get-CommitType "fix: resolve bug"
        $type | Should -Be "patch"
    }

    It "detects breaking change in footer as major bump" {
        $type = Get-CommitType @"
feat: add new feature

BREAKING CHANGE: API has changed
"@
        $type | Should -Be "major"
    }

    It "detects breaking change in title as major bump" {
        $type = Get-CommitType "feat!: breaking feature"
        $type | Should -Be "major"
    }

    It "treats unknown types as patch" {
        $type = Get-CommitType "chore: update deps"
        $type | Should -Be "patch"
    }
}

Describe "Version Bumping" {
    It "bumps patch for fix commits" {
        $version = [PSCustomObject]@{ Major = 1; Minor = 2; Patch = 3 }
        $new = Bump-Version $version "patch"
        $new.Major | Should -Be 1
        $new.Minor | Should -Be 2
        $new.Patch | Should -Be 4
    }

    It "bumps minor for feat commits and resets patch" {
        $version = [PSCustomObject]@{ Major = 1; Minor = 2; Patch = 3 }
        $new = Bump-Version $version "minor"
        $new.Major | Should -Be 1
        $new.Minor | Should -Be 3
        $new.Patch | Should -Be 0
    }

    It "bumps major for breaking commits and resets minor and patch" {
        $version = [PSCustomObject]@{ Major = 1; Minor = 2; Patch = 3 }
        $new = Bump-Version $version "major"
        $new.Major | Should -Be 2
        $new.Minor | Should -Be 0
        $new.Patch | Should -Be 0
    }
}

Describe "Changelog Generation" {
    It "generates changelog entry from commits" {
        $commits = @(
            [PSCustomObject]@{ Type = "feat"; Message = "add authentication"; Hash = "abc1234" }
            [PSCustomObject]@{ Type = "fix"; Message = "resolve login bug"; Hash = "def5678" }
        )
        $changelog = Build-Changelog $commits "2.0.0"
        $changelog | Should -Match "2.0.0"
        $changelog | Should -Match "add authentication"
        $changelog | Should -Match "resolve login bug"
    }

    It "groups commits by type in changelog" {
        $commits = @(
            [PSCustomObject]@{ Type = "feat"; Message = "feature 1"; Hash = "abc" }
            [PSCustomObject]@{ Type = "feat"; Message = "feature 2"; Hash = "def" }
            [PSCustomObject]@{ Type = "fix"; Message = "fix 1"; Hash = "ghi" }
        )
        $changelog = Build-Changelog $commits "2.0.0"
        $changelog | Should -Match "Features"
        $changelog | Should -Match "Fixes"
    }
}

Describe "Mock Commit Fixtures" {
    It "creates realistic mock commit logs" {
        $commits = New-MockCommitLog -Count 5
        $commits | Should -HaveCount 5
        $commits[0].Type | Should -Not -BeNullOrEmpty
        $commits[0].Message | Should -Not -BeNullOrEmpty
        $commits[0].Hash | Should -Not -BeNullOrEmpty
    }

    It "mock commits include various types" {
        $commits = New-MockCommitLog -Count 20
        $types = $commits.Type | Select-Object -Unique
        $types | Should -Contain "feat"
        $types | Should -Contain "fix"
    }

    It "mock commits can include breaking changes" {
        $commits = New-MockCommitLog -Count 20 -IncludeBreaking $true
        $hasBreaking = $commits | Where-Object { $_.Message -match "BREAKING" } | Measure-Object | Select-Object -ExpandProperty Count
        $hasBreaking | Should -BeGreaterThan 0
    }
}

Describe "Full Integration" {
    It "processes version.json file" {
        $testFile = New-Item -Path "TestDrive:\version.json" -ItemType File -Force -Value '{"version":"1.0.0"}'
        $newVersion = Process-VersionFile -Path $testFile.FullName -CommitLog @(
            [PSCustomObject]@{ Type = "feat"; Message = "feat: test feature"; Hash = "abc" }
        )
        $newVersion | Should -Be "1.1.0"
    }

    It "returns appropriate version for major bump" {
        $testFile = New-Item -Path "TestDrive:\version.json" -ItemType File -Force -Value '{"version":"1.0.0"}'
        $newVersion = Process-VersionFile -Path $testFile.FullName -CommitLog @(
            [PSCustomObject]@{ Type = "feat"; Message = "test!: breaking"; Hash = "abc" }
        )
        $newVersion | Should -Be "2.0.0"
    }
}
