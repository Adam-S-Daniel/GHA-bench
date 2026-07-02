# Pester tests for LabelAssigner.psm1, written test-first (red/green TDD).
# Each Describe block below was authored before its corresponding
# implementation existed in the module; run `Invoke-Pester` from the repo
# root to execute the full suite.

BeforeAll {
    $script:ModulePath = Join-Path $PSScriptRoot '..' 'LabelAssigner.psm1'
    Import-Module $script:ModulePath -Force
}

Describe 'Test-GlobMatch' {
    It 'matches an exact literal path' {
        Test-GlobMatch -Path 'src/main.ps1' -Pattern 'src/main.ps1' | Should -BeTrue
    }

    It 'does not match a different literal path' {
        Test-GlobMatch -Path 'src/other.ps1' -Pattern 'src/main.ps1' | Should -BeFalse
    }

    It 'matches a single-segment wildcard *' {
        Test-GlobMatch -Path 'docs/readme.md' -Pattern 'docs/*.md' | Should -BeTrue
    }

    It 'does not let a single-segment * cross a directory boundary' {
        Test-GlobMatch -Path 'docs/sub/readme.md' -Pattern 'docs/*.md' | Should -BeFalse
    }

    It 'matches nested paths with a trailing **' {
        Test-GlobMatch -Path 'docs/sub/deep/readme.md' -Pattern 'docs/**' | Should -BeTrue
    }

    It 'matches files directly inside the dir for a trailing ** pattern' {
        Test-GlobMatch -Path 'docs/readme.md' -Pattern 'docs/**' | Should -BeTrue
    }

    It 'does not match a sibling directory that merely shares a prefix' {
        Test-GlobMatch -Path 'docsonly/readme.md' -Pattern 'docs/**' | Should -BeFalse
    }

    It 'matches a slash-less pattern against a nested file (gitignore-style)' {
        Test-GlobMatch -Path 'src/api/users.test.ts' -Pattern '*.test.*' | Should -BeTrue
    }

    It 'matches ? as exactly one character' {
        Test-GlobMatch -Path 'src/v1.ts' -Pattern 'src/v?.ts' | Should -BeTrue
    }

    It 'does not match ? against zero or multiple characters' {
        Test-GlobMatch -Path 'src/v10.ts' -Pattern 'src/v?.ts' | Should -BeFalse
    }

    It 'treats regex metacharacters in the pattern as literals' {
        Test-GlobMatch -Path 'src/a+b.ts' -Pattern 'src/a+b.ts' | Should -BeTrue
    }
}

Describe 'New-LabelRule' {
    It 'creates a rule object carrying the given pattern and label' {
        $rule = New-LabelRule -Pattern 'docs/**' -Label 'documentation'
        $rule.Pattern | Should -Be 'docs/**'
        $rule.Label | Should -Be 'documentation'
    }

    It 'defaults Priority to 0 and ExclusiveGroup to $null when not specified' {
        $rule = New-LabelRule -Pattern 'docs/**' -Label 'documentation'
        $rule.Priority | Should -Be 0
        $rule.ExclusiveGroup | Should -BeNullOrEmpty
    }

    It 'carries an explicit Priority and ExclusiveGroup' {
        $rule = New-LabelRule -Pattern 'src/api/**' -Label 'api' -Priority 80 -ExclusiveGroup 'area'
        $rule.Priority | Should -Be 80
        $rule.ExclusiveGroup | Should -Be 'area'
    }

    It 'throws a meaningful error when Pattern is empty' {
        { New-LabelRule -Pattern '' -Label 'x' } | Should -Throw '*Pattern*'
    }

    It 'throws a meaningful error when Label is empty' {
        { New-LabelRule -Pattern 'x' -Label '' } | Should -Throw '*Label*'
    }
}

