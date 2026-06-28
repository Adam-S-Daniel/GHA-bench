# PrLabelAssigner.Tests.ps1
# Pester 5 tests for the PR Label Assigner script.
#
# TDD methodology: each Describe block was written as a failing test first,
# then the minimum code in PrLabelAssigner.ps1 was added to make it pass.
#
# Run with: Invoke-Pester -Path ./PrLabelAssigner.Tests.ps1

BeforeAll {
    # Dot-source the script under test. Because it is dot-sourced, the main
    # execution guard at the bottom of the script is skipped and only the
    # functions become available in this scope.
    . "$PSScriptRoot/PrLabelAssigner.ps1"
}

Describe 'Convert-GlobToRegex' {
    It 'converts a literal segment to an anchored regex that matches exactly' {
        $rx = Convert-GlobToRegex -Glob 'package.json'
        'package.json'      | Should -Match $rx
        'src/package.json'  | Should -Not -Match $rx
    }

    It 'treats * as matching within a single path segment (no slash)' {
        $rx = Convert-GlobToRegex -Glob '*.md'
        'README.md'    | Should -Match $rx
        'docs/a.md'    | Should -Not -Match $rx
    }

    It 'treats ** as matching across path segments' {
        $rx = Convert-GlobToRegex -Glob 'docs/**'
        'docs/a.md'           | Should -Match $rx
        'docs/guide/intro.md' | Should -Match $rx
        'src/a.md'            | Should -Not -Match $rx
    }

    It 'supports **/ prefix to match a filename pattern at any depth' {
        $rx = Convert-GlobToRegex -Glob '**/*.test.*'
        'a.test.js'                | Should -Match $rx
        'src/api/users.test.ts'    | Should -Match $rx
        'src/api/users.ts'         | Should -Not -Match $rx
    }

    It 'escapes regex metacharacters that are not glob wildcards' {
        $rx = Convert-GlobToRegex -Glob 'a+b.txt'
        'a+b.txt' | Should -Match $rx
        'axb.txt' | Should -Not -Match $rx
    }
}

Describe 'Test-GlobMatch' {
    It 'returns $true when the path matches the glob' {
        Test-GlobMatch -Path 'docs/a.md' -Glob 'docs/**' | Should -BeTrue
    }

    It 'returns $false when the path does not match the glob' {
        Test-GlobMatch -Path 'src/a.ts' -Glob 'docs/**' | Should -BeFalse
    }
}

Describe 'Get-PrLabels' {
    BeforeAll {
        # A representative rule set exercising every feature: glob patterns,
        # multiple labels per rule, overlapping rules, priorities, and an
        # exclusive rule used for conflict resolution.
        $script:Rules = @(
            [pscustomobject]@{ pattern = 'docs/**';     labels = @('documentation'); priority = 10 }
            [pscustomobject]@{ pattern = '*.md';         labels = @('documentation'); priority = 10 }
            [pscustomobject]@{ pattern = 'src/**';       labels = @('backend');       priority = 20 }
            [pscustomobject]@{ pattern = 'src/api/**';   labels = @('api','backend'); priority = 30 }
            [pscustomobject]@{ pattern = '**/*.test.*';  labels = @('tests');         priority = 40 }
        )
    }

    It 'returns a single label for a file matching one rule' {
        $labels = Get-PrLabels -ChangedFiles @('docs/guide.md') -Rules $script:Rules
        $labels | Should -Be @('documentation')
    }

    It 'unions labels from multiple matching rules for one file' {
        # src/api/x.ts matches both src/** (backend) and src/api/** (api,backend)
        $labels = Get-PrLabels -ChangedFiles @('src/api/x.ts') -Rules $script:Rules
        # Sorted by priority desc, then alpha. Both labels effectively priority 30.
        $labels | Should -Be @('api','backend')
    }

    It 'orders the final label set by rule priority (highest first)' {
        $labels = Get-PrLabels -ChangedFiles @('src/api/users.test.ts') -Rules $script:Rules
        # tests(40) > api(30) = backend(30); ties broken alphabetically.
        $labels | Should -Be @('tests','api','backend')
    }

    It 'aggregates and de-duplicates labels across multiple changed files' {
        $files = @('docs/a.md', 'src/api/x.ts', 'README.md')
        $labels = Get-PrLabels -ChangedFiles $files -Rules $script:Rules
        # documentation(10) from docs/** and *.md; api(30), backend(30) from src/api/**.
        $labels | Should -Be @('api','backend','documentation')
    }

    It 'returns an empty array when no rule matches any file' {
        $labels = Get-PrLabels -ChangedFiles @('LICENSE') -Rules $script:Rules
        $labels | Should -BeNullOrEmpty
    }

    It 'honours an exclusive rule that overrides lower-priority labels per file' {
        $rules = @(
            [pscustomobject]@{ pattern = 'src/**';     labels = @('backend'); priority = 20 }
            [pscustomobject]@{ pattern = 'generated/**'; labels = @('skip-review'); priority = 99; exclusive = $true }
        )
        # A generated file matches an exclusive rule; only its labels apply for that file.
        $labels = Get-PrLabels -ChangedFiles @('generated/api.ts', 'src/app.ts') -Rules $rules
        $labels | Should -Be @('skip-review','backend')
    }
}

Describe 'Get-RuleConfig' {
    It 'loads rules from a JSON config file' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("cfg_" + [System.IO.Path]::GetRandomFileName() + ".json")
        @{ rules = @(@{ pattern = 'docs/**'; labels = @('documentation'); priority = 10 }) } |
            ConvertTo-Json -Depth 5 | Set-Content -Path $tmp -Encoding utf8
        try {
            $rules = Get-RuleConfig -Path $tmp
            $rules.Count        | Should -Be 1
            $rules[0].pattern   | Should -Be 'docs/**'
            $rules[0].labels    | Should -Be @('documentation')
        } finally {
            Remove-Item $tmp -Force
        }
    }

    It 'throws a meaningful error when the config file is missing' {
        { Get-RuleConfig -Path '/no/such/config.json' } |
            Should -Throw -ExpectedMessage '*Config file not found*'
    }

    It 'throws a meaningful error when the config JSON is malformed' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("bad_" + [System.IO.Path]::GetRandomFileName() + ".json")
        'this is not json {{' | Set-Content -Path $tmp -Encoding utf8
        try {
            { Get-RuleConfig -Path $tmp } | Should -Throw -ExpectedMessage '*Failed to parse*'
        } finally {
            Remove-Item $tmp -Force
        }
    }
}

Describe 'Get-ChangedFileList' {
    It 'reads a JSON array of file paths' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("files_" + [System.IO.Path]::GetRandomFileName() + ".json")
        @('docs/a.md','src/b.ts') | ConvertTo-Json | Set-Content -Path $tmp -Encoding utf8
        try {
            $files = Get-ChangedFileList -Path $tmp
            $files | Should -Be @('docs/a.md','src/b.ts')
        } finally {
            Remove-Item $tmp -Force
        }
    }

    It 'throws a meaningful error when the changed-files file is missing' {
        { Get-ChangedFileList -Path '/no/such/files.json' } |
            Should -Throw -ExpectedMessage '*Changed files list not found*'
    }
}
