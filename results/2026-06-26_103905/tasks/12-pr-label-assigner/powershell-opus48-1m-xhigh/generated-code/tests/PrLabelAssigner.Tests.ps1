#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Pester test suite for the PR Label Assigner.
#
# Written TDD-style: each Describe block corresponds to a unit of behavior
# that was driven into existence by a failing test first. The very first
# cycle started with the single "matches a simple ** glob" test below.

BeforeAll {
    # Import the module under test. $PSScriptRoot is the tests/ directory.
    $script:ModulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'src/PrLabelAssigner.psm1'
    Import-Module $script:ModulePath -Force
}

Describe 'Test-GlobMatch' {
    Context 'directory globs with **' {
        It 'matches a path under a "**" directory glob' {
            Test-GlobMatch -Path 'docs/guide.md' -Pattern 'docs/**' | Should -BeTrue
        }
        It 'matches a deeply nested path under "**"' {
            Test-GlobMatch -Path 'src/api/v1/users.ts' -Pattern 'src/api/**' | Should -BeTrue
        }
        It 'does not match a sibling directory' {
            Test-GlobMatch -Path 'src/web/users.ts' -Pattern 'src/api/**' | Should -BeFalse
        }
    }

    Context 'single-star * does not cross path separators' {
        It 'matches a file directly under a directory' {
            Test-GlobMatch -Path 'src/main.ts' -Pattern 'src/*.ts' | Should -BeTrue
        }
        It 'does not match a file in a nested directory' {
            Test-GlobMatch -Path 'src/api/users.ts' -Pattern 'src/*.ts' | Should -BeFalse
        }
    }

    Context 'patterns without a slash match the basename at any depth' {
        It 'matches a test file in a nested directory with *.test.*' {
            Test-GlobMatch -Path 'src/components/Button.test.tsx' -Pattern '*.test.*' | Should -BeTrue
        }
        It 'matches a markdown file at the repo root with *.md' {
            Test-GlobMatch -Path 'README.md' -Pattern '*.md' | Should -BeTrue
        }
        It 'matches an exact filename anywhere (package.json)' {
            Test-GlobMatch -Path 'frontend/package.json' -Pattern 'package.json' | Should -BeTrue
        }
    }

    Context 'leading **/ matches zero or more leading directories' {
        It 'matches when there are no leading directories' {
            Test-GlobMatch -Path 'Button.test.tsx' -Pattern '**/*.test.*' | Should -BeTrue
        }
        It 'matches when there are leading directories' {
            Test-GlobMatch -Path 'a/b/Button.test.tsx' -Pattern '**/*.test.*' | Should -BeTrue
        }
    }

    Context '? matches exactly one non-separator character' {
        It 'matches a single character' {
            Test-GlobMatch -Path 'v1/app.ts' -Pattern 'v?/app.ts' | Should -BeTrue
        }
        It 'does not match a path separator' {
            Test-GlobMatch -Path 'a/b/app.ts' -Pattern 'a?b/app.ts' | Should -BeFalse
        }
    }

    Context 'matching is case-insensitive' {
        It 'matches regardless of case' {
            Test-GlobMatch -Path 'Docs/Guide.MD' -Pattern 'docs/**' | Should -BeTrue
        }
    }
}

