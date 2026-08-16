# Mock git commit log fixtures for testing
# These simulate real git commits for integration testing

function Get-MockCommits {
    <#
    .SYNOPSIS
        Return mock commit messages for test scenarios
    #>
    param([string]$Scenario = "mixed")

    switch ($Scenario) {
        "patch-only" {
            return @(
                @{ Type = "fix"; Scope = "ui"; Subject = "Fix button hover state"; Body = $null }
            )
        }
        "minor-feature" {
            return @(
                @{ Type = "feat"; Scope = "auth"; Subject = "Add OAuth provider support"; Body = $null }
            )
        }
        "major-breaking" {
            return @(
                @{ Type = "feat"; Scope = "api"; Subject = "Refactor REST API endpoints"; Body = "BREAKING CHANGE: /api/v1 endpoints removed in favor of /api/v2" }
            )
        }
        "mixed" {
            return @(
                @{ Type = "fix"; Scope = "ui"; Subject = "Fix button alignment in header" }
                @{ Type = "fix"; Scope = "db"; Subject = "Handle null values in migration" }
                @{ Type = "feat"; Scope = "auth"; Subject = "Add session timeout feature" }
                @{ Type = "feat"; Scope = "api"; Subject = "Add rate limiting middleware" }
            )
        }
        "complex-breaking" {
            return @(
                @{ Type = "fix"; Scope = "ui"; Subject = "Fix responsive layout on mobile" }
                @{ Type = "feat"; Scope = "auth"; Subject = "Implement MFA support"; Body = "BREAKING CHANGE: password-only auth removed" }
                @{ Type = "feat"; Scope = "api"; Subject = "Add GraphQL endpoint" }
            )
        }
        default {
            throw "Unknown scenario: $Scenario"
        }
    }
}

function ConvertCommitsToGitLog {
    <#
    .SYNOPSIS
        Convert commit objects to simulated git log format for reference
    #>
    param([object[]]$Commits)

    $logLines = @()
    foreach ($commit in $Commits) {
        $scope = if ($commit.Scope) { "($($commit.Scope))" } else { "" }
        $logLines += "$($commit.Type)$scope`: $($commit.Subject)"
        if ($commit.Body) {
            $logLines += ""
            $logLines += $commit.Body
        }
        $logLines += ""
    }

    return $logLines -join "`n"
}

