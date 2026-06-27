# LabelAssigner.Tests.ps1
# Unit tests (Pester 5) for the PR label-assigner core logic.
# Built incrementally via red/green TDD.

BeforeAll {
    # Import the module under test. $PSScriptRoot is the tests/ folder.
    $ModulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'src/LabelAssigner.psm1'
    Import-Module $ModulePath -Force
}

Describe 'Test-GlobMatch' {
    It 'matches a literal file path exactly' {
        Test-GlobMatch -Path 'README.md' -Pattern 'README.md' | Should -BeTrue
    }

    It 'does not match a different literal path' {
        Test-GlobMatch -Path 'README.md' -Pattern 'LICENSE' | Should -BeFalse
    }

    It "treats '*' as matching within a single path segment" {
        Test-GlobMatch -Path 'src/app.ts' -Pattern 'src/*.ts' | Should -BeTrue
    }

    It "does not let '*' cross a directory separator" {
        Test-GlobMatch -Path 'src/api/app.ts' -Pattern 'src/*.ts' | Should -BeFalse
    }

    It "treats '**' as matching across directory separators" {
        Test-GlobMatch -Path 'docs/guide/intro.md' -Pattern 'docs/**' | Should -BeTrue
    }

    It "matches the 'docs/**' directory prefix for nested files" {
        Test-GlobMatch -Path 'src/api/v1/users.ts' -Pattern 'src/api/**' | Should -BeTrue
    }

    It "treats '?' as a single non-separator character" {
        Test-GlobMatch -Path 'v1.ts' -Pattern 'v?.ts'  | Should -BeTrue
        Test-GlobMatch -Path 'v10.ts' -Pattern 'v?.ts' | Should -BeFalse
    }

    It 'matches a slash-less pattern against the file basename at any depth' {
        Test-GlobMatch -Path 'src/components/Button.test.tsx' -Pattern '*.test.*' | Should -BeTrue
        Test-GlobMatch -Path 'Button.test.tsx' -Pattern '*.test.*'                | Should -BeTrue
    }

    It 'escapes regex metacharacters that are not glob wildcards' {
        # The '.' in the pattern must be literal, not "any char".
        Test-GlobMatch -Path 'aXjs' -Pattern '*.js' | Should -BeFalse
    }

    It 'matches a leading **/ as zero or more directories' {
        Test-GlobMatch -Path 'a/b/c.png' -Pattern '**/*.png' | Should -BeTrue
        Test-GlobMatch -Path 'c.png' -Pattern '**/*.png'     | Should -BeTrue
    }
}

Describe 'ConvertTo-GlobRegex' {
    It 'anchors the produced pattern at both ends' {
        $rx = ConvertTo-GlobRegex -Pattern 'docs/**'
        $rx | Should -Match '^\^'
        $rx | Should -Match '\$$'
    }
}

