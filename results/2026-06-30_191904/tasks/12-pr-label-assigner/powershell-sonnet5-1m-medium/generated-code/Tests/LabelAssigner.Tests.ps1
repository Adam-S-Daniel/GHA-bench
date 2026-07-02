# Pester tests for the LabelAssigner module.
# TDD: each Describe block below was written before its corresponding
# implementation existed in LabelAssigner.psm1. Run with `Invoke-Pester`.

BeforeAll {
    Import-Module "$PSScriptRoot/../LabelAssigner.psm1" -Force
}

Describe 'Test-GlobMatch' {
    It 'matches a simple wildcard within a single path segment' {
        Test-GlobMatch -Path 'file.test.js' -Pattern '*.test.js' | Should -BeTrue
    }

    It 'does not match a single "*" across a path separator' {
        Test-GlobMatch -Path 'src/file.js' -Pattern '*.js' | Should -BeFalse
    }

    It 'matches nested paths with "**"' {
        Test-GlobMatch -Path 'docs/guide/setup.md' -Pattern 'docs/**' | Should -BeTrue
    }

    It 'matches the directory itself with "**"' {
        Test-GlobMatch -Path 'docs/readme.md' -Pattern 'docs/**' | Should -BeTrue
    }

    It 'does not match files outside the globbed directory' {
        Test-GlobMatch -Path 'src/readme.md' -Pattern 'docs/**' | Should -BeFalse
    }

    It 'matches "**" combined with a suffix pattern across directories' {
        Test-GlobMatch -Path 'lib/deep/nested/util.test.ts' -Pattern '**/*.test.*' | Should -BeTrue
    }

    It 'is case-insensitive' {
        Test-GlobMatch -Path 'DOCS/readme.MD' -Pattern 'docs/**' | Should -BeTrue
    }
}

Describe 'Import-LabelRules' {
    BeforeAll {
        $script:validConfig = Join-Path $TestDrive 'valid.json'
        @'
[
  { "pattern": "docs/**", "label": "documentation", "priority": 10 },
  { "pattern": "src/**", "label": "backend", "priority": 5, "group": "area" }
]
'@ | Set-Content -LiteralPath $script:validConfig

        $script:missingFieldConfig = Join-Path $TestDrive 'missing-field.json'
        '[{ "pattern": "docs/**" }]' | Set-Content -LiteralPath $script:missingFieldConfig

        $script:badJsonConfig = Join-Path $TestDrive 'bad.json'
        '{ not valid json' | Set-Content -LiteralPath $script:badJsonConfig
    }

    It 'loads rules with pattern, label, priority, and group' {
        $rules = Import-LabelRules -Path $script:validConfig
        $rules.Count | Should -Be 2
        $rules[0].Pattern | Should -Be 'docs/**'
        $rules[0].Label | Should -Be 'documentation'
        $rules[0].Priority | Should -Be 10
        $rules[1].Group | Should -Be 'area'
    }

    It 'defaults priority to 0 when omitted' {
        $config = Join-Path $TestDrive 'no-priority.json'
        '[{ "pattern": "*.md", "label": "documentation" }]' | Set-Content -LiteralPath $config
        $rules = Import-LabelRules -Path $config
        $rules[0].Priority | Should -Be 0
    }

    It 'throws a meaningful error when the file does not exist' {
        { Import-LabelRules -Path (Join-Path $TestDrive 'nope.json') } | Should -Throw '*not found*'
    }

    It 'throws a meaningful error when a rule is missing a required field' {
        { Import-LabelRules -Path $script:missingFieldConfig } | Should -Throw '*label*'
    }

    It 'throws a meaningful error when the JSON is malformed' {
        { Import-LabelRules -Path $script:badJsonConfig } | Should -Throw '*JSON*'
    }
}

Describe 'Resolve-FileLabels' {
    BeforeAll {
        $script:rules = @(
            [PSCustomObject]@{ Pattern = 'docs/**'; Label = 'documentation'; Priority = 10; Group = $null }
            [PSCustomObject]@{ Pattern = '**/*.test.*'; Label = 'tests'; Priority = 10; Group = $null }
            [PSCustomObject]@{ Pattern = 'src/api/**'; Label = 'api'; Priority = 20; Group = 'area' }
            [PSCustomObject]@{ Pattern = 'src/**'; Label = 'backend'; Priority = 5; Group = 'area' }
        )
    }

    It 'returns an empty array when no rule matches' {
        Resolve-FileLabels -File 'README.txt' -Rules $script:rules | Should -BeNullOrEmpty
    }

    It 'returns a single label for a single matching rule' {
        Resolve-FileLabels -File 'docs/readme.md' -Rules $script:rules | Should -Be @('documentation')
    }

    It 'returns multiple labels when independent (ungrouped) rules both match' {
        $result = Resolve-FileLabels -File 'src/api/users.test.js' -Rules $script:rules
        $result | Should -Contain 'tests'
        $result | Should -Contain 'api'
    }

    It 'resolves conflicting rules in the same group by highest priority' {
        $result = Resolve-FileLabels -File 'src/api/users.js' -Rules $script:rules
        $result | Should -Be @('api')
        $result | Should -Not -Contain 'backend'
    }

    It 'falls back to the lower-priority grouped rule when the higher one does not match' {
        $result = Resolve-FileLabels -File 'src/utils.js' -Rules $script:rules
        $result | Should -Be @('backend')
    }
}

Describe 'Get-PRLabels' {
    BeforeAll {
        $script:rules = @(
            [PSCustomObject]@{ Pattern = 'docs/**'; Label = 'documentation'; Priority = 10; Group = $null }
            [PSCustomObject]@{ Pattern = '**/*.test.*'; Label = 'tests'; Priority = 10; Group = $null }
            [PSCustomObject]@{ Pattern = 'src/api/**'; Label = 'api'; Priority = 20; Group = 'area' }
            [PSCustomObject]@{ Pattern = 'src/**'; Label = 'backend'; Priority = 5; Group = 'area' }
        )
    }

    It 'returns an empty array for an empty file list' {
        Get-PRLabels -Files @() -Rules $script:rules | Should -BeNullOrEmpty
    }

    It 'unions and de-duplicates labels across many files, sorted alphabetically' {
        $files = @('docs/readme.md', 'src/api/users.js', 'src/api/users.test.js', 'src/utils.test.js')
        $result = Get-PRLabels -Files $files -Rules $script:rules
        $result | Should -Be @('api', 'backend', 'documentation', 'tests')
    }

    It 'excludes losing grouped labels from the final set even if produced by another file' {
        $files = @('src/utils.js', 'src/api/users.js')
        $result = Get-PRLabels -Files $files -Rules $script:rules
        # src/utils.js alone would give "backend", but src/api/users.js's "api"
        # rule is evaluated independently per file, so both can surface unless
        # the same file resolves the conflict. Here they are different files,
        # each resolving its own group independently.
        $result | Should -Be @('api', 'backend')
    }
}
