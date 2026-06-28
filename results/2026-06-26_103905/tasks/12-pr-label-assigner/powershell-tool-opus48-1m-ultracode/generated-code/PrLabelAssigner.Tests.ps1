#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester unit tests for the PR Label Assigner.

.DESCRIPTION
    These tests were written test-first (red/green/refactor TDD). Each
    `Describe` block corresponds to one unit of behaviour in the module:
        - glob pattern matching
        - rule loading from JSON config
        - label resolution (priorities, multiple labels, conflict "stop")
        - the high-level orchestration entry point

    Run with:  Invoke-Pester
#>

BeforeAll {
    # Import the module under test. -Force guarantees we always pick up the
    # latest version of the code while iterating during development.
    $ModulePath = Join-Path $PSScriptRoot 'PrLabelAssigner.psm1'
    Import-Module $ModulePath -Force
}

Describe 'Test-LabelGlob (glob pattern matching)' {

    Context 'literal and single-segment wildcards' {
        It 'matches an exact path' {
            Test-LabelGlob -Path 'README.md' -Pattern 'README.md' | Should -BeTrue
        }

        It 'does not match a different path' {
            Test-LabelGlob -Path 'README.md' -Pattern 'LICENSE' | Should -BeFalse
        }

        It "treats '*' as any characters within a single path segment" {
            Test-LabelGlob -Path 'app.js' -Pattern '*.js' | Should -BeTrue
        }

        It "does not let '*' cross a directory boundary (slash-containing pattern)" {
            # 'src/*.js' matches a file directly under src/ ...
            Test-LabelGlob -Path 'src/app.js'     -Pattern 'src/*.js' | Should -BeTrue
            # ... but '*' never spans '/', so a nested file does not match.
            Test-LabelGlob -Path 'src/sub/app.js' -Pattern 'src/*.js' | Should -BeFalse
        }

        It "treats '?' as exactly one non-slash character" {
            Test-LabelGlob -Path 'a.js' -Pattern '?.js' | Should -BeTrue
            Test-LabelGlob -Path 'ab.js' -Pattern '?.js' | Should -BeFalse
        }
    }

    Context "'**' crosses directory boundaries" {
        It "matches everything beneath a directory with 'dir/**'" {
            Test-LabelGlob -Path 'docs/intro.md' -Pattern 'docs/**' | Should -BeTrue
            Test-LabelGlob -Path 'docs/guide/setup.md' -Pattern 'docs/**' | Should -BeTrue
        }

        It "does not match a sibling directory with 'dir/**'" {
            Test-LabelGlob -Path 'src/intro.md' -Pattern 'docs/**' | Should -BeFalse
        }

        It "matches at any depth with a leading '**/'" {
            Test-LabelGlob -Path 'a.md' -Pattern '**/*.md' | Should -BeTrue
            Test-LabelGlob -Path 'docs/guide/a.md' -Pattern '**/*.md' | Should -BeTrue
        }
    }

    Context 'gitignore-style basename matching' {
        It 'matches a slash-free pattern against the file basename at any depth' {
            Test-LabelGlob -Path 'src/components/Button.test.tsx' -Pattern '*.test.*' | Should -BeTrue
            Test-LabelGlob -Path 'helper.test.js' -Pattern '*.test.*' | Should -BeTrue
        }

        It 'does not match when the basename does not fit the pattern' {
            Test-LabelGlob -Path 'src/components/Button.tsx' -Pattern '*.test.*' | Should -BeFalse
        }
    }

    Context 'input validation' {
        It 'throws a meaningful error on an empty pattern' {
            { Test-LabelGlob -Path 'a.js' -Pattern '' } |
                Should -Throw -ExpectedMessage '*Pattern*'
        }
    }
}

