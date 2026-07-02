# Pester tests for PrLabelAssigner.ps1
# TDD approach: each Describe/It block below was written before the corresponding
# implementation existed in PrLabelAssigner.ps1 (red), then minimal code was added
# to satisfy it (green), then the implementation was refactored while keeping
# these tests passing.

BeforeAll {
    . "$PSScriptRoot/PrLabelAssigner.ps1"
}

Describe "Convert-GlobToRegex" {
    It "converts a simple '**' glob into a regex that matches any nested path" {
        $regex = Convert-GlobToRegex -Glob "docs/**"
        "docs/readme.md" -match $regex | Should -BeTrue
        "docs/sub/dir/file.md" -match $regex | Should -BeTrue
        "notdocs/readme.md" -match $regex | Should -BeFalse
    }

    It "treats '*' as matching within a single path segment only" {
        $regex = Convert-GlobToRegex -Glob "src/*.js"
        "src/index.js" -match $regex | Should -BeTrue
        "src/sub/index.js" -match $regex | Should -BeFalse
    }
}

Describe "Test-PathMatchesGlob" {
    It "matches path-based globs (containing '/') against the full relative path" {
        Test-PathMatchesGlob -Path "src/api/users.go" -Glob "src/api/**" | Should -BeTrue
        Test-PathMatchesGlob -Path "src/web/users.go" -Glob "src/api/**" | Should -BeFalse
    }

    It "matches name-based globs (no '/') against just the file's base name, anywhere in the tree" {
        Test-PathMatchesGlob -Path "src/api/users.test.js" -Glob "*.test.*" | Should -BeTrue
        Test-PathMatchesGlob -Path "src/api/users.js" -Glob "*.test.*" | Should -BeFalse
    }

    It "throws a meaningful error when given a null or empty glob" {
        { Test-PathMatchesGlob -Path "a.txt" -Glob "" } | Should -Throw "*glob pattern*"
    }
}

Describe "Import-LabelRules" {
    It "throws a clear error when the rules file does not exist" {
        { Import-LabelRules -RulesPath "$PSScriptRoot/fixtures/unit/does-not-exist.json" } |
            Should -Throw "*Rules file not found*"
    }

    It "loads a valid rules file into an array of rule objects" {
        $rules = Import-LabelRules -RulesPath "$PSScriptRoot/fixtures/unit/rules.json"
        $rules.Count | Should -BeGreaterThan 0
        $rules[0].Pattern | Should -Not -BeNullOrEmpty
        $rules[0].Label | Should -Not -BeNullOrEmpty
    }

    It "throws a clear error when a rule is missing a required field" {
        { Import-LabelRules -RulesPath "$PSScriptRoot/fixtures/unit/invalid-rules-missing-label.json" } |
            Should -Throw "*missing required field 'Label'*"
    }
}

Describe "Get-FileLabels (single file, rule matching + conflict resolution)" {
    BeforeAll {
        $script:rules = Import-LabelRules -RulesPath "$PSScriptRoot/fixtures/unit/rules.json"
    }

    It "returns every matching label for a file when rules do not conflict" {
        $labels = Get-FileLabels -File "docs/guide/setup.md" -Rules $rules
        $labels | Should -Contain "documentation"
    }

    It "returns multiple independent labels when a file matches multiple non-conflicting rules" {
        # src/api/users.test.js matches both 'src/api/**' (api) and '*.test.*' (tests)
        $labels = Get-FileLabels -File "src/api/users.test.js" -Rules $rules
        $labels | Should -Contain "api"
        $labels | Should -Contain "tests"
    }

    It "resolves conflicting rules in the same ConflictGroup using Priority (lowest wins)" {
        # src/legacy/api/old.go matches both 'src/**' (code, priority 10, group area)
        # and the more specific 'src/legacy/**' (legacy, priority 1, group area)
        $labels = Get-FileLabels -File "src/legacy/api/old.go" -Rules $rules
        $labels | Should -Contain "legacy"
        $labels | Should -Not -Contain "code"
    }
}

Describe "Get-PrLabels (whole change set)" {
    BeforeAll {
        $script:rules = Import-LabelRules -RulesPath "$PSScriptRoot/fixtures/unit/rules.json"
    }

    It "returns an empty array when there are no changed files" {
        $labels = Get-PrLabels -ChangedFiles @() -Rules $rules
        ($labels -is [array]) | Should -BeTrue -Because "the function should always return an array wrapper"
        $labels.Count | Should -Be 0
    }

    It "returns a de-duplicated, sorted set of labels across all changed files" {
        $files = @(
            "docs/readme.md",
            "src/api/users.go",
            "src/api/users.test.js",
            "src/legacy/api/old.go"
        )
        # src/api/users.go and src/legacy/api/old.go both fall under the generic
        # 'src/**' -> code rule via the 'area' ConflictGroup; only old.go also
        # matches the more specific 'src/legacy/**' rule, so it gets 'legacy'
        # instead of 'code' for that one file -- but 'code' still applies
        # because of users.go.
        $labels = Get-PrLabels -ChangedFiles $files -Rules $rules
        $labels | Should -Be @("api", "code", "documentation", "legacy", "tests")
    }

    It "returns an empty array when no file matches any rule" {
        $labels = Get-PrLabels -ChangedFiles @("unmatched/file.xyz") -Rules $rules
        $labels.Count | Should -Be 0
    }
}
