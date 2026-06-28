# PRLabelAssigner.Tests.ps1
#
# Unit tests for the PR Label Assigner module, written with red/green TDD.
# These exercise the pure logic of the module (glob -> regex conversion,
# path matching, config loading, and the end-to-end label resolution with
# priority ordering) directly and fast, so each red/green cycle is quick.
#
# The full behavioural surface is ALSO exercised end-to-end through the
# GitHub Actions workflow via `act` (see Act.Integration.Tests.ps1); these
# unit tests are the fast TDD scaffolding that drove the implementation.

BeforeAll {
    # Import the module under test. $PSScriptRoot is the tests/ directory.
    $script:ModulePath = Join-Path $PSScriptRoot '..' 'src' 'PRLabelAssigner.psm1'
    Import-Module $script:ModulePath -Force
}

Describe 'ConvertTo-GlobRegex' {
    It 'converts a single * into a single-segment wildcard ([^/]*)' {
        # A single star must NOT cross directory separators.
        ConvertTo-GlobRegex -Glob '*.json' | Should -Be '^[^/]*\.json$'
    }

    It 'converts a bare ** into a cross-directory wildcard (.*)' {
        ConvertTo-GlobRegex -Glob 'docs/**' | Should -Be '^docs/.*$'
    }

    It 'converts a leading **/ into an optional directory prefix' {
        # **/ must be optional so "**/x" matches both "x" and "a/b/x".
        ConvertTo-GlobRegex -Glob '**/*.md' | Should -Be '^(?:.*/)?[^/]*\.md$'
    }

    It 'converts ? into a single non-separator character' {
        ConvertTo-GlobRegex -Glob 'v?.txt' | Should -Be '^v[^/]\.txt$'
    }

    It 'escapes regex-special characters so they match literally' {
        ConvertTo-GlobRegex -Glob '.github/**' | Should -Be '^\.github/.*$'
    }
}

Describe 'Test-GlobMatch' {
    It 'matches a file inside a globstar directory' {
        Test-GlobMatch -Path 'docs/readme.md' -Glob 'docs/**' | Should -BeTrue
    }

    It 'does not let a single * cross a directory separator' {
        Test-GlobMatch -Path 'src/config.json' -Glob '*.json' | Should -BeFalse
        Test-GlobMatch -Path 'config.json'     -Glob '*.json' | Should -BeTrue
    }

    It 'matches files at any depth with a leading **/' {
        Test-GlobMatch -Path 'a.md'       -Glob '**/*.md' | Should -BeTrue
        Test-GlobMatch -Path 'docs/a.md'  -Glob '**/*.md' | Should -BeTrue
        Test-GlobMatch -Path 'x/y/z.md'   -Glob '**/*.md' | Should -BeTrue
    }

    It 'matches a compound extension pattern like *.test.*' {
        Test-GlobMatch -Path 'src/api/u.test.ps1' -Glob '**/*.test.*' | Should -BeTrue
        Test-GlobMatch -Path 'src/api/u.ps1'      -Glob '**/*.test.*' | Should -BeFalse
    }

    It 'is case-sensitive so .Tests.ps1 does not match *.test.*' {
        Test-GlobMatch -Path 'Foo.Tests.ps1' -Glob '**/*.test.*' | Should -BeFalse
    }
}

