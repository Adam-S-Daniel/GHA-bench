<#
    Pester tests for the PR Label Assigner tool.

    Written test-first (red/green TDD): each Describe block below was added
    before the corresponding implementation existed in ../PRLabelAssigner.psm1,
    run once to confirm it failed for the right reason, then made to pass with
    the minimum code needed. Later blocks build on earlier ones (e.g. the
    exclusive-priority tests were only added once basic label collection
    already passed).
#>

BeforeAll {
    Import-Module "$PSScriptRoot/../PRLabelAssigner.psm1" -Force
}

Describe 'Test-GlobMatch' {
    It 'matches a simple directory-prefix glob (docs/**)' {
        Test-GlobMatch -Path 'docs/guide.md' -Pattern 'docs/**' | Should -BeTrue
    }

    It 'matches nested paths under a double-star glob' {
        Test-GlobMatch -Path 'docs/sub/deep/file.md' -Pattern 'docs/**' | Should -BeTrue
    }

    It 'does not match a path outside the glob prefix' {
        Test-GlobMatch -Path 'src/docs.md' -Pattern 'docs/**' | Should -BeFalse
    }

    It 'matches a slash-less pattern against the basename regardless of directory' {
        Test-GlobMatch -Path 'src/api/handler.test.js' -Pattern '*.test.*' | Should -BeTrue
    }

    It 'does not match a slash-less pattern when the basename does not fit' {
        Test-GlobMatch -Path 'src/api/handler.js' -Pattern '*.test.*' | Should -BeFalse
    }

    It 'is case-insensitive' {
        Test-GlobMatch -Path 'DOCS/Guide.MD' -Pattern 'docs/**' | Should -BeTrue
    }
}

Describe 'Get-PRLabels - basic single-rule mapping' {
    It 'assigns the documentation label for a file under docs/**' {
        $rules = @(
            [pscustomobject]@{ Pattern = 'docs/**'; Label = 'documentation'; Priority = 1 }
        )
        $labels = Get-PRLabels -ChangedFiles @('docs/readme.md') -Rules $rules
        $labels | Should -Be @('documentation')
    }

    It 'returns no labels when nothing matches' {
        $rules = @(
            [pscustomobject]@{ Pattern = 'docs/**'; Label = 'documentation'; Priority = 1 }
        )
        $labels = Get-PRLabels -ChangedFiles @('src/main.ts') -Rules $rules
        $labels | Should -BeNullOrEmpty
    }
}

Describe 'Get-PRLabels - multiple labels per file' {
    It 'applies every non-exclusive rule that matches a single file' {
        $rules = @(
            [pscustomobject]@{ Pattern = 'src/api/**'; Label = 'api'; Priority = 1 }
            [pscustomobject]@{ Pattern = '*.test.*'; Label = 'tests'; Priority = 1 }
        )
        $labels = Get-PRLabels -ChangedFiles @('src/api/handler.test.js') -Rules $rules
        $labels | Should -Be @('api', 'tests')
    }

    It 'unions labels across multiple changed files' {
        $rules = @(
            [pscustomobject]@{ Pattern = 'docs/**'; Label = 'documentation'; Priority = 1 }
            [pscustomobject]@{ Pattern = 'src/api/**'; Label = 'api'; Priority = 1 }
        )
        $labels = Get-PRLabels -ChangedFiles @('docs/readme.md', 'src/api/handler.js') -Rules $rules
        $labels | Should -Be @('api', 'documentation')
    }
}

