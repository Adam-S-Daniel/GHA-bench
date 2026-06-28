#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
    Unit tests for the PR Label Assigner module.

    Developed test-first (red/green TDD): each Describe block was written and
    run to failure BEFORE the corresponding function existed, then the minimum
    implementation was added to make it pass.

    These tests exercise the building blocks directly. End-to-end validation of
    the same behaviour through the real GitHub Actions pipeline lives in
    tests/Act.Workflow.Tests.ps1 (driven by `act`).
#>

BeforeAll {
    # Import the module under test from the repo root (one level up from tests/).
    $modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'PRLabelAssigner.psm1'
    Import-Module $modulePath -Force
}

Describe 'ConvertTo-LabelGlobRegex' {

    It 'turns a directory-prefix glob (docs/**) into an anchored regex that matches nested files' {
        $rx = ConvertTo-LabelGlobRegex -Pattern 'docs/**'
        'docs/intro.md'        | Should -Match $rx
        'docs/guide/setup.md'  | Should -Match $rx
        'src/app.ps1'          | Should -Not -Match $rx
    }

    It 'treats a leading **/ as zero-or-more directory segments' {
        $rx = ConvertTo-LabelGlobRegex -Pattern '**/*.md'
        'README.md'        | Should -Match $rx   # zero leading segments
        'docs/a/b/note.md' | Should -Match $rx   # several leading segments
        'note.txt'         | Should -Not -Match $rx
    }

    It 'does not let a single * cross a directory boundary' {
        $rx = ConvertTo-LabelGlobRegex -Pattern 'src/*.ps1'
        'src/app.ps1'          | Should -Match $rx
        'src/sub/app.ps1'      | Should -Not -Match $rx
    }

    It 'escapes regex metacharacters that appear in literal path segments' {
        # The '.' must be literal, not "any char".
        $rx = ConvertTo-LabelGlobRegex -Pattern 'a.b/c'
        'a.b/c' | Should -Match $rx
        'axb/c' | Should -Not -Match $rx
    }
}

Describe 'Test-LabelGlobMatch' {

    It 'matches a slash-less pattern against the file basename at any depth (gitignore-style)' {
        # The task example "*.test.*" should catch test files anywhere.
        Test-LabelGlobMatch -Path 'src/api/users.test.ps1' -Pattern '*.test.*' | Should -BeTrue
        Test-LabelGlobMatch -Path 'users.test.ps1'         -Pattern '*.test.*' | Should -BeTrue
        Test-LabelGlobMatch -Path 'src/api/users.ps1'      -Pattern '*.test.*' | Should -BeFalse
    }

    It 'matches a slash-bearing pattern against the full path' {
        Test-LabelGlobMatch -Path 'src/api/v1/users.ps1' -Pattern 'src/api/**' | Should -BeTrue
        Test-LabelGlobMatch -Path 'src/web/index.html'   -Pattern 'src/api/**' | Should -BeFalse
    }

    It 'normalises backslashes so Windows-style paths still match' {
        Test-LabelGlobMatch -Path 'docs\guide\setup.md' -Pattern 'docs/**' | Should -BeTrue
    }

    It 'is case-sensitive (paths in git are case-sensitive)' {
        Test-LabelGlobMatch -Path 'DOCS/intro.md' -Pattern 'docs/**' | Should -BeFalse
    }
}

