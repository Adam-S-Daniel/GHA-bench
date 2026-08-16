# Test fixtures for semantic version bumper
# Defines test cases with initial state, inputs, and expected outputs

$testCases = @(
    @{
        Name          = "patch-bump-single-fix"
        Description   = "Bump patch version for a single fix commit"
        InitialJson   = @{ version = "1.2.3"; name = "test-app" }
        Commits       = @("fix: correct null reference exception")
        ExpectedVersion = "1.2.4"
        ExpectChangelog = $true
    }
    @{
        Name            = "minor-bump-single-feat"
        Description     = "Bump minor version for a single feature commit"
        InitialJson     = @{ version = "1.2.3"; name = "test-app" }
        Commits         = @("feat: add user authentication")
        ExpectedVersion = "1.3.0"
        ExpectChangelog = $true
    }
    @{
        Name            = "major-bump-breaking-change"
        Description     = "Bump major version for breaking change"
        InitialJson     = @{ version = "1.2.3"; name = "test-app" }
        Commits         = @("refactor: rewrite API handler`n`nBREAKING CHANGE: old API endpoints removed")
        ExpectedVersion = "2.0.0"
        ExpectChangelog = $true
    }
    @{
        Name            = "major-wins-over-minor-and-patch"
        Description     = "When multiple commit types exist, major takes priority"
        InitialJson     = @{ version = "1.0.0"; name = "test-app" }
        Commits         = @(
            "fix: small bug"
            "feat: new feature"
            "refactor: cleanup`n`nBREAKING CHANGE: removed deprecated method"
        )
        ExpectedVersion = "2.0.0"
        ExpectChangelog = $true
    }
    @{
        Name            = "minor-wins-over-patch"
        Description     = "When only minor and patch commits exist, minor takes priority"
        InitialJson     = @{ version = "1.0.0"; name = "test-app" }
        Commits         = @(
            "fix: bug 1"
            "fix: bug 2"
            "feat: new feature"
        )
        ExpectedVersion = "1.1.0"
        ExpectChangelog = $true
    }
    @{
        Name            = "multiple-patches"
        Description     = "Bump patch once for multiple fix commits"
        InitialJson     = @{ version = "1.0.0"; name = "test-app" }
        Commits         = @(
            "fix: memory leak"
            "fix: race condition"
        )
        ExpectedVersion = "1.0.1"
        ExpectChangelog = $true
    }
    @{
        Name            = "zero-version"
        Description     = "Handle 0.x.x versions correctly"
        InitialJson     = @{ version = "0.5.2"; name = "test-app" }
        Commits         = @("feat: initial feature set")
        ExpectedVersion = "0.6.0"
        ExpectChangelog = $true
    }
    @{
        Name            = "empty-commits-should-default-patch"
        Description     = "With no conventional commits, should bump patch"
        InitialJson     = @{ version = "1.0.0"; name = "test-app" }
        Commits         = @("random commit message")
        ExpectedVersion = "1.0.1"
        ExpectChangelog = $true
    }
)

# Export test cases
$testCases