Describe 'Resolve-PrLabels' {
    BeforeAll {
        # A representative rule set covering every feature: multiple labels per
        # rule, overlapping rules, priorities, and an exclusive (StopOnMatch) rule.
        $script:Rules = @(
            [pscustomobject]@{ Pattern = '**/*.generated.*'; Labels = @('generated');        Priority = 100; StopOnMatch = $true }
            [pscustomobject]@{ Pattern = '*.test.*';         Labels = @('tests');             Priority = 50 }
            [pscustomobject]@{ Pattern = 'package.json';     Labels = @('dependencies');      Priority = 40 }
            [pscustomobject]@{ Pattern = 'src/api/**';       Labels = @('api', 'backend');    Priority = 30 }
            [pscustomobject]@{ Pattern = 'src/**';           Labels = @('source');            Priority = 20 }
            [pscustomobject]@{ Pattern = 'docs/**';          Labels = @('documentation');     Priority = 10 }
            [pscustomobject]@{ Pattern = '*.md';             Labels = @('documentation');     Priority = 10 }
        )
    }

    It 'assigns a single label from a single matching rule' {
        $result = Resolve-PrLabels -ChangedFiles @('docs/intro.md') -Rules $script:Rules
        $result.Labels | Should -Contain 'documentation'
    }

    It 'assigns multiple labels from one rule to one file' {
        $result = Resolve-PrLabels -ChangedFiles @('src/api/users.ts') -Rules $script:Rules
        $result.Labels | Should -Contain 'api'
        $result.Labels | Should -Contain 'backend'
    }

    It 'unions labels from multiple matching rules for one file' {
        # src/api/users.ts matches src/api/** (api, backend) AND src/** (source)
        $result = Resolve-PrLabels -ChangedFiles @('src/api/users.ts') -Rules $script:Rules
        $result.Labels | Should -Contain 'source'
    }

    It 'deduplicates labels contributed by more than one rule' {
        # docs/x.md matches both docs/** and *.md, both -> documentation
        $result = Resolve-PrLabels -ChangedFiles @('docs/x.md') -Rules $script:Rules
        ($result.Labels | Where-Object { $_ -eq 'documentation' }).Count | Should -Be 1
    }

    It 'orders the final label set by descending priority, ties broken alphabetically' {
        $files = @(
            'docs/guide.md', 'src/api/users.ts', 'src/api/users.test.ts',
            'src/utils/helper.ts', 'README.md', 'package.json'
        )
        $result = Resolve-PrLabels -ChangedFiles $files -Rules $script:Rules
        $result.Labels -join ',' |
            Should -Be 'tests,dependencies,api,backend,source,documentation'
    }

    It 'honors StopOnMatch: an exclusive high-priority rule suppresses lower rules for that file' {
        # schema.generated.ts also matches src/api/** and src/**, but StopOnMatch wins.
        $result = Resolve-PrLabels -ChangedFiles @('src/api/schema.generated.ts') -Rules $script:Rules
        $result.Labels -join ',' | Should -Be 'generated'
    }

    It 'records per-file label detail' {
        $result = Resolve-PrLabels -ChangedFiles @('src/api/users.test.ts') -Rules $script:Rules
        $file = $result.Files | Where-Object { $_.Path -eq 'src/api/users.test.ts' }
        $file.Labels | Should -Contain 'tests'
        $file.Labels | Should -Contain 'api'
        $file.Labels | Should -Contain 'source'
    }

    It 'returns an empty label set when no files are provided' {
        $result = Resolve-PrLabels -ChangedFiles @() -Rules $script:Rules
        $result.Labels | Should -BeNullOrEmpty
    }

    It 'returns an empty label set when no rules match' {
        $result = Resolve-PrLabels -ChangedFiles @('LICENSE', '.gitignore') -Rules $script:Rules
        $result.Labels | Should -BeNullOrEmpty
    }

    It 'treats a missing Priority as the lowest priority (0)' {
        $rules = @(
            [pscustomobject]@{ Pattern = 'a/**'; Labels = @('high'); Priority = 5 }
            [pscustomobject]@{ Pattern = 'b/**'; Labels = @('nopri') }   # no Priority field
        )
        $result = Resolve-PrLabels -ChangedFiles @('a/x', 'b/y') -Rules $rules
        $result.Labels -join ',' | Should -Be 'high,nopri'
    }

    It 'throws a meaningful error for a rule with no pattern' {
        $bad = @([pscustomobject]@{ Labels = @('x') })
        { Resolve-PrLabels -ChangedFiles @('a') -Rules $bad } |
            Should -Throw -ExpectedMessage "*missing a non-empty 'Pattern'*"
    }

    It 'throws a meaningful error for a rule with no labels' {
        $bad = @([pscustomobject]@{ Pattern = 'a/**'; Labels = @() })
        { Resolve-PrLabels -ChangedFiles @('a/x') -Rules $bad } |
            Should -Throw -ExpectedMessage '*at least one label*'
    }

    It 'accepts rules supplied as hashtables as well as objects' {
        $rules = @(@{ Pattern = 'docs/**'; Labels = @('documentation'); Priority = 1 })
        $result = Resolve-PrLabels -ChangedFiles @('docs/a.md') -Rules $rules
        $result.Labels | Should -Contain 'documentation'
    }
}

