<#
    Pester tests for the PrLabelAssigner module.
    Written test-first (red/green): each Describe block below was added and run
    against no/partial implementation until it failed, then PrLabelAssigner.psm1
    was written/extended just enough to turn it green.
#>

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'PrLabelAssigner.psm1') -Force
}

Describe 'Test-PrLabelGlobMatch' {
    Context 'doublestar directory patterns' {
        It 'matches a file directly under a doublestar directory pattern' {
            Test-PrLabelGlobMatch -Path 'docs/readme.md' -Pattern 'docs/**' | Should -BeTrue
        }

        It 'matches a deeply nested file under a doublestar directory pattern' {
            Test-PrLabelGlobMatch -Path 'docs/guides/setup/install.md' -Pattern 'docs/**' | Should -BeTrue
        }

        It 'does not match a sibling directory with a similar prefix' {
            Test-PrLabelGlobMatch -Path 'docs-legacy/readme.md' -Pattern 'docs/**' | Should -BeFalse
        }

        It 'matches nested API source files' {
            Test-PrLabelGlobMatch -Path 'src/api/handlers/users.ts' -Pattern 'src/api/**' | Should -BeTrue
        }

        It 'does not match files outside the target directory' {
            Test-PrLabelGlobMatch -Path 'src/ui/button.ts' -Pattern 'src/api/**' | Should -BeFalse
        }
    }

    Context 'basename patterns without a slash' {
        It 'matches a basename pattern at the repo root' {
            Test-PrLabelGlobMatch -Path 'button.test.ts' -Pattern '*.test.*' | Should -BeTrue
        }

        It 'matches a basename pattern at any depth' {
            Test-PrLabelGlobMatch -Path 'src/components/button.test.ts' -Pattern '*.test.*' | Should -BeTrue
        }

        It 'does not match files that do not fit the basename pattern' {
            Test-PrLabelGlobMatch -Path 'src/components/button.spec.ts' -Pattern '*.test.*' | Should -BeFalse
        }
    }

    Context 'edge cases' {
        It 'is case-sensitive' {
            Test-PrLabelGlobMatch -Path 'DOCS/readme.md' -Pattern 'docs/**' | Should -BeFalse
        }

        It 'treats backslashes in the candidate path as path separators' {
            Test-PrLabelGlobMatch -Path 'docs\readme.md' -Pattern 'docs/**' | Should -BeTrue
        }
    }
}

Describe 'Import-PrLabelRules' {
    BeforeAll {
        $script:TestDataDir = Join-Path $TestDrive 'rules'
        New-Item -ItemType Directory -Path $script:TestDataDir -Force | Out-Null
    }

    It 'throws a meaningful error when the rules file does not exist' {
        $missingPath = Join-Path $script:TestDataDir 'does-not-exist.json'
        { Import-PrLabelRules -Path $missingPath } | Should -Throw '*not found*'
    }

    It 'throws a meaningful error when the file is not valid JSON' {
        $badJsonPath = Join-Path $script:TestDataDir 'bad.json'
        Set-Content -Path $badJsonPath -Value '{ this is not json'
        { Import-PrLabelRules -Path $badJsonPath } | Should -Throw '*JSON*'
    }

    It 'throws a meaningful error when a rule is missing Pattern' {
        $path = Join-Path $script:TestDataDir 'missing-pattern.json'
        Set-Content -Path $path -Value '[{ "Label": "documentation" }]'
        { Import-PrLabelRules -Path $path } | Should -Throw '*Pattern*'
    }

    It 'throws a meaningful error when a rule is missing Label' {
        $path = Join-Path $script:TestDataDir 'missing-label.json'
        Set-Content -Path $path -Value '[{ "Pattern": "docs/**" }]'
        { Import-PrLabelRules -Path $path } | Should -Throw '*Label*'
    }

    It 'loads valid rules and defaults Priority to 0 and Group to null' {
        $path = Join-Path $script:TestDataDir 'valid.json'
        Set-Content -Path $path -Value '[{ "Pattern": "docs/**", "Label": "documentation" }]'
        $rules = Import-PrLabelRules -Path $path
        $rules.Count | Should -Be 1
        $rules[0].Pattern | Should -Be 'docs/**'
        $rules[0].Label | Should -Be 'documentation'
        $rules[0].Priority | Should -Be 0
        $rules[0].Group | Should -BeNullOrEmpty
    }

    It 'preserves explicit Priority and Group values' {
        $path = Join-Path $script:TestDataDir 'priority.json'
        Set-Content -Path $path -Value '[{ "Pattern": "**/*.generated.*", "Label": "generated", "Priority": 100, "Group": "area" }]'
        $rules = Import-PrLabelRules -Path $path
        $rules[0].Priority | Should -Be 100
        $rules[0].Group | Should -Be 'area'
    }

    It 'loads multiple rules from a single file' {
        $path = Join-Path $script:TestDataDir 'multi.json'
        Set-Content -Path $path -Value '[{ "Pattern": "docs/**", "Label": "documentation" }, { "Pattern": "*.test.*", "Label": "tests" }]'
        $rules = Import-PrLabelRules -Path $path
        $rules.Count | Should -Be 2
    }
}

