# LabelAssigner.Tests.ps1
#
# Pester test suite for the PR label assigner, built with red/green TDD.
# Each Describe block corresponds to one TDD cycle: the tests were written
# first (red), then the minimum implementation was added (green), then
# refactored while keeping the suite green.

BeforeAll {
    # Import the module under test fresh for every run.
    $modulePath = Join-Path $PSScriptRoot '..' 'src' 'LabelAssigner.psm1'
    Import-Module $modulePath -Force
}

# --- TDD cycle 1: glob matching for '*' (single path segment) -------------
Describe 'Test-GlobMatch' {

    Context "single-star '*' matches within one path segment" {
        It "matches 'docs/*.md' against 'docs/readme.md'" {
            Test-GlobMatch -Path 'docs/readme.md' -Pattern 'docs/*.md' | Should -BeTrue
        }

        It "does not match 'docs/*.md' against 'docs/sub/readme.md' ('*' must not cross '/')" {
            Test-GlobMatch -Path 'docs/sub/readme.md' -Pattern 'docs/*.md' | Should -BeFalse
        }

        It "does not match 'docs/*.md' against 'src/readme.md'" {
            Test-GlobMatch -Path 'src/readme.md' -Pattern 'docs/*.md' | Should -BeFalse
        }
    }

    # --- TDD cycle 2: '**', '?', and basename-only patterns ---------------
    Context "double-star '**' matches across path segments" {
        It "matches 'docs/**' against 'docs/readme.md'" {
            Test-GlobMatch -Path 'docs/readme.md' -Pattern 'docs/**' | Should -BeTrue
        }

        It "matches 'docs/**' against a deeply nested file" {
            Test-GlobMatch -Path 'docs/guides/deploy/steps.md' -Pattern 'docs/**' | Should -BeTrue
        }

        It "does not match 'docs/**' against 'src/docs.md'" {
            Test-GlobMatch -Path 'src/docs.md' -Pattern 'docs/**' | Should -BeFalse
        }

        It "matches 'src/**/*.ps1' against 'src/api/users.ps1'" {
            Test-GlobMatch -Path 'src/api/users.ps1' -Pattern 'src/**/*.ps1' | Should -BeTrue
        }
    }

    Context "'?' matches exactly one non-separator character" {
        It "matches 'v?.md' against 'v1.md'" {
            Test-GlobMatch -Path 'v1.md' -Pattern 'v?.md' | Should -BeTrue
        }

        It "does not match 'v?.md' against 'v12.md'" {
            Test-GlobMatch -Path 'v12.md' -Pattern 'v?.md' | Should -BeFalse
        }
    }

    Context 'patterns without a slash match against any path depth (basename match)' {
        It "matches '*.test.*' against 'src/core/parser.test.ps1'" {
            Test-GlobMatch -Path 'src/core/parser.test.ps1' -Pattern '*.test.*' | Should -BeTrue
        }

        It "matches '*.test.*' against a root-level 'app.test.js'" {
            Test-GlobMatch -Path 'app.test.js' -Pattern '*.test.*' | Should -BeTrue
        }

        It "does not match '*.test.*' against 'src/testdata/foo.ps1'" {
            Test-GlobMatch -Path 'src/testdata/foo.ps1' -Pattern '*.test.*' | Should -BeFalse
        }
    }
}