Describe 'Get-PRLabels' {
    BeforeAll {
        # A small, representative rule set used across these tests.
        $script:rules = @(
            [pscustomobject]@{ pattern = 'docs/**';     labels = @('documentation'); priority = 10 }
            [pscustomobject]@{ pattern = '**/*.md';      labels = @('documentation'); priority = 10 }
            [pscustomobject]@{ pattern = 'src/api/**';   labels = @('api', 'backend'); priority = 50 }
            [pscustomobject]@{ pattern = 'src/**';       labels = @('source');        priority = 20 }
            [pscustomobject]@{ pattern = '**/*.test.*';  labels = @('tests');         priority = 40 }
        )
    }

    It 'returns an empty set when there are no changed files' {
        Get-PRLabels -ChangedFiles @() -Rules $script:rules | Should -BeNullOrEmpty
    }

    It 'returns an empty set when nothing matches' {
        Get-PRLabels -ChangedFiles @('LICENSE', 'Makefile') -Rules $script:rules | Should -BeNullOrEmpty
    }

    It 'assigns the label of the single matching rule' {
        (Get-PRLabels -ChangedFiles @('docs/readme.md') -Rules $script:rules) -join ',' |
            Should -Be 'documentation'
    }

    It 'assigns multiple labels from a single rule' {
        # src/api/x.ps1 matches src/api/** (api,backend @50) and src/** (source @20).
        (Get-PRLabels -ChangedFiles @('src/api/x.ps1') -Rules $script:rules) -join ',' |
            Should -Be 'api,backend,source'
    }

    It 'unions labels across multiple files and de-duplicates' {
        $files = @('docs/a.md', 'src/api/b.ps1', 'src/core/c.ps1')
        # documentation@10, api@50, backend@50, source@20
        (Get-PRLabels -ChangedFiles $files -Rules $script:rules) -join ',' |
            Should -Be 'api,backend,source,documentation'
    }

    It 'orders labels by priority descending, then alphabetically for ties' {
        # A file hitting tests@40, api@50, backend@50, source@20.
        (Get-PRLabels -ChangedFiles @('src/api/x.test.ps1') -Rules $script:rules) -join ',' |
            Should -Be 'api,backend,tests,source'
    }

    It 'uses the highest priority when a label is contributed by several rules' {
        $rules = @(
            [pscustomobject]@{ pattern = '**/*.ps1'; labels = @('code'); priority = 5 }
            [pscustomobject]@{ pattern = 'src/**';   labels = @('code'); priority = 99 }
            [pscustomobject]@{ pattern = '*.md';     labels = @('docs'); priority = 50 }
        )
        # 'code' should win priority 99 (from src/**), so it sorts before 'docs'@50.
        (Get-PRLabels -ChangedFiles @('src/app.ps1', 'README.md') -Rules $rules) -join ',' |
            Should -Be 'code,docs'
    }

    It 'treats a missing priority as 0' {
        $rules = @(
            [pscustomobject]@{ pattern = '*.a'; labels = @('alpha') }                 # no priority
            [pscustomobject]@{ pattern = '*.b'; labels = @('bravo'); priority = 1 }
        )
        (Get-PRLabels -ChangedFiles @('x.a', 'x.b') -Rules $rules) -join ',' |
            Should -Be 'bravo,alpha'
    }
}

Describe 'Import-LabelConfig' {
    It 'throws a clear error when the config file does not exist' {
        { Import-LabelConfig -Path 'TestDrive:/does-not-exist.json' } |
            Should -Throw -ExpectedMessage '*Config file not found*'
    }

    It 'throws a clear error when the JSON is malformed' {
        $p = Join-Path $TestDrive 'bad.json'
        Set-Content -Path $p -Value '{ this is not json '
        { Import-LabelConfig -Path $p } | Should -Throw -ExpectedMessage '*Invalid JSON*'
    }

    It "throws when the config has no 'rules' array" {
        $p = Join-Path $TestDrive 'norules.json'
        Set-Content -Path $p -Value '{ "something": 1 }'
        { Import-LabelConfig -Path $p } | Should -Throw -ExpectedMessage "*must contain a 'rules' array*"
    }

    It "throws when a rule is missing its 'pattern'" {
        $p = Join-Path $TestDrive 'nopattern.json'
        Set-Content -Path $p -Value '{ "rules": [ { "labels": ["x"] } ] }'
        { Import-LabelConfig -Path $p } | Should -Throw -ExpectedMessage "*rule 0*pattern*"
    }

    It "throws when a rule is missing its 'labels'" {
        $p = Join-Path $TestDrive 'nolabels.json'
        Set-Content -Path $p -Value '{ "rules": [ { "pattern": "a/**" } ] }'
        { Import-LabelConfig -Path $p } | Should -Throw -ExpectedMessage "*rule 0*labels*"
    }

    It 'loads a valid config and normalises its rules' {
        $p = Join-Path $TestDrive 'good.json'
        $json = @'
{
  "rules": [
    { "pattern": "docs/**", "labels": ["documentation"], "priority": 10 },
    { "pattern": "src/api/**", "labels": ["api", "backend"] }
  ]
}
'@
        Set-Content -Path $p -Value $json
        $rules = Import-LabelConfig -Path $p
        $rules.Count            | Should -Be 2
        $rules[0].pattern       | Should -Be 'docs/**'
        ($rules[0].labels -join ',') | Should -Be 'documentation'
        $rules[0].priority      | Should -Be 10
        # A rule without an explicit priority defaults to 0.
        $rules[1].priority      | Should -Be 0
        ($rules[1].labels -join ',') | Should -Be 'api,backend'
    }
}

Describe 'Get-ChangedFileList' {
    It 'throws a clear error when the file list does not exist' {
        { Get-ChangedFileList -Path 'TestDrive:/missing.txt' } |
            Should -Throw -ExpectedMessage '*Changed-files list not found*'
    }

    It 'reads one path per line, trimming blanks and # comments' {
        $p = Join-Path $TestDrive 'changed.txt'
        $content = @'
# this is a comment
docs/readme.md

  src/api/users.ps1
config.json
'@
        Set-Content -Path $p -Value $content
        $files = Get-ChangedFileList -Path $p
        ($files -join '|') | Should -Be 'docs/readme.md|src/api/users.ps1|config.json'
    }

    It 'returns an empty set for an empty file list' {
        $p = Join-Path $TestDrive 'empty.txt'
        Set-Content -Path $p -Value ''
        Get-ChangedFileList -Path $p | Should -BeNullOrEmpty
    }
}
