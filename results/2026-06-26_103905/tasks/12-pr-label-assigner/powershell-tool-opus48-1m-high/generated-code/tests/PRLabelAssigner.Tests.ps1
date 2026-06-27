# Unit tests for the PRLabelAssigner module, written red/green TDD-style.
#
# Run with:  Invoke-Pester -Path ./tests/PRLabelAssigner.Tests.ps1

BeforeAll {
    # Resolve the module relative to this test file so the suite is location-independent.
    $modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'PRLabelAssigner.psm1'
    Import-Module $modulePath -Force
}

Describe 'ConvertTo-LabelRegex' {
    It 'turns a literal dot into an escaped dot, not a wildcard' {
        # 'a.b' must match only 'a.b', never 'axb'.
        $regex = ConvertTo-LabelRegex -Pattern 'a.b'
        'a.b' | Should -Match $regex
        'axb' | Should -Not -Match $regex
    }
}

Describe 'Test-PathPattern' {
    Context 'patterns containing a slash match against the full path' {
        It 'matches a file directly under a "**" directory pattern' {
            Test-PathPattern -Path 'docs/readme.md' -Pattern 'docs/**' | Should -BeTrue
        }
        It 'matches a deeply nested file under a "**" directory pattern' {
            Test-PathPattern -Path 'docs/guide/intro.md' -Pattern 'docs/**' | Should -BeTrue
        }
        It 'does not match a path outside the directory' {
            Test-PathPattern -Path 'src/app.js' -Pattern 'docs/**' | Should -BeFalse
        }
        It 'honours nested directory patterns like src/api/**' {
            Test-PathPattern -Path 'src/api/users.js' -Pattern 'src/api/**' | Should -BeTrue
            Test-PathPattern -Path 'src/web/users.js' -Pattern 'src/api/**' | Should -BeFalse
        }
        It 'treats a single * as not crossing a path separator' {
            Test-PathPattern -Path 'src/api/users.js' -Pattern 'src/*' | Should -BeFalse
            Test-PathPattern -Path 'src/users.js'     -Pattern 'src/*' | Should -BeTrue
        }
    }

    Context 'patterns without a slash match against the file basename' {
        It 'matches a test file anywhere in the tree' {
            Test-PathPattern -Path 'src/api/users.test.js' -Pattern '*.test.*' | Should -BeTrue
            Test-PathPattern -Path 'users.test.js'         -Pattern '*.test.*' | Should -BeTrue
        }
        It 'does not match a non-test file' {
            Test-PathPattern -Path 'src/api/users.js' -Pattern '*.test.*' | Should -BeFalse
        }
    }
}