Describe 'Import-LabelRules' {
    It 'loads rules from a valid JSON config file' {
        $path = Join-Path $TestDrive 'rules.json'
        @'
{
  "rules": [
    { "pattern": "docs/**", "labels": ["documentation"], "priority": 10 },
    { "pattern": "src/api/**", "labels": ["api", "backend"], "priority": 30 }
  ]
}
'@ | Set-Content -Path $path -Encoding utf8

        $rules = Import-LabelRules -Path $path
        $rules.Count | Should -Be 2
        $rules[0].pattern | Should -Be 'docs/**'
        $rules[1].labels  | Should -Contain 'backend'
    }

    It 'parsed JSON rules feed straight into Resolve-PrLabels' {
        $path = Join-Path $TestDrive 'rules2.json'
        @'
{ "rules": [ { "pattern": "*.md", "labels": ["documentation"], "priority": 5 } ] }
'@ | Set-Content -Path $path -Encoding utf8

        $rules = Import-LabelRules -Path $path
        $result = Resolve-PrLabels -ChangedFiles @('README.md') -Rules $rules
        $result.Labels | Should -Contain 'documentation'
    }

    It 'throws a clear error when the config file does not exist' {
        { Import-LabelRules -Path (Join-Path $TestDrive 'missing.json') } |
            Should -Throw -ExpectedMessage '*not found*'
    }

    It 'throws a clear error for malformed JSON' {
        $path = Join-Path $TestDrive 'bad.json'
        'this is { not json' | Set-Content -Path $path -Encoding utf8
        { Import-LabelRules -Path $path } |
            Should -Throw -ExpectedMessage '*Failed to parse*'
    }

    It 'throws a clear error when the "rules" array is absent' {
        $path = Join-Path $TestDrive 'norules.json'
        '{ "something": 1 }' | Set-Content -Path $path -Encoding utf8
        { Import-LabelRules -Path $path } |
            Should -Throw -ExpectedMessage "*'rules'*"
    }
}

Describe 'Get-ChangedFile' {
    It 'reads one path per line' {
        $path = Join-Path $TestDrive 'files.txt'
        "docs/a.md`nsrc/b.ts" | Set-Content -Path $path -Encoding utf8
        $files = Get-ChangedFile -Path $path
        $files | Should -Be @('docs/a.md', 'src/b.ts')
    }

    It 'ignores blank lines and # comments and trims whitespace' {
        $path = Join-Path $TestDrive 'files2.txt'
        @'
# this is a comment
docs/a.md

   src/b.ts
'@ | Set-Content -Path $path -Encoding utf8
        $files = Get-ChangedFile -Path $path
        $files | Should -Be @('docs/a.md', 'src/b.ts')
    }

    It 'returns an empty array for an empty file' {
        $path = Join-Path $TestDrive 'empty.txt'
        '' | Set-Content -Path $path -Encoding utf8
        @(Get-ChangedFile -Path $path).Count | Should -Be 0
    }

    It 'throws a clear error when the file does not exist' {
        { Get-ChangedFile -Path (Join-Path $TestDrive 'nope.txt') } |
            Should -Throw -ExpectedMessage '*not found*'
    }
}

Describe 'Format-PrLabelOutput' {
    BeforeAll {
        $script:Rules = @(
            [pscustomobject]@{ Pattern = 'src/api/**'; Labels = @('api', 'backend'); Priority = 30 }
            [pscustomobject]@{ Pattern = 'src/**';     Labels = @('source');         Priority = 20 }
            [pscustomobject]@{ Pattern = 'docs/**';    Labels = @('documentation');  Priority = 10 }
        )
    }

    It 'emits a machine-parseable PR_LABELS marker line' {
        $result = Resolve-PrLabels -ChangedFiles @('src/api/x.ts', 'docs/y.md') -Rules $script:Rules
        $out = Format-PrLabelOutput -Result $result
        $out | Should -Contain 'PR_LABELS=api,backend,source,documentation'
    }

    It 'emits a PR_LABEL_COUNT marker line' {
        $result = Resolve-PrLabels -ChangedFiles @('src/api/x.ts') -Rules $script:Rules
        $out = Format-PrLabelOutput -Result $result
        $out | Should -Contain 'PR_LABEL_COUNT=3'
    }

    It 'emits empty markers when there are no labels' {
        $result = Resolve-PrLabels -ChangedFiles @('LICENSE') -Rules $script:Rules
        $out = Format-PrLabelOutput -Result $result
        $out | Should -Contain 'PR_LABELS='
        $out | Should -Contain 'PR_LABEL_COUNT=0'
    }

    It 'includes a per-file breakdown line for each changed file' {
        $result = Resolve-PrLabels -ChangedFiles @('src/api/x.ts') -Rules $script:Rules
        $out = Format-PrLabelOutput -Result $result
        ($out -join "`n") | Should -Match 'src/api/x\.ts\s*->\s*api, backend, source'
    }
}