Describe 'Get-PRLabel - matching and union' {

    It 'returns nothing for an empty file list (an @()-wrapped call yields a 0-length array)' {
        $rules = @( @{ Pattern = 'docs/**'; Labels = 'documentation' } )
        Get-PRLabel -ChangedFiles @() -Rules $rules | Should -BeNullOrEmpty
        # Documented caller contract: wrap in @() for a guaranteed array.
        $wrapped = @(Get-PRLabel -ChangedFiles @() -Rules $rules)
        $wrapped.Count | Should -Be 0
        ($wrapped -is [array]) | Should -BeTrue
    }

    It 'returns an empty array when nothing matches' {
        $rules = @( @{ Pattern = 'docs/**'; Labels = 'documentation' } )
        Get-PRLabel -ChangedFiles @('src/app.ps1') -Rules $rules | Should -BeNullOrEmpty
    }

    It 'applies a single label when one rule matches one file' {
        $rules = @( @{ Pattern = 'docs/**'; Labels = 'documentation' } )
        $result = Get-PRLabel -ChangedFiles @('docs/intro.md') -Rules $rules
        ($result -join ',') | Should -BeExactly 'documentation'
    }

    It 'applies multiple labels from a single rule that lists several labels' {
        $rules = @( @{ Pattern = 'src/api/**'; Labels = @('api', 'backend'); Priority = 5 } )
        $result = Get-PRLabel -ChangedFiles @('src/api/users.ps1') -Rules $rules
        ($result -join ',') | Should -BeExactly 'api,backend'
    }

    It 'unions labels from several matching rules across several files' {
        $rules = @(
            @{ Pattern = 'docs/**';     Labels = 'documentation'; Priority = 10 }
            @{ Pattern = '*.test.*';    Labels = 'tests';         Priority = 5  }
        )
        $files = @('docs/intro.md', 'src/api/users.test.ps1')
        $result = Get-PRLabel -ChangedFiles $files -Rules $rules
        ($result -join ',') | Should -BeExactly 'documentation,tests'
    }

    It 'de-duplicates a label contributed by multiple rules/files' {
        $rules = @(
            @{ Pattern = 'docs/**';  Labels = 'documentation'; Priority = 10 }
            @{ Pattern = '**/*.md';  Labels = 'documentation'; Priority = 10 }
        )
        $files = @('docs/intro.md', 'README.md')
        $result = Get-PRLabel -ChangedFiles $files -Rules $rules
        ($result -join ',') | Should -BeExactly 'documentation'
    }

    It 'supports an array of patterns on a single rule (OR semantics)' {
        $rules = @( @{ Pattern = @('src/api/**', 'api/**'); Labels = 'api' } )
        ((Get-PRLabel -ChangedFiles @('api/v1/users.ps1') -Rules $rules) -join ',') | Should -BeExactly 'api'
        ((Get-PRLabel -ChangedFiles @('src/api/users.ps1') -Rules $rules) -join ',') | Should -BeExactly 'api'
    }
}

Describe 'Get-PRLabel - priority ordering' {

    It 'orders the output by descending priority' {
        $rules = @(
            @{ Pattern = 'docs/**';   Labels = 'documentation'; Priority = 1  }
            @{ Pattern = 'src/api/**'; Labels = 'api';          Priority = 50 }
            @{ Pattern = '*.test.*';  Labels = 'tests';         Priority = 30 }
        )
        $files = @('docs/x.md', 'src/api/users.ps1', 'src/api/users.test.ps1')
        $result = Get-PRLabel -ChangedFiles $files -Rules $rules
        ($result -join ',') | Should -BeExactly 'api,tests,documentation'
    }

    It 'breaks priority ties by first declaration order (stable, deterministic)' {
        $rules = @(
            @{ Pattern = 'a/**'; Labels = 'first';  Priority = 7 }
            @{ Pattern = 'b/**'; Labels = 'second'; Priority = 7 }
        )
        # Files are listed out of order on purpose; rule declaration order wins.
        $result = Get-PRLabel -ChangedFiles @('b/x', 'a/y') -Rules $rules
        ($result -join ',') | Should -BeExactly 'first,second'
    }

    It 'uses the highest contributing priority when a label comes from several rules' {
        $rules = @(
            @{ Pattern = '**/*.md'; Labels = 'documentation'; Priority = 1   }
            @{ Pattern = 'guide/**'; Labels = 'guide';        Priority = 5   }
            @{ Pattern = 'docs/**'; Labels = 'documentation'; Priority = 100 }
        )
        # documentation effectively has priority 100, so it sorts first.
        $result = Get-PRLabel -ChangedFiles @('docs/intro.md', 'guide/start.md') -Rules $rules
        ($result -join ',') | Should -BeExactly 'documentation,guide'
    }
}

Describe 'Get-PRLabel - conflict resolution via groups' {

    It 'keeps only the highest-priority label within a mutual-exclusion group' {
        # area/core and area/api conflict; the higher-priority rule wins.
        $rules = @(
            @{ Pattern = 'src/**';     Labels = 'area/core'; Priority = 5; Group = 'area' }
            @{ Pattern = 'src/api/**'; Labels = 'area/api';  Priority = 9; Group = 'area' }
        )
        $result = Get-PRLabel -ChangedFiles @('src/api/users.ps1') -Rules $rules
        ($result -join ',') | Should -BeExactly 'area/api'
    }

    It 'keeps the lower group member when the higher-priority rule does not match' {
        $rules = @(
            @{ Pattern = 'src/**';     Labels = 'area/core'; Priority = 5; Group = 'area' }
            @{ Pattern = 'src/api/**'; Labels = 'area/api';  Priority = 9; Group = 'area' }
        )
        $result = Get-PRLabel -ChangedFiles @('src/db/conn.ps1') -Rules $rules
        ($result -join ',') | Should -BeExactly 'area/core'
    }

    It 'resolves groups independently of additive (ungrouped) labels' {
        $rules = @(
            @{ Pattern = 'src/api/**'; Labels = @('api', 'backend'); Priority = 50 }
            @{ Pattern = 'src/**';     Labels = 'area/core';         Priority = 5;  Group = 'area' }
            @{ Pattern = 'src/api/**'; Labels = 'area/api';          Priority = 9;  Group = 'area' }
        )
        # api/backend are additive (kept); area group resolves to area/api.
        $result = Get-PRLabel -ChangedFiles @('src/api/users.ps1') -Rules $rules
        ($result -join ',') | Should -BeExactly 'api,backend,area/api'
    }
}

