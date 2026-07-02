# Pester tests for the PR Label Assigner script.
# Red/Green TDD: each Describe/It below was written before the corresponding
# implementation existed in src/LabelAssigner.ps1.

BeforeAll {
    . "$PSScriptRoot/../src/LabelAssigner.ps1"
}

Describe "Get-PrLabels - basic glob matching" {

    It "assigns 'documentation' label to files under docs/**" {
        $rules = @(
            @{ Pattern = "docs/**"; Label = "documentation"; Priority = 1 }
        )
        $files = @("docs/readme.md", "docs/guide/setup.md")

        $result = Get-PrLabels -ChangedFiles $files -Rules $rules

        $result | Should -Contain "documentation"
    }

    It "returns no labels when no rule matches any file" {
        $rules = @(
            @{ Pattern = "docs/**"; Label = "documentation"; Priority = 1 }
        )
        $files = @("src/main.ps1")

        $result = Get-PrLabels -ChangedFiles $files -Rules $rules

        $result | Should -BeNullOrEmpty
    }

    It "matches a wildcard extension pattern like *.test.*" {
        $rules = @(
            @{ Pattern = "*.test.*"; Label = "tests"; Priority = 1 }
        )
        $files = @("src/foo.test.ps1")

        $result = Get-PrLabels -ChangedFiles $files -Rules $rules

        $result | Should -Contain "tests"
    }

    It "matches deep nested paths with src/api/**" {
        $rules = @(
            @{ Pattern = "src/api/**"; Label = "api"; Priority = 1 }
        )
        $files = @("src/api/v1/users/handler.ps1")

        $result = Get-PrLabels -ChangedFiles $files -Rules $rules

        $result | Should -Contain "api"
    }
}

Describe "Get-PrLabels - multiple labels per file" {

    It "assigns multiple labels when a file matches multiple independent rules" {
        $rules = @(
            @{ Pattern = "src/api/**"; Label = "api"; Priority = 1 }
            @{ Pattern = "*.test.*"; Label = "tests"; Priority = 1 }
        )
        $files = @("src/api/handler.test.ps1")

        $result = Get-PrLabels -ChangedFiles $files -Rules $rules

        $result | Should -Contain "api"
        $result | Should -Contain "tests"
        $result.Count | Should -Be 2
    }

    It "de-duplicates labels when multiple files/rules produce the same label" {
        $rules = @(
            @{ Pattern = "docs/**"; Label = "documentation"; Priority = 1 }
            @{ Pattern = "*.md"; Label = "documentation"; Priority = 1 }
        )
        $files = @("docs/readme.md", "CHANGELOG.md")

        $result = Get-PrLabels -ChangedFiles $files -Rules $rules

        ($result | Where-Object { $_ -eq "documentation" }).Count | Should -Be 1
    }
}

Describe "Get-PrLabels - priority ordering" {

    It "orders labels by descending priority when rules conflict" {
        $rules = @(
            @{ Pattern = "src/**"; Label = "low-priority"; Priority = 1 }
            @{ Pattern = "src/critical/**"; Label = "high-priority"; Priority = 10 }
        )
        $files = @("src/critical/core.ps1")

        $result = Get-PrLabels -ChangedFiles $files -Rules $rules

        $result[0] | Should -Be "high-priority"
        $result[1] | Should -Be "low-priority"
    }
}

Describe "Get-PrLabels - error handling" {

    It "throws a meaningful error when ChangedFiles is empty" {
        $rules = @(@{ Pattern = "docs/**"; Label = "documentation"; Priority = 1 })

        { Get-PrLabels -ChangedFiles @() -Rules $rules } | Should -Throw "*ChangedFiles*"
    }

    It "throws a meaningful error when Rules is empty" {
        { Get-PrLabels -ChangedFiles @("docs/readme.md") -Rules @() } | Should -Throw "*Rules*"
    }

    It "throws a meaningful error when a rule is missing a Label" {
        $rules = @(@{ Pattern = "docs/**" })

        { Get-PrLabels -ChangedFiles @("docs/readme.md") -Rules $rules } | Should -Throw "*Pattern*Label*"
    }
}

Describe "Get-PrLabels - mocked file list (simulating a PR)" {

    BeforeAll {
        # Simulate a PR's changed-file list, as would be retrieved from
        # `git diff --name-only` or the GitHub API.
        function Get-MockPrChangedFiles {
            return @(
                "docs/setup.md",
                "src/api/v2/orders.ps1",
                "src/api/v2/orders.test.ps1",
                "src/utils/helpers.ps1"
            )
        }
    }

    It "produces the expected label set for a realistic mocked PR" {
        $rules = @(
            @{ Pattern = "docs/**"; Label = "documentation"; Priority = 1 }
            @{ Pattern = "src/api/**"; Label = "api"; Priority = 2 }
            @{ Pattern = "*.test.*"; Label = "tests"; Priority = 3 }
        )

        $files = Get-MockPrChangedFiles
        $result = Get-PrLabels -ChangedFiles $files -Rules $rules

        $result | Should -Contain "documentation"
        $result | Should -Contain "api"
        $result | Should -Contain "tests"
        $result.Count | Should -Be 3
        # Highest priority (tests) first
        $result[0] | Should -Be "tests"
    }
}