Describe 'Get-FileLabels' {
    BeforeAll {
        # A small rule set exercising multi-label, priority and exclusive groups.
        $script:Rules = @(
            [pscustomobject]@{ pattern = 'docs/**';     labels = @('documentation'); priority = 10; exclusiveGroup = $null }
            [pscustomobject]@{ pattern = 'src/api/**';   labels = @('api', 'backend'); priority = 30; exclusiveGroup = 'area' }
            [pscustomobject]@{ pattern = 'src/**';       labels = @('backend');        priority = 20; exclusiveGroup = 'area' }
            [pscustomobject]@{ pattern = '*.test.*';     labels = @('tests');          priority = 40; exclusiveGroup = $null }
        )
    }

    It 'returns the label for a single matching rule' {
        Get-FileLabels -Path 'docs/intro.md' -Rules $script:Rules |
            Should -Be @('documentation')
    }

    It 'returns no labels when nothing matches' {
        Get-FileLabels -Path 'Makefile' -Rules $script:Rules |
            Should -BeNullOrEmpty
    }

    It 'returns multiple labels from a single rule' {
        # src/api/app.ts matches src/api/** (api, backend) and src/** (backend).
        $labels = Get-FileLabels -Path 'src/api/app.ts' -Rules $script:Rules
        $labels | Should -Contain 'api'
        $labels | Should -Contain 'backend'
    }

    It 'accumulates labels across rules in different exclusive groups' {
        # A test file under src/api should get area=api/backend AND tests.
        $labels = Get-FileLabels -Path 'src/api/app.test.ts' -Rules $script:Rules
        $labels | Should -Contain 'api'
        $labels | Should -Contain 'tests'
    }

    It 'resolves an exclusive-group conflict by highest priority' {
        # src/web/app.ts matches only src/** within group "area" (priority 20).
        Get-FileLabels -Path 'src/web/app.ts' -Rules $script:Rules |
            Should -Be @('backend')
    }

    It 'lets the higher-priority rule win inside the same exclusive group' {
        # src/api/app.ts matches both src/api/** (p30) and src/** (p20) in
        # group "area"; only the priority-30 rule's labels are kept.
        $labels = Get-FileLabels -Path 'src/api/app.ts' -Rules $script:Rules
        # Both api and backend come from the winning rule; nothing extra.
        ($labels | Sort-Object) | Should -Be @('api', 'backend')
    }
}

Describe 'Get-PrLabels' {
    BeforeAll {
        $script:Rules = @(
            [pscustomobject]@{ pattern = 'docs/**';   labels = @('documentation'); priority = 10; exclusiveGroup = $null }
            [pscustomobject]@{ pattern = 'src/api/**'; labels = @('api');           priority = 30; exclusiveGroup = $null }
            [pscustomobject]@{ pattern = '*.test.*';   labels = @('tests');         priority = 40; exclusiveGroup = $null }
        )
    }

    It 'returns the union of labels across all changed files' {
        $files = @('docs/readme.md', 'src/api/users.ts')
        $labels = Get-PrLabels -ChangedFiles $files -Rules $script:Rules
        $labels | Should -Contain 'documentation'
        $labels | Should -Contain 'api'
    }

    It 'de-duplicates labels that come from multiple files' {
        $files = @('src/api/users.ts', 'src/api/orders.ts')
        Get-PrLabels -ChangedFiles $files -Rules $script:Rules |
            Should -Be @('api')
    }

    It 'orders the final labels by descending rule priority' {
        # documentation(10), api(30), tests(40) -> tests, api, documentation
        $files = @('docs/x.md', 'src/api/y.ts', 'a.test.js')
        Get-PrLabels -ChangedFiles $files -Rules $script:Rules |
            Should -Be @('tests', 'api', 'documentation')
    }

    It 'returns an empty array when no file matches any rule' {
        $labels = Get-PrLabels -ChangedFiles @('Makefile', 'LICENSE') -Rules $script:Rules
        $labels | Should -BeNullOrEmpty
    }

    It 'returns an empty array for an empty changed-file list' {
        Get-PrLabels -ChangedFiles @() -Rules $script:Rules |
            Should -BeNullOrEmpty
    }
}