Describe 'Import-LabelRule - loading and normalisation' {

    It 'loads rules from a JSON config file and feeds them into Get-PRLabel' {
        $json = @'
{
  "rules": [
    { "pattern": "docs/**", "labels": ["documentation"], "priority": 10 },
    { "pattern": "src/api/**", "labels": ["api", "backend"], "priority": 50 }
  ]
}
'@
        $path = Join-Path $TestDrive 'rules.json'
        Set-Content -LiteralPath $path -Value $json -Encoding utf8

        $rules = Import-LabelRule -Path $path
        $rules.Count | Should -Be 2

        $result = Get-PRLabel -ChangedFiles @('src/api/users.ps1', 'docs/x.md') -Rules $rules
        ($result -join ',') | Should -BeExactly 'api,backend,documentation'
    }

    It 'normalises a single (non-array) pattern and label into arrays' {
        $json = '{ "rules": [ { "pattern": "*.test.*", "labels": "tests" } ] }'
        $path = Join-Path $TestDrive 'single.json'
        Set-Content -LiteralPath $path -Value $json -Encoding utf8

        $rules = Import-LabelRule -Path $path
        , $rules[0].Pattern | Should -BeOfType [System.Array]
        , $rules[0].Labels  | Should -BeOfType [System.Array]
        $rules[0].Pattern[0] | Should -BeExactly '*.test.*'
        $rules[0].Labels[0]  | Should -BeExactly 'tests'
    }

    It 'defaults priority to 0 and group to $null when omitted' {
        $json = '{ "rules": [ { "pattern": "docs/**", "labels": "documentation" } ] }'
        $path = Join-Path $TestDrive 'defaults.json'
        Set-Content -LiteralPath $path -Value $json -Encoding utf8

        $rules = Import-LabelRule -Path $path
        $rules[0].Priority | Should -Be 0
        $rules[0].Group    | Should -BeNullOrEmpty
    }

    It 'preserves priority and group values from JSON' {
        $json = '{ "rules": [ { "pattern": "src/api/**", "labels": "area/api", "priority": 9, "group": "area" } ] }'
        $path = Join-Path $TestDrive 'group.json'
        Set-Content -LiteralPath $path -Value $json -Encoding utf8

        $rules = Import-LabelRule -Path $path
        $rules[0].Priority | Should -Be 9
        $rules[0].Group    | Should -BeExactly 'area'
    }
}

Describe 'Import-LabelRule - error handling' {

    It 'throws a clear error when the config file does not exist' {
        $missing = Join-Path $TestDrive 'nope.json'
        { Import-LabelRule -Path $missing } |
            Should -Throw -ExpectedMessage '*not found*'
    }

    It 'throws a clear error when the file is not valid JSON' {
        $path = Join-Path $TestDrive 'bad.json'
        Set-Content -LiteralPath $path -Value 'this is { not json' -Encoding utf8
        { Import-LabelRule -Path $path } |
            Should -Throw -ExpectedMessage '*parse*'
    }

    It 'throws when the config has no rules array' {
        $path = Join-Path $TestDrive 'norules.json'
        Set-Content -LiteralPath $path -Value '{ "something": [] }' -Encoding utf8
        { Import-LabelRule -Path $path } |
            Should -Throw -ExpectedMessage "*'rules'*"
    }

    It 'throws when a rule is missing its pattern' {
        $path = Join-Path $TestDrive 'nopattern.json'
        Set-Content -LiteralPath $path -Value '{ "rules": [ { "labels": "x" } ] }' -Encoding utf8
        { Import-LabelRule -Path $path } |
            Should -Throw -ExpectedMessage '*pattern*'
    }

    It 'throws when a rule is missing its labels' {
        $path = Join-Path $TestDrive 'nolabels.json'
        Set-Content -LiteralPath $path -Value '{ "rules": [ { "pattern": "docs/**" } ] }' -Encoding utf8
        { Import-LabelRule -Path $path } |
            Should -Throw -ExpectedMessage '*labels*'
    }
}