Describe 'Get-PRLabels' {
    BeforeAll {
        # A representative rule set used across the examples below. Priority is
        # higher = more important; it drives the order of the final label set.
        $script:rules = @(
            @{ pattern = 'docs/**';    labels = @('documentation'); priority = 10 }
            @{ pattern = 'src/api/**'; labels = @('api', 'backend'); priority = 30 }
            @{ pattern = '*.test.*';   labels = @('tests');         priority = 20 }
        )
    }

    It 'returns an empty array when no files are supplied' {
        $result = Get-PRLabels -ChangedFiles @() -Rules $script:rules
        @($result).Count | Should -Be 0
    }

    It 'returns an empty array when no rule matches any file' {
        $result = Get-PRLabels -ChangedFiles @('LICENSE', 'Makefile') -Rules $script:rules
        @($result).Count | Should -Be 0
    }

    It 'assigns the documentation label to a docs file' {
        Get-PRLabels -ChangedFiles @('docs/readme.md') -Rules $script:rules |
            Should -Be @('documentation')
    }

    It 'assigns multiple labels from a single matching rule' {
        # src/api/** carries both 'api' and 'backend'.
        $result = Get-PRLabels -ChangedFiles @('src/api/users.js') -Rules $script:rules
        $result | Should -Contain 'api'
        $result | Should -Contain 'backend'
        @($result).Count | Should -Be 2
    }

    It 'accumulates labels across multiple files and de-duplicates them' {
        $files = @('docs/readme.md', 'src/api/users.js', 'src/api/orders.js')
        $result = Get-PRLabels -ChangedFiles $files -Rules $script:rules
        # 'api'/'backend' appear once despite two matching files.
        @($result).Count | Should -Be 3
        ($result | Sort-Object) | Should -Be @('api', 'backend', 'documentation')
    }

    It 'applies multiple labels to a single file when several rules match (multiple labels per file)' {
        # users.test.js lives under src/api AND is a test file.
        $result = Get-PRLabels -ChangedFiles @('src/api/users.test.js') -Rules $script:rules
        ($result | Sort-Object) | Should -Be @('api', 'backend', 'tests')
    }

    It 'orders the final label set by descending rule priority, then name' {
        # priorities: api/backend=30, tests=20, documentation=10.
        $files = @('docs/readme.md', 'src/api/users.test.js')
        $result = Get-PRLabels -ChangedFiles $files -Rules $script:rules
        $result | Should -Be @('api', 'backend', 'tests', 'documentation')
    }

    It 'lets a higher-priority rule win when labels conflict in exclusive mode' {
        # Two rules assign different labels to the same file; in -FirstMatchWins
        # mode only the highest-priority matching rule contributes.
        $conflict = @(
            @{ pattern = 'src/**';     labels = @('source');   priority = 5 }
            @{ pattern = 'src/api/**'; labels = @('api');      priority = 50 }
        )
        $result = Get-PRLabels -ChangedFiles @('src/api/users.js') -Rules $conflict -FirstMatchWins
        $result | Should -Be @('api')
    }

    It 'throws a meaningful error for a rule missing its pattern' {
        $bad = @(@{ labels = @('x') })
        { Get-PRLabels -ChangedFiles @('a') -Rules $bad } |
            Should -Throw -ExpectedMessage "*'pattern' is required*"
    }

    It 'throws a meaningful error for a rule missing its labels' {
        $bad = @(@{ pattern = 'docs/**' })
        { Get-PRLabels -ChangedFiles @('a') -Rules $bad } |
            Should -Throw -ExpectedMessage "*'labels' is required*"
    }
}

Describe 'Import-LabelRules' {
    BeforeAll {
        $script:fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("plr-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:fixtureRoot -Force | Out-Null
    }
    AfterAll {
        if (Test-Path $script:fixtureRoot) { Remove-Item $script:fixtureRoot -Recurse -Force }
    }

    It 'loads a valid JSON config into usable rules' {
        $path = Join-Path $script:fixtureRoot 'good.json'
        @'
{
  "rules": [
    { "pattern": "docs/**", "labels": ["documentation"], "priority": 10 },
    { "pattern": "*.test.*", "labels": ["tests"], "priority": 20 }
  ]
}
'@ | Set-Content -Path $path -Encoding utf8

        $rules = Import-LabelRules -Path $path
        @($rules).Count | Should -Be 2
        # The loaded rules drive Get-PRLabels end to end.
        Get-PRLabels -ChangedFiles @('docs/x.md', 'a.test.js') -Rules $rules |
            Should -Be @('tests', 'documentation')
    }

    It 'also accepts a bare top-level JSON array of rules' {
        $path = Join-Path $script:fixtureRoot 'array.json'
        '[{ "pattern": "docs/**", "labels": "documentation" }]' | Set-Content -Path $path -Encoding utf8
        $rules = Import-LabelRules -Path $path
        @($rules).Count | Should -Be 1
    }

    It 'throws a clear error when the file does not exist' {
        { Import-LabelRules -Path (Join-Path $script:fixtureRoot 'missing.json') } |
            Should -Throw -ExpectedMessage '*not found*'
    }

    It 'throws a clear error when the file contains invalid JSON' {
        $path = Join-Path $script:fixtureRoot 'broken.json'
        '{ this is not json' | Set-Content -Path $path -Encoding utf8
        { Import-LabelRules -Path $path } | Should -Throw -ExpectedMessage '*Failed to parse*'
    }
}