Describe 'Get-LabelRules' {
    BeforeAll {
        $script:TmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("rules_" + [System.Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:TmpDir -Force | Out-Null
    }
    AfterAll {
        if (Test-Path $script:TmpDir) { Remove-Item $script:TmpDir -Recurse -Force }
    }

    It 'loads a valid rules file and returns normalized rule objects' {
        $path = Join-Path $script:TmpDir 'valid.json'
        @'
{
  "rules": [
    { "pattern": "docs/**", "labels": ["documentation"], "priority": 10 },
    { "pattern": "*.test.*", "labels": ["tests"] }
  ]
}
'@ | Set-Content -Path $path -Encoding utf8

        $rules = Get-LabelRules -Path $path
        $rules.Count | Should -Be 2
        $rules[0].pattern | Should -Be 'docs/**'
        $rules[0].labels  | Should -Be @('documentation')
    }

    It 'defaults a missing priority to 0' {
        $path = Join-Path $script:TmpDir 'defaults.json'
        '{ "rules": [ { "pattern": "*.md", "labels": ["docs"] } ] }' |
            Set-Content -Path $path -Encoding utf8
        (Get-LabelRules -Path $path)[0].priority | Should -Be 0
    }

    It 'throws a meaningful error when the file does not exist' {
        { Get-LabelRules -Path (Join-Path $script:TmpDir 'nope.json') } |
            Should -Throw '*not found*'
    }

    It 'throws a meaningful error for invalid JSON' {
        $path = Join-Path $script:TmpDir 'bad.json'
        '{ not valid json' | Set-Content -Path $path -Encoding utf8
        { Get-LabelRules -Path $path } | Should -Throw '*Failed to parse*'
    }

    It 'throws when a rule is missing its pattern' {
        $path = Join-Path $script:TmpDir 'nopattern.json'
        '{ "rules": [ { "labels": ["x"] } ] }' | Set-Content -Path $path -Encoding utf8
        { Get-LabelRules -Path $path } | Should -Throw "*'pattern'*"
    }

    It 'throws when a rule is missing its labels' {
        $path = Join-Path $script:TmpDir 'nolabels.json'
        '{ "rules": [ { "pattern": "*.md" } ] }' | Set-Content -Path $path -Encoding utf8
        { Get-LabelRules -Path $path } | Should -Throw "*'labels'*"
    }

    It 'throws when the top-level rules array is absent' {
        $path = Join-Path $script:TmpDir 'norules.json'
        '{ "something": 1 }' | Set-Content -Path $path -Encoding utf8
        { Get-LabelRules -Path $path } | Should -Throw "*'rules'*"
    }
}

Describe 'Invoke-LabelAssigner' {
    BeforeAll {
        $script:TmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("inv_" + [System.Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:TmpDir -Force | Out-Null

        $script:RulesFile = Join-Path $script:TmpDir 'rules.json'
        @'
{
  "rules": [
    { "pattern": "docs/**",   "labels": ["documentation"], "priority": 10 },
    { "pattern": "src/api/**", "labels": ["api"],           "priority": 30 },
    { "pattern": "*.test.*",   "labels": ["tests"],         "priority": 40 }
  ]
}
'@ | Set-Content -Path $script:RulesFile -Encoding utf8
    }
    AfterAll {
        if (Test-Path $script:TmpDir) { Remove-Item $script:TmpDir -Recurse -Force }
    }

    It 'reads a changed-files list file and returns the ordered labels' {
        $listFile = Join-Path $script:TmpDir 'changed.txt'
        "docs/intro.md`nsrc/api/users.ts`nsrc/api/users.test.ts" |
            Set-Content -Path $listFile -Encoding utf8

        $result = Invoke-LabelAssigner -ChangedFilesPath $listFile -RulesPath $script:RulesFile
        $result.Labels | Should -Be @('tests', 'api', 'documentation')
    }

    It 'accepts an in-memory changed-files array' {
        $result = Invoke-LabelAssigner -ChangedFiles @('docs/a.md') -RulesPath $script:RulesFile
        $result.Labels | Should -Be @('documentation')
    }

    It 'ignores blank lines and trims whitespace in the list file' {
        $listFile = Join-Path $script:TmpDir 'messy.txt'
        "  docs/a.md  `n`n   `nsrc/api/b.ts" | Set-Content -Path $listFile -Encoding utf8
        $result = Invoke-LabelAssigner -ChangedFilesPath $listFile -RulesPath $script:RulesFile
        ($result.Labels | Sort-Object) | Should -Be @('api', 'documentation')
    }

    It 'returns an empty label set when nothing matches' {
        $result = Invoke-LabelAssigner -ChangedFiles @('Makefile') -RulesPath $script:RulesFile
        $result.Labels | Should -BeNullOrEmpty
    }

    It 'throws when the changed-files list file does not exist' {
        { Invoke-LabelAssigner -ChangedFilesPath (Join-Path $script:TmpDir 'ghost.txt') -RulesPath $script:RulesFile } |
            Should -Throw '*not found*'
    }
}