Describe 'Import-PrLabelRule (load rules from JSON config)' {

    BeforeEach {
        # A fresh, valid config for each test, written into Pester's TestDrive
        # (an auto-cleaned temp folder).
        $script:ConfigPath = Join-Path $TestDrive 'labels.json'
        @'
{
  "rules": [
    { "pattern": "docs/**",      "labels": ["documentation"],  "priority": 10 },
    { "pattern": "src/api/**",   "labels": ["api", "backend"], "priority": 30 },
    { "pattern": "package.json", "labels": "dependencies",     "priority": 50, "stop": true },
    { "pattern": "*.test.*",     "labels": ["tests"] }
  ]
}
'@ | Set-Content -Path $script:ConfigPath -Encoding utf8
    }

    It 'loads every rule from the file' {
        $rules = Import-PrLabelRule -Path $script:ConfigPath
        $rules.Count | Should -Be 4
    }

    It 'normalises a single string label into an array' {
        $rules = Import-PrLabelRule -Path $script:ConfigPath
        $depRule = $rules | Where-Object { $_.Pattern -eq 'package.json' }
        $depRule.Labels | Should -BeOfType [string]
        $depRule.Labels.Count | Should -Be 1
        $depRule.Labels[0] | Should -Be 'dependencies'
    }

    It 'preserves multiple labels' {
        $rules = Import-PrLabelRule -Path $script:ConfigPath
        $apiRule = $rules | Where-Object { $_.Pattern -eq 'src/api/**' }
        $apiRule.Labels | Should -Be @('api', 'backend')
    }

    It 'defaults Priority to 0 and Stop to $false when omitted' {
        $rules = Import-PrLabelRule -Path $script:ConfigPath
        $testRule = $rules | Where-Object { $_.Pattern -eq '*.test.*' }
        $testRule.Priority | Should -Be 0
        $testRule.Stop | Should -BeFalse
    }

    It 'reads the Stop flag when present' {
        $rules = Import-PrLabelRule -Path $script:ConfigPath
        $depRule = $rules | Where-Object { $_.Pattern -eq 'package.json' }
        $depRule.Stop | Should -BeTrue
    }

    It 'throws a meaningful error when the file does not exist' {
        { Import-PrLabelRule -Path (Join-Path $TestDrive 'nope.json') } |
            Should -Throw -ExpectedMessage '*not found*'
    }

    It 'throws a meaningful error on malformed JSON' {
        $bad = Join-Path $TestDrive 'bad.json'
        'this is { not json' | Set-Content -Path $bad -Encoding utf8
        { Import-PrLabelRule -Path $bad } |
            Should -Throw -ExpectedMessage '*Failed to parse*'
    }

    It 'throws when a rule is missing its pattern' {
        $bad = Join-Path $TestDrive 'nopattern.json'
        '{ "rules": [ { "labels": ["x"] } ] }' | Set-Content -Path $bad -Encoding utf8
        { Import-PrLabelRule -Path $bad } |
            Should -Throw -ExpectedMessage '*pattern*'
    }

    It 'throws when a rule is missing its labels' {
        $bad = Join-Path $TestDrive 'nolabels.json'
        '{ "rules": [ { "pattern": "docs/**" } ] }' | Set-Content -Path $bad -Encoding utf8
        { Import-PrLabelRule -Path $bad } |
            Should -Throw -ExpectedMessage '*label*'
    }
}

Describe 'Get-PrLabel (resolve labels for changed files)' {

    BeforeAll {
        # A representative rule set used across these tests. Built directly as
        # objects (no file I/O) to keep the resolution logic isolated.
        $script:Rules = @(
            [PSCustomObject]@{ Pattern = 'docs/**';    Labels = @('documentation'); Priority = 10; Stop = $false }
            [PSCustomObject]@{ Pattern = 'src/api/**'; Labels = @('api', 'backend'); Priority = 30; Stop = $false }
            [PSCustomObject]@{ Pattern = 'src/**';     Labels = @('source');        Priority = 20; Stop = $false }
            [PSCustomObject]@{ Pattern = '*.test.*';   Labels = @('tests');         Priority = 40; Stop = $false }
        )
    }

    It 'returns the single label of the single matching rule' {
        @(Get-PrLabel -ChangedFile @('docs/intro.md') -Rule $script:Rules) |
            Should -Be @('documentation')
    }

    It 'returns an empty set when nothing matches' {
        @(Get-PrLabel -ChangedFile @('LICENSE') -Rule $script:Rules).Count |
            Should -Be 0
    }

    It 'returns an empty set for an empty file list' {
        @(Get-PrLabel -ChangedFile @() -Rule $script:Rules).Count |
            Should -Be 0
    }

    It 'emits all labels of a multi-label rule' {
        # src/api/users.js matches BOTH src/api/** (api,backend @30) and
        # src/** (source @20); result ordered by priority desc, then alpha.
        @(Get-PrLabel -ChangedFile @('src/api/users.js') -Rule $script:Rules) |
            Should -Be @('api', 'backend', 'source')
    }

    It 'deduplicates a label contributed by several files' {
        @(Get-PrLabel -ChangedFile @('docs/a.md', 'docs/b.md', 'docs/c/d.md') -Rule $script:Rules) |
            Should -Be @('documentation')
    }

    It 'orders the final set by descending priority then alphabetically' {
        # tests @40, source @20, documentation @10
        @(Get-PrLabel -ChangedFile @('docs/x.md', 'src/util.js', 'src/a.test.js') -Rule $script:Rules) |
            Should -Be @('tests', 'source', 'documentation')
    }

    Context 'conflict resolution via the Stop flag' {
        BeforeAll {
            $script:StopRules = @(
                [PSCustomObject]@{ Pattern = 'package.json'; Labels = @('dependencies'); Priority = 50; Stop = $true }
                [PSCustomObject]@{ Pattern = '**/*.json';    Labels = @('config');       Priority = 10; Stop = $false }
            )
        }

        It 'stops lower-priority rules from applying to the same file' {
            # package.json matches the stop-rule first; the lower-priority
            # **/*.json (config) rule is skipped for that file.
            @(Get-PrLabel -ChangedFile @('package.json') -Rule $script:StopRules) |
                Should -Be @('dependencies')
        }

        It 'still applies the lower-priority rule to other files' {
            @(Get-PrLabel -ChangedFile @('settings.json') -Rule $script:StopRules) |
                Should -Be @('config')
        }

        It 'combines results across files (stop is per-file, union is global)' {
            @(Get-PrLabel -ChangedFile @('package.json', 'settings.json') -Rule $script:StopRules) |
                Should -Be @('dependencies', 'config')
        }
    }
}