Describe 'Get-PrChangedFiles' {
    Context 'reading from a fixture file' {
        BeforeAll {
            $script:FixtureDir = Join-Path $TestDrive 'fixture-reads'
            New-Item -ItemType Directory -Path $script:FixtureDir -Force | Out-Null
        }

        It 'returns trimmed, non-empty lines from the fixture file' {
            $fixturePath = Join-Path $script:FixtureDir 'changed-files.txt'
            Set-Content -Path $fixturePath -Value @('docs/readme.md', '  src/api/handler.ts  ', '', 'src/api/handler.test.ts')
            $files = Get-PrChangedFiles -FixturePath $fixturePath
            $files.Count | Should -Be 3
            $files | Should -Contain 'docs/readme.md'
            $files | Should -Contain 'src/api/handler.ts'
            $files | Should -Contain 'src/api/handler.test.ts'
        }

        It 'prefers the fixture file over a supplied BaseRef when both are given' {
            $fixturePath = Join-Path $script:FixtureDir 'changed-files-2.txt'
            Set-Content -Path $fixturePath -Value 'docs/only.md'
            $files = Get-PrChangedFiles -FixturePath $fixturePath -BaseRef 'main'
            $files | Should -Be @('docs/only.md')
        }
    }

    Context 'falling back to git diff' {
        BeforeAll {
            $script:GitRepoDir = Join-Path $TestDrive 'git-repo'
            New-Item -ItemType Directory -Path $script:GitRepoDir -Force | Out-Null
            Push-Location $script:GitRepoDir
            git init --quiet --initial-branch=main .
            git config user.email 'test@example.com'
            git config user.name 'Test User'
            'first' | Set-Content -Path 'base.txt'
            git add base.txt
            git commit --quiet -m 'base commit'
            git rev-parse HEAD | Out-Null
            'second' | Set-Content -Path 'docs.md'
            git add docs.md
            git commit --quiet -m 'add docs'
            Pop-Location
        }

        It 'returns files changed between BaseRef and HeadRef via git diff' {
            Push-Location $script:GitRepoDir
            try {
                $files = Get-PrChangedFiles -FixturePath (Join-Path $script:GitRepoDir 'nonexistent.txt') -BaseRef 'HEAD~1' -HeadRef 'HEAD'
                $files | Should -Be @('docs.md')
            } finally {
                Pop-Location
            }
        }
    }

    Context 'when nothing is available' {
        It 'throws a meaningful error when no fixture file and no BaseRef are provided' {
            { Get-PrChangedFiles -FixturePath (Join-Path $TestDrive 'missing.txt') } | Should -Throw '*changed files*'
        }
    }
}