# --- TDD cycle 3: mapping changed files to labels --------------------------
Describe 'Get-PRLabels' {

    BeforeAll {
        # Shared fixture: the classic ruleset from the task description.
        $script:basicRules = @(
            @{ Pattern = 'docs/**';    Labels = @('documentation'); Priority = 10 }
            @{ Pattern = 'src/api/**'; Labels = @('api');           Priority = 10 }
            @{ Pattern = '*.test.*';   Labels = @('tests');         Priority = 10 }
        )
    }

    Context 'basic path-to-label mapping' {
        It 'assigns a single label for a single matching file' {
            $labels = Get-PRLabels -ChangedFiles @('docs/readme.md') -Rules $basicRules
            @($labels) | Should -Be @('documentation')
        }

        It 'collects the union of labels across several changed files, sorted' {
            $files = @('docs/readme.md', 'src/api/users.ps1', 'src/core/parser.test.ps1')
            $labels = Get-PRLabels -ChangedFiles $files -Rules $basicRules
            @($labels) | Should -Be @('api', 'documentation', 'tests')
        }

        It 'returns an empty set when no rule matches' {
            $labels = Get-PRLabels -ChangedFiles @('LICENSE') -Rules $basicRules
            @($labels) | Should -BeNullOrEmpty
        }

        It 'returns an empty set for an empty changed-file list' {
            $labels = Get-PRLabels -ChangedFiles @() -Rules $basicRules
            @($labels) | Should -BeNullOrEmpty
        }

        It 'does not duplicate a label matched by many files' {
            $files = @('docs/a.md', 'docs/b.md')
            $labels = Get-PRLabels -ChangedFiles $files -Rules $basicRules
            @($labels) | Should -Be @('documentation')
        }
    }

    Context 'multiple labels per file' {
        It 'applies every label listed on a single matching rule' {
            $rules = @(@{ Pattern = 'src/api/**'; Labels = @('api', 'backend'); Priority = 10 })
            $labels = Get-PRLabels -ChangedFiles @('src/api/users.ps1') -Rules $rules
            @($labels) | Should -Be @('api', 'backend')
        }

        It 'merges labels from several equal-priority rules matching the same file' {
            $rules = @(
                @{ Pattern = 'src/api/**'; Labels = @('api');   Priority = 10 }
                @{ Pattern = '*.test.*';   Labels = @('tests'); Priority = 10 }
            )
            $labels = Get-PRLabels -ChangedFiles @('src/api/users.test.ps1') -Rules $rules
            @($labels) | Should -Be @('api', 'tests')
        }
    }

    # --- TDD cycle 4: priority ordering when rules conflict ----------------
    # Semantics: for each file, only the matching rules at the highest
    # priority (lowest Priority number) contribute labels; lower-priority
    # matches for that file are discarded. Priorities are per-file, so a
    # low-priority rule still fires for files nothing else claims.
    Context 'priority ordering when rules conflict' {
        It 'the more specific higher-priority rule wins for the same file' {
            $rules = @(
                @{ Pattern = 'docs/**';     Labels = @('documentation'); Priority = 20 }
                @{ Pattern = 'docs/api/**'; Labels = @('api-docs');      Priority = 10 }
            )
            $labels = Get-PRLabels -ChangedFiles @('docs/api/spec.md') -Rules $rules
            @($labels) | Should -Be @('api-docs')
        }

        It 'a lower-priority rule still applies to files the winner does not match' {
            $rules = @(
                @{ Pattern = 'docs/**';     Labels = @('documentation'); Priority = 20 }
                @{ Pattern = 'docs/api/**'; Labels = @('api-docs');      Priority = 10 }
            )
            $files = @('docs/api/spec.md', 'docs/intro.md')
            $labels = Get-PRLabels -ChangedFiles $files -Rules $rules
            @($labels) | Should -Be @('api-docs', 'documentation')
        }

        It 'equal-priority conflicting rules both contribute (tie = union)' {
            $rules = @(
                @{ Pattern = 'docs/**';     Labels = @('documentation'); Priority = 10 }
                @{ Pattern = 'docs/api/**'; Labels = @('api-docs');      Priority = 10 }
            )
            $labels = Get-PRLabels -ChangedFiles @('docs/api/spec.md') -Rules $rules
            @($labels) | Should -Be @('api-docs', 'documentation')
        }

        It 'rules without an explicit Priority default to 100 (lowest precedence)' {
            $rules = @(
                @{ Pattern = 'docs/**';     Labels = @('documentation') }   # implicit 100
                @{ Pattern = 'docs/api/**'; Labels = @('api-docs'); Priority = 10 }
            )
            $labels = Get-PRLabels -ChangedFiles @('docs/api/spec.md') -Rules $rules
            @($labels) | Should -Be @('api-docs')
        }
    }

    # --- TDD cycle 5a: graceful error handling ------------------------------
    Context 'error handling' {
        It 'throws a meaningful error when the rule set is empty' {
            { Get-PRLabels -ChangedFiles @('a.md') -Rules @() } |
                Should -Throw '*at least one rule*'
        }

        It 'throws a meaningful error when a rule has no Pattern' {
            $rules = @(@{ Labels = @('oops') })
            { Get-PRLabels -ChangedFiles @('a.md') -Rules $rules } |
                Should -Throw "*missing a 'Pattern'*"
        }

        It 'throws a meaningful error when a rule has no Labels' {
            $rules = @(@{ Pattern = 'docs/**' })
            { Get-PRLabels -ChangedFiles @('a.md') -Rules $rules } |
                Should -Throw "*missing 'Labels'*"
        }
    }
}

# --- TDD cycle 5b: CLI entry point over mocked fixture files ---------------
Describe 'Invoke-LabelAssigner.ps1 (CLI)' {

    BeforeAll {
        $script:cli = Join-Path $PSScriptRoot '..' 'src' 'Invoke-LabelAssigner.ps1'

        # Fixture: a mocked PR changed-file list + a JSON ruleset on disk.
        $script:fixtureDir = Join-Path $TestDrive 'fixtures'
        New-Item -ItemType Directory -Path $fixtureDir -Force | Out-Null

        @('docs/readme.md', 'src/api/users.ps1', 'src/core/parser.test.ps1') |
            Set-Content -Path (Join-Path $fixtureDir 'changed-files.txt')

        @(
            @{ pattern = 'docs/**';    labels = @('documentation'); priority = 10 }
            @{ pattern = 'src/api/**'; labels = @('api');           priority = 10 }
            @{ pattern = '*.test.*';   labels = @('tests');         priority = 10 }
        ) | ConvertTo-Json | Set-Content -Path (Join-Path $fixtureDir 'label-rules.json')
    }

    It 'prints the sorted final label set in a parseable FINAL LABELS line' {
        $out = & $cli -ChangedFilesPath (Join-Path $fixtureDir 'changed-files.txt') `
                      -RulesPath (Join-Path $fixtureDir 'label-rules.json')
        $out | Should -Contain 'FINAL LABELS: api,documentation,tests'
    }

    It "prints 'FINAL LABELS: (none)' when nothing matches" {
        $none = Join-Path $fixtureDir 'no-match.txt'
        Set-Content -Path $none -Value 'LICENSE'
        $out = & $cli -ChangedFilesPath $none -RulesPath (Join-Path $fixtureDir 'label-rules.json')
        $out | Should -Contain 'FINAL LABELS: (none)'
    }

    It 'fails with a meaningful error when the rules file does not exist' {
        { & $cli -ChangedFilesPath (Join-Path $fixtureDir 'changed-files.txt') `
                 -RulesPath (Join-Path $fixtureDir 'missing.json') } |
            Should -Throw '*Rules file not found*'
    }

    It 'fails with a meaningful error when the rules file is not valid JSON' {
        $bad = Join-Path $fixtureDir 'bad.json'
        Set-Content -Path $bad -Value '{ not json ]'
        { & $cli -ChangedFilesPath (Join-Path $fixtureDir 'changed-files.txt') -RulesPath $bad } |
            Should -Throw '*not valid JSON*'
    }
}