Describe 'Get-PRLabels - priority ordering resolves exclusive conflicts' {
    It 'keeps only the highest-priority label within an exclusive group for one file' {
        $rules = @(
            [pscustomobject]@{ Pattern = 'src/**'; Label = 'source'; Priority = 1; ExclusiveGroup = 'area' }
            [pscustomobject]@{ Pattern = 'src/api/**'; Label = 'api'; Priority = 2; ExclusiveGroup = 'area' }
        )
        $labels = Get-PRLabels -ChangedFiles @('src/api/client.ts') -Rules $rules
        $labels | Should -Be @('api')
    }

    It 'lets a lower-priority exclusive rule win for a file the higher-priority rule does not touch' {
        $rules = @(
            [pscustomobject]@{ Pattern = 'src/**'; Label = 'source'; Priority = 1; ExclusiveGroup = 'area' }
            [pscustomobject]@{ Pattern = 'src/api/**'; Label = 'api'; Priority = 2; ExclusiveGroup = 'area' }
        )
        $labels = Get-PRLabels -ChangedFiles @('src/utils/helper.ts', 'src/api/client.ts') -Rules $rules
        $labels | Should -Be @('api', 'source')
    }

    It 'does not let exclusivity suppress labels from a different group' {
        $rules = @(
            [pscustomobject]@{ Pattern = 'src/**'; Label = 'source'; Priority = 1; ExclusiveGroup = 'area' }
            [pscustomobject]@{ Pattern = 'src/api/**'; Label = 'api'; Priority = 2; ExclusiveGroup = 'area' }
            [pscustomobject]@{ Pattern = '*.test.*'; Label = 'tests'; Priority = 1 }
        )
        $labels = Get-PRLabels -ChangedFiles @('src/api/client.test.ts') -Rules $rules
        $labels | Should -Be @('api', 'tests')
    }
}

Describe 'Get-PRLabels - error handling' {
    It 'throws a meaningful error when ChangedFiles is empty' {
        $rules = @([pscustomobject]@{ Pattern = 'docs/**'; Label = 'documentation'; Priority = 1 })
        { Get-PRLabels -ChangedFiles @() -Rules $rules } | Should -Throw '*ChangedFiles*'
    }

    It 'throws a meaningful error when a rule is missing a Pattern' {
        $rules = @([pscustomobject]@{ Label = 'documentation'; Priority = 1 })
        { Get-PRLabels -ChangedFiles @('docs/readme.md') -Rules $rules } | Should -Throw '*Pattern*'
    }

    It 'throws a meaningful error when a rule is missing a Label' {
        $rules = @([pscustomobject]@{ Pattern = 'docs/**'; Priority = 1 })
        { Get-PRLabels -ChangedFiles @('docs/readme.md') -Rules $rules } | Should -Throw '*Label*'
    }
}

Describe 'Assign-PRLabels.ps1 - end-to-end with mocked file lists' {
    BeforeEach {
        $script:changedFilesPath = Join-Path $TestDrive 'changed-files.json'
        $script:rulesPath = Join-Path $TestDrive 'label-rules.json'

        # Mock changed-file list, standing in for a real PR's diff.
        @('docs/readme.md', 'src/api/handler.test.js') | ConvertTo-Json | Set-Content -Path $script:changedFilesPath

        @(
            [pscustomobject]@{ Pattern = 'docs/**'; Label = 'documentation'; Priority = 1 }
            [pscustomobject]@{ Pattern = 'src/api/**'; Label = 'api'; Priority = 1 }
            [pscustomobject]@{ Pattern = '*.test.*'; Label = 'tests'; Priority = 1 }
        ) | ConvertTo-Json | Set-Content -Path $script:rulesPath
    }

    It 'prints the final label set computed from the mocked file list' {
        $output = & "$PSScriptRoot/../Assign-PRLabels.ps1" -ChangedFilesPath $script:changedFilesPath -RulesPath $script:rulesPath
        ($output -join "`n") | Should -Match 'Final Labels: api, documentation, tests'
    }

    It 'throws a meaningful error when the changed-files fixture is missing' {
        { & "$PSScriptRoot/../Assign-PRLabels.ps1" -ChangedFilesPath (Join-Path $TestDrive 'missing.json') -RulesPath $script:rulesPath } |
            Should -Throw '*not found*'
    }
}