Describe 'Import-LabelRules' {
    BeforeAll {
        $script:tempDir = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:tempDir -Force | Out-Null
    }

    AfterAll {
        Remove-Item -Path $script:tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'throws a meaningful error when the rules file does not exist' {
        $missing = Join-Path $script:tempDir 'missing.json'
        { Import-LabelRules -Path $missing } | Should -Throw '*not found*'
    }

    It 'throws a meaningful error for malformed JSON' {
        $badPath = Join-Path $script:tempDir 'bad.json'
        Set-Content -Path $badPath -Value '{ not valid json'
        { Import-LabelRules -Path $badPath } | Should -Throw '*Failed to parse*'
    }

    It 'throws a meaningful error when a rule entry is missing Label' {
        $path = Join-Path $script:tempDir 'missing-label.json'
        Set-Content -Path $path -Value '[{"Pattern":"docs/**"}]'
        { Import-LabelRules -Path $path } | Should -Throw "*'Label'*"
    }

    It 'throws a meaningful error when a rule entry is missing Pattern' {
        $path = Join-Path $script:tempDir 'missing-pattern.json'
        Set-Content -Path $path -Value '[{"Label":"documentation"}]'
        { Import-LabelRules -Path $path } | Should -Throw "*'Pattern'*"
    }

    It 'loads valid rule entries with defaults applied' {
        $path = Join-Path $script:tempDir 'valid.json'
        Set-Content -Path $path -Value '[{"Pattern":"docs/**","Label":"documentation","Priority":5,"ExclusiveGroup":"area"},{"Pattern":"*.test.*","Label":"tests"}]'
        $rules = @(Import-LabelRules -Path $path)
        $rules.Count | Should -Be 2
        $rules[0].Label | Should -Be 'documentation'
        $rules[0].Priority | Should -Be 5
        $rules[0].ExclusiveGroup | Should -Be 'area'
        $rules[1].Priority | Should -Be 0
        $rules[1].ExclusiveGroup | Should -BeNullOrEmpty
    }
}

Describe 'Get-PrLabels' {
    BeforeAll {
        # A rule set that exercises glob patterns, independent (non-exclusive)
        # labels, and a priority conflict within an exclusive group ('area').
        $script:rules = @(
            New-LabelRule -Pattern 'docs/**'    -Label 'documentation' -Priority 50  -ExclusiveGroup 'area'
            New-LabelRule -Pattern 'src/api/**' -Label 'api'           -Priority 80  -ExclusiveGroup 'area'
            New-LabelRule -Pattern 'src/**'     -Label 'source'        -Priority 10  -ExclusiveGroup 'area'
            New-LabelRule -Pattern '*.test.*'   -Label 'tests'         -Priority 100
            New-LabelRule -Pattern '*.md'       -Label 'documentation' -Priority 20
        )
    }

    It 'returns an empty result for an empty changed-file list' {
        Get-PrLabels -ChangedFiles @() -Rules $script:rules | Should -BeNullOrEmpty
    }

    It 'applies a single matching label for a docs file' {
        @(Get-PrLabels -ChangedFiles @('docs/readme.md') -Rules $script:rules) | Should -Be @('documentation')
    }

    It 'ignores files that match no rule' {
        Get-PrLabels -ChangedFiles @('LICENSE') -Rules $script:rules | Should -BeNullOrEmpty
    }

    It 'applies multiple independent labels to the same file' {
        $result = @(Get-PrLabels -ChangedFiles @('src/api/users.test.ts') -Rules $script:rules)
        $result | Should -Contain 'api'
        $result | Should -Contain 'tests'
        $result.Count | Should -Be 2
    }

    It 'resolves a conflict in an exclusive group by picking the highest-priority label' {
        $result = @(Get-PrLabels -ChangedFiles @('src/api/users.ts') -Rules $script:rules)
        $result | Should -Be @('api')
        $result | Should -Not -Contain 'source'
    }

    It 'falls back to the only matching rule in a group when there is no conflict' {
        $result = @(Get-PrLabels -ChangedFiles @('src/utils/helper.ts') -Rules $script:rules)
        $result | Should -Be @('source')
    }

    It 'aggregates and de-duplicates labels across multiple changed files' {
        $files = @('docs/readme.md', 'src/api/users.ts', 'src/utils/helper.ts')
        $result = @(Get-PrLabels -ChangedFiles $files -Rules $script:rules)
        $expected = @('api', 'documentation', 'source')
        (Compare-Object $result $expected | Measure-Object).Count | Should -Be 0
    }

    It 'sorts the returned labels alphabetically' {
        $files = @('src/api/users.test.ts', 'src/utils/helper.ts')
        $result = @(Get-PrLabels -ChangedFiles $files -Rules $script:rules)
        $result | Should -Be @('api', 'source', 'tests')
    }

    It 'throws a meaningful error for a rule object missing required properties' {
        $badRule = [PSCustomObject]@{ Label = 'x' }
        { Get-PrLabels -ChangedFiles @('a.txt') -Rules @($badRule) } | Should -Throw "*'Pattern'*"
    }

    It 'throws a meaningful error when a changed file entry is empty' {
        { Get-PrLabels -ChangedFiles @('') -Rules $script:rules } | Should -Throw '*empty*'
    }
}