Describe 'Import-PrChangedFile (read a mock changed-file list)' {

    It 'reads one path per line, trimming whitespace' {
        $f = Join-Path $TestDrive 'changed.txt'
        "docs/a.md`n  src/app.js  `nREADME.md" | Set-Content -Path $f -Encoding utf8
        Import-PrChangedFile -Path $f | Should -Be @('docs/a.md', 'src/app.js', 'README.md')
    }

    It 'skips blank lines and # comments' {
        $f = Join-Path $TestDrive 'changed.txt'
        "# the PR files`n`ndocs/a.md`n   `n# trailing comment`nsrc/app.js" |
            Set-Content -Path $f -Encoding utf8
        Import-PrChangedFile -Path $f | Should -Be @('docs/a.md', 'src/app.js')
    }

    It 'returns an empty array for an empty file' {
        $f = Join-Path $TestDrive 'empty.txt'
        '' | Set-Content -Path $f -Encoding utf8
        @(Import-PrChangedFile -Path $f).Count | Should -Be 0
    }

    It 'throws a meaningful error when the file does not exist' {
        { Import-PrChangedFile -Path (Join-Path $TestDrive 'missing.txt') } |
            Should -Throw -ExpectedMessage '*not found*'
    }
}

Describe 'Resolve-PrLabel (end-to-end orchestration)' {

    BeforeEach {
        $script:Config = Join-Path $TestDrive 'labels.json'
        @'
{
  "rules": [
    { "pattern": "docs/**",      "labels": ["documentation"],  "priority": 10 },
    { "pattern": "src/api/**",   "labels": ["api", "backend"], "priority": 30 },
    { "pattern": "src/**",       "labels": ["source"],         "priority": 20 },
    { "pattern": "*.test.*",     "labels": ["tests"],          "priority": 40 },
    { "pattern": "package.json", "labels": ["dependencies"],   "priority": 50, "stop": true },
    { "pattern": "**/*.json",    "labels": ["config"],         "priority": 5 }
  ]
}
'@ | Set-Content -Path $script:Config -Encoding utf8

        $script:Changed = Join-Path $TestDrive 'changed.txt'
    }

    It 'resolves labels from a changed-file list and a config file' {
        "docs/intro.md`nsrc/api/users.js`nsrc/helpers/util.test.js" |
            Set-Content -Path $script:Changed -Encoding utf8
        # tests@40, api@30, backend@30, source@20, documentation@10
        @(Resolve-PrLabel -ChangedFilesPath $script:Changed -ConfigPath $script:Config) |
            Should -Be @('tests', 'api', 'backend', 'source', 'documentation')
    }

    It 'honours the stop flag end-to-end' {
        "package.json`nconfig/app.json" | Set-Content -Path $script:Changed -Encoding utf8
        # package.json -> dependencies (stop swallows config); app.json -> config
        @(Resolve-PrLabel -ChangedFilesPath $script:Changed -ConfigPath $script:Config) |
            Should -Be @('dependencies', 'config')
    }

    It 'returns an empty set when no file matches any rule' {
        "LICENSE`n.gitignore" | Set-Content -Path $script:Changed -Encoding utf8
        @(Resolve-PrLabel -ChangedFilesPath $script:Changed -ConfigPath $script:Config).Count |
            Should -Be 0
    }
}