Describe 'Resolve-PrLabels' {
    Context 'basic path-to-label mapping' {
        BeforeAll {
            $script:BasicRules = @(
                [PSCustomObject]@{ Pattern = 'docs/**'; Label = 'documentation'; Priority = 0; Group = $null }
                [PSCustomObject]@{ Pattern = 'src/api/**'; Label = 'api'; Priority = 0; Group = $null }
                [PSCustomObject]@{ Pattern = '*.test.*'; Label = 'tests'; Priority = 0; Group = $null }
                [PSCustomObject]@{ Pattern = '*.spec.*'; Label = 'tests'; Priority = 0; Group = $null }
            )
        }

        It 'assigns a single label for a single matching file' {
            $labels = Resolve-PrLabels -ChangedFiles @('docs/readme.md') -Rules $script:BasicRules
            $labels | Should -Be @('documentation')
        }

        It 'aggregates distinct labels across multiple changed files' {
            $labels = Resolve-PrLabels -ChangedFiles @('docs/readme.md', 'src/api/handler.ts') -Rules $script:BasicRules
            $labels | Should -Be @('api', 'documentation')
        }

        It 'assigns multiple labels to a single file that matches multiple rules' {
            $labels = Resolve-PrLabels -ChangedFiles @('src/api/handler.test.ts') -Rules $script:BasicRules
            $labels | Should -Be @('api', 'tests')
        }

        It 'deduplicates a label matched by more than one file or rule' {
            $labels = Resolve-PrLabels -ChangedFiles @('src/api/a.test.ts', 'src/api/b.spec.ts') -Rules $script:BasicRules
            $labels | Should -Be @('api', 'tests')
        }

        It 'ignores files that match no rule' {
            $labels = Resolve-PrLabels -ChangedFiles @('LICENSE', 'docs/readme.md') -Rules $script:BasicRules
            $labels | Should -Be @('documentation')
        }

        It 'returns an empty array when no files are changed' {
            $labels = Resolve-PrLabels -ChangedFiles @() -Rules $script:BasicRules
            $labels | Should -BeNullOrEmpty
        }

        It 'returns an empty array when no rules are supplied' {
            $labels = Resolve-PrLabels -ChangedFiles @('docs/readme.md') -Rules @()
            $labels | Should -BeNullOrEmpty
        }
    }

    Context 'priority ordering when rules conflict within a Group' {
        BeforeAll {
            $script:GroupedRules = @(
                [PSCustomObject]@{ Pattern = 'src/**'; Label = 'frontend'; Priority = 1; Group = 'area' }
                [PSCustomObject]@{ Pattern = '**/*.generated.*'; Label = 'generated'; Priority = 100; Group = 'area' }
            )
        }

        It 'lets the higher-priority rule in a Group win for a file matched by both' {
            $labels = Resolve-PrLabels -ChangedFiles @('src/widgets/button.generated.ts') -Rules $script:GroupedRules
            $labels | Should -Be @('generated')
        }

        It 'still assigns the lower-priority label to files that only match it' {
            $labels = Resolve-PrLabels -ChangedFiles @('src/app.ts', 'src/widgets/button.generated.ts') -Rules $script:GroupedRules
            $labels | Should -Be @('frontend', 'generated')
        }

        It 'is unaffected by rule declaration order (priority alone decides the winner)' {
            $reordered = @($script:GroupedRules[1], $script:GroupedRules[0])
            $labels = Resolve-PrLabels -ChangedFiles @('src/widgets/button.generated.ts') -Rules $reordered
            $labels | Should -Be @('generated')
        }
    }

    Context 'input validation' {
        It 'throws a meaningful error when a rule is missing a Label' {
            $badRules = @([PSCustomObject]@{ Pattern = 'docs/**' })
            { Resolve-PrLabels -ChangedFiles @('docs/readme.md') -Rules $badRules } | Should -Throw '*Label*'
        }

        It 'throws a meaningful error when a rule is missing a Pattern' {
            $badRules = @([PSCustomObject]@{ Label = 'documentation' })
            { Resolve-PrLabels -ChangedFiles @('docs/readme.md') -Rules $badRules } | Should -Throw '*Pattern*'
        }
    }
}

Describe 'end-to-end pipeline with a mocked changed-file list' {
    It 'combines a mocked Get-PrChangedFiles with Import-PrLabelRules and Resolve-PrLabels' {
        Mock -CommandName Get-PrChangedFiles -MockWith {
            @('docs/readme.md', 'src/api/handler.test.ts')
        }

        $rulesPath = Join-Path $TestDrive 'e2e-rules.json'
        @(
            [PSCustomObject]@{ Pattern = 'docs/**'; Label = 'documentation' }
            [PSCustomObject]@{ Pattern = 'src/api/**'; Label = 'api' }
            [PSCustomObject]@{ Pattern = '*.test.*'; Label = 'tests' }
        ) | ConvertTo-Json | Set-Content -Path $rulesPath

        $rules = Import-PrLabelRules -Path $rulesPath
        $changedFiles = Get-PrChangedFiles -FixturePath 'this-path-is-irrelevant-because-of-the-mock.txt'
        $labels = Resolve-PrLabels -ChangedFiles $changedFiles -Rules $rules

        $labels | Should -Be @('api', 'documentation', 'tests')
        Should -Invoke -CommandName Get-PrChangedFiles -Times 1 -Exactly
    }
}
