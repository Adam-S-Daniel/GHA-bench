<#
Test fixtures for semantic version bumper
Provides mock commit logs for various scenarios
#>

# Test case 1: Patch bump (fix commits)
$testCase1 = @{
    name    = "patch-bump"
    commits = @(
        "fix: correct null reference exception",
        "fix: handle edge case in parsing"
    )
    expected = @{
        oldVersion = "1.0.0"
        newVersion = "1.0.1"
        bumpType   = "patch"
    }
}

# Test case 2: Minor bump (feature commits)
$testCase2 = @{
    name    = "minor-bump"
    commits = @(
        "feat: add authentication module",
        "feat: implement caching layer",
        "fix: correct timezone handling"
    )
    expected = @{
        oldVersion = "1.0.0"
        newVersion = "1.1.0"
        bumpType   = "minor"
    }
}

# Test case 3: Major bump (breaking changes)
$testCase3 = @{
    name    = "major-bump"
    commits = @(
        "feat: redesign API interface`n`nBREAKING CHANGE: removed legacy endpoints",
        "fix: update error handling"
    )
    expected = @{
        oldVersion = "1.0.0"
        newVersion = "2.0.0"
        bumpType   = "major"
    }
}

# Test case 4: Mixed commits with breaking change takes priority
$testCase4 = @{
    name    = "mixed-with-breaking"
    commits = @(
        "fix: small fix",
        "feat: new feature",
        "feat!: removed old API`n`nBREAKING CHANGE: API v1 no longer supported"
    )
    expected = @{
        oldVersion = "2.1.0"
        newVersion = "3.0.0"
        bumpType   = "major"
    }
}

# Test case 5: No commits (default to patch)
$testCase5 = @{
    name    = "no-commits"
    commits = @()
    expected = @{
        oldVersion = "1.5.3"
        newVersion = "1.5.4"
        bumpType   = "patch"
    }
}

# Test case 6: Complex version with many features
$testCase6 = @{
    name    = "many-features"
    commits = @(
        "feat(auth): add OAuth2 support",
        "feat(db): implement connection pooling",
        "feat(api): add rate limiting",
        "fix(auth): handle token refresh",
        "docs: update README"
    )
    expected = @{
        oldVersion = "0.5.0"
        newVersion = "0.6.0"
        bumpType   = "minor"
    }
}

$testCases = @($testCase1, $testCase2, $testCase3, $testCase4, $testCase5, $testCase6)

$testCases
