# Pester tests for the PR Label Assigner.
# TDD approach: each Describe block was written before the implementation it
# exercises (red), then the minimum code was added to LabelAssigner.psm1 to
# make it pass (green), followed by refactoring.

BeforeAll {
    # Import the module under test fresh for every run.
    Import-Module (Join-Path $PSScriptRoot '..' 'LabelAssigner.psm1') -Force
}

Describe 'Test-GlobMatch' {

    Context 'single-star patterns (no directory crossing)' {
        It 'matches a plain wildcard within one path segment' {
            Test-GlobMatch -Path 'src/main.ps1' -Pattern 'src/*.ps1' | Should -BeTrue
        }

        It 'does not let * cross directory separators' {
            Test-GlobMatch -Path 'src/api/main.ps1' -Pattern 'src/*.ps1' | Should -BeFalse
        }
    }

    Context 'double-star patterns (recursive)' {
        It 'matches any file under a directory tree' {
            Test-GlobMatch -Path 'docs/guide/intro.md' -Pattern 'docs/**' | Should -BeTrue
        }

        It 'matches direct children of the directory too' {
            Test-GlobMatch -Path 'docs/readme.md' -Pattern 'docs/**' | Should -BeTrue
        }

        It 'does not match files outside the tree' {
            Test-GlobMatch -Path 'src/docs.ps1' -Pattern 'docs/**' | Should -BeFalse
        }

        It 'supports ** in the middle of a pattern' {
            Test-GlobMatch -Path 'src/api/v2/users.ps1' -Pattern 'src/**/*.ps1' | Should -BeTrue
        }

        It 'allows **/ to match zero directories' {
            Test-GlobMatch -Path 'src/users.ps1' -Pattern 'src/**/*.ps1' | Should -BeTrue
        }
    }

    Context 'bare filename patterns match against the basename' {
        It 'matches *.test.* anywhere in the tree' {
            Test-GlobMatch -Path 'src/api/users.test.ts' -Pattern '*.test.*' | Should -BeTrue
        }

        It 'does not match when the basename differs' {
            Test-GlobMatch -Path 'src/api/users.ts' -Pattern '*.test.*' | Should -BeFalse
        }
    }

    Context '? wildcard' {
        It 'matches exactly one non-separator character' {
            Test-GlobMatch -Path 'file1.txt' -Pattern 'file?.txt' | Should -BeTrue
            Test-GlobMatch -Path 'file10.txt' -Pattern 'file?.txt' | Should -BeFalse
        }
    }

    Context 'literal patterns and regex metacharacters' {
        It 'treats regex metacharacters in the pattern literally' {
            Test-GlobMatch -Path 'a+b/file.txt' -Pattern 'a+b/*.txt' | Should -BeTrue
        }

        It 'matches exact literal paths' {
            Test-GlobMatch -Path 'CHANGELOG.md' -Pattern 'CHANGELOG.md' | Should -BeTrue
        }
    }
}

Describe 'Get-PRLabels' {

    BeforeAll {
        # Shared rule fixture: mirrors the task's example mapping plus a
        # higher-priority exclusive rule to exercise conflict resolution.
        $script:Rules = @(
            @{ Pattern = 'docs/**';          Labels = @('documentation') },
            @{ Pattern = 'src/api/**';       Labels = @('api', 'backend') },
            @{ Pattern = '*.test.*';         Labels = @('tests') },
            @{ Pattern = 'docs/internal/**'; Labels = @('internal-docs'); Priority = 10; Exclusive = $true }
        )
    }

    Context 'basic mapping' {
        It 'maps a single file to its label' {
            Get-PRLabels -ChangedFiles @('docs/readme.md') -Rules $script:Rules |
                Should -Be @('documentation')
        }

        It 'returns an empty set when nothing matches' {
            Get-PRLabels -ChangedFiles @('Makefile') -Rules $script:Rules |
                Should -BeNullOrEmpty
        }
    }

    Context 'multiple labels' {
        It 'applies multiple labels from a single rule' {
            Get-PRLabels -ChangedFiles @('src/api/users.ps1') -Rules $script:Rules |
                Should -Be @('api', 'backend')
        }

        It 'accumulates labels from several matching rules for one file' {
            # src/api/users.test.ts matches both src/api/** and *.test.*
            Get-PRLabels -ChangedFiles @('src/api/users.test.ts') -Rules $script:Rules |
                Should -Be @('api', 'backend', 'tests')
        }

        It 'deduplicates and sorts labels across many files' {
            $files = @('docs/a.md', 'docs/b.md', 'src/api/x.ps1', 'src/api/y.ps1')
            Get-PRLabels -ChangedFiles $files -Rules $script:Rules |
                Should -Be @('api', 'backend', 'documentation')
        }
    }

    Context 'priority ordering on conflicts' {
        It 'lets a high-priority exclusive rule shadow lower-priority rules for a file' {
            # docs/internal/secrets.md matches both docs/** and docs/internal/**,
            # but the internal rule is exclusive with higher priority.
            Get-PRLabels -ChangedFiles @('docs/internal/secrets.md') -Rules $script:Rules |
                Should -Be @('internal-docs')
        }

        It 'still applies lower-priority rules to files the exclusive rule does not match' {
            $files = @('docs/internal/secrets.md', 'docs/public.md')
            Get-PRLabels -ChangedFiles $files -Rules $script:Rules |
                Should -Be @('documentation', 'internal-docs')
        }

        It 'applies all matching rules when none are exclusive' {
            $rules = @(
                @{ Pattern = 'docs/**';       Labels = @('documentation'); Priority = 1 },
                @{ Pattern = 'docs/api/**';   Labels = @('api-docs');      Priority = 5 }
            )
            Get-PRLabels -ChangedFiles @('docs/api/rest.md') -Rules $rules |
                Should -Be @('api-docs', 'documentation')
        }
    }

    Context 'error handling' {
        It 'throws a meaningful error for a rule without a Pattern' {
            { Get-PRLabels -ChangedFiles @('a.txt') -Rules @(@{ Labels = @('x') }) } |
                Should -Throw '*missing a ''Pattern''*'
        }

        It 'throws a meaningful error for a rule without Labels' {
            { Get-PRLabels -ChangedFiles @('a.txt') -Rules @(@{ Pattern = '*.txt' }) } |
                Should -Throw '*must define at least one label*'
        }

        It 'accepts an empty changed-file list and returns nothing' {
            Get-PRLabels -ChangedFiles @() -Rules $script:Rules | Should -BeNullOrEmpty
        }
    }
}
