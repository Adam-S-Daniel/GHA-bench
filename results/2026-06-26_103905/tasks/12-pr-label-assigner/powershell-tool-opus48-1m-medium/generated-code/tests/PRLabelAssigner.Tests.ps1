#requires -Modules Pester
<#
    Pester tests for the PR Label Assigner module.

    These tests are written first (red), then the module is implemented to make
    them pass (green). They exercise four layers:
      1. Glob -> regex conversion       (Convert-GlobToRegex)
      2. Single-file glob matching      (Test-GlobMatch)
      3. End-to-end label resolution    (Get-PRLabels)
      4. Error handling / edge cases
#>

BeforeAll {
    # Import the module under test relative to this test file so the suite is
    # runnable from any working directory.
    $modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'src/PRLabelAssigner.psm1'
    Import-Module $modulePath -Force
}

Describe 'Convert-GlobToRegex' {
    It 'converts a "**" segment into a cross-directory wildcard' {
        $regex = Convert-GlobToRegex -Glob 'docs/**'
        'docs/intro/setup.md' | Should -Match $regex
        'docs/readme.md'      | Should -Match $regex
    }

    It 'treats a single "*" as a within-segment wildcard that does not cross "/"' {
        $regex = Convert-GlobToRegex -Glob 'src/*.ps1'
        'src/app.ps1'        | Should -Match $regex
        'src/sub/app.ps1'    | Should -Not -Match $regex
    }

    It 'anchors the pattern so partial matches are rejected' {
        $regex = Convert-GlobToRegex -Glob 'api'
        'api'      | Should -Match $regex
        'apiary'   | Should -Not -Match $regex
    }

    It 'escapes regex metacharacters that appear literally in a path' {
        $regex = Convert-GlobToRegex -Glob 'a.b/c.txt'
        'a.b/c.txt' | Should -Match $regex
        'aXb/c.txt' | Should -Not -Match $regex
    }
}

Describe 'Test-GlobMatch' {
    It 'matches a basename-only pattern anywhere in the tree' {
        Test-GlobMatch -Path 'src/api/user.test.js' -Glob '*.test.*' | Should -BeTrue
        Test-GlobMatch -Path 'user.test.js'         -Glob '*.test.*' | Should -BeTrue
    }

    It 'matches a "**" directory prefix' {
        Test-GlobMatch -Path 'src/api/v1/users.ps1' -Glob 'src/api/**' | Should -BeTrue
        Test-GlobMatch -Path 'src/db/users.ps1'     -Glob 'src/api/**' | Should -BeFalse
    }

    It 'is case-insensitive for path comparison' {
        Test-GlobMatch -Path 'DOCS/readme.md' -Glob 'docs/**' | Should -BeTrue
    }
}

Describe 'Get-PRLabels' {
    BeforeAll {
        # A representative rule set covering globs, multi-label files and priority.
        $script:rules = @(
            [pscustomobject]@{ pattern = 'docs/**';     label = 'documentation'; priority = 30 }
            [pscustomobject]@{ pattern = 'src/api/**';   label = 'api';           priority = 10 }
            [pscustomobject]@{ pattern = '*.test.*';     label = 'tests';         priority = 20 }
            [pscustomobject]@{ pattern = 'src/**';       label = 'source';        priority = 40 }
        )
    }

    It 'returns the union of labels across all changed files' {
        $files = @('docs/intro.md', 'src/api/users.ps1')
        $labels = Get-PRLabels -ChangedFiles $files -Rules $script:rules
        $labels | Should -Contain 'documentation'
        $labels | Should -Contain 'api'
        $labels | Should -Contain 'source'
    }

    It 'assigns multiple labels to a single file when several rules match' {
        $files = @('src/api/user.test.ps1')
        $labels = Get-PRLabels -ChangedFiles $files -Rules $script:rules
        # api (src/api/**), tests (*.test.*) and source (src/**) all match.
        $labels | Should -Contain 'api'
        $labels | Should -Contain 'tests'
        $labels | Should -Contain 'source'
    }

    It 'orders the final label set by ascending priority (most important first)' {
        $files = @('src/api/user.test.ps1')
        $labels = Get-PRLabels -ChangedFiles $files -Rules $script:rules
        # priorities: api=10, tests=20, source=40 -> api, tests, source
        $labels | Should -Be @('api', 'tests', 'source')
    }

    It 'deduplicates a label produced by multiple files' {
        $files = @('docs/a.md', 'docs/b.md')
        $labels = Get-PRLabels -ChangedFiles $files -Rules $script:rules
        @($labels | Where-Object { $_ -eq 'documentation' }).Count | Should -Be 1
    }

    It 'returns an empty array when no rule matches any file' {
        $files = @('LICENSE')
        $labels = Get-PRLabels -ChangedFiles $files -Rules $script:rules
        $labels | Should -BeNullOrEmpty
    }

    It 'breaks priority ties deterministically using the label name' {
        $tieRules = @(
            [pscustomobject]@{ pattern = 'x/**'; label = 'zebra'; priority = 5 }
            [pscustomobject]@{ pattern = 'x/**'; label = 'alpha'; priority = 5 }
        )
        $labels = Get-PRLabels -ChangedFiles @('x/y.txt') -Rules $tieRules
        $labels | Should -Be @('alpha', 'zebra')
    }
}

Describe 'Get-PRLabels error handling' {
    It 'throws a meaningful error when a rule is missing the pattern field' {
        $bad = @([pscustomobject]@{ label = 'x'; priority = 1 })
        { Get-PRLabels -ChangedFiles @('a.txt') -Rules $bad } |
            Should -Throw -ExpectedMessage '*pattern*'
    }

    It 'throws a meaningful error when a rule is missing the label field' {
        $bad = @([pscustomobject]@{ pattern = 'a*'; priority = 1 })
        { Get-PRLabels -ChangedFiles @('a.txt') -Rules $bad } |
            Should -Throw -ExpectedMessage '*label*'
    }

    It 'tolerates an empty changed-file list and returns no labels' {
        $rules = @([pscustomobject]@{ pattern = 'a*'; label = 'x'; priority = 1 })
        Get-PRLabels -ChangedFiles @() -Rules $rules | Should -BeNullOrEmpty
    }
}

Describe 'Workflow structure' {
    BeforeAll {
        $script:repoRoot     = Split-Path $PSScriptRoot -Parent
        $script:workflowPath = Join-Path $script:repoRoot '.github/workflows/pr-label-assigner.yml'
        $script:workflowText = Get-Content -LiteralPath $script:workflowPath -Raw
    }

    It 'the workflow file exists' {
        Test-Path -LiteralPath $script:workflowPath | Should -BeTrue
    }

    It 'declares the expected trigger events' {
        $script:workflowText | Should -Match '(?m)^\s*push:'
        $script:workflowText | Should -Match '(?m)^\s*pull_request:'
        $script:workflowText | Should -Match '(?m)^\s*schedule:'
        $script:workflowText | Should -Match '(?m)^\s*workflow_dispatch:'
    }

    It 'defines the test and assign-labels jobs with a dependency' {
        $script:workflowText | Should -Match '(?m)^\s{2}test:'
        $script:workflowText | Should -Match '(?m)^\s{2}assign-labels:'
        $script:workflowText | Should -Match 'needs:\s*test'
    }

    It 'declares least-privilege permissions' {
        $script:workflowText | Should -Match 'permissions:'
        $script:workflowText | Should -Match 'contents:\s*read'
    }

    It 'uses actions/checkout@v4 and pwsh shell steps' {
        $script:workflowText | Should -Match 'actions/checkout@v4'
        $script:workflowText | Should -Match 'shell:\s*pwsh'
    }

    It 'references script files that actually exist on disk' {
        # The entrypoint the workflow invokes must be present.
        Test-Path (Join-Path $script:repoRoot 'src/Invoke-PRLabelAssigner.ps1') | Should -BeTrue
        Test-Path (Join-Path $script:repoRoot 'src/PRLabelAssigner.psm1')        | Should -BeTrue
        $script:workflowText | Should -Match 'Invoke-PRLabelAssigner\.ps1'
    }

    It 'passes actionlint with exit code 0' -Skip:(-not (Get-Command actionlint -ErrorAction SilentlyContinue)) {
        $null = & actionlint $script:workflowPath 2>&1
        $LASTEXITCODE | Should -Be 0
    }
}

Describe 'Import-LabelRules' {
    It 'loads rules from a JSON file' {
        $json = @'
[
  { "pattern": "docs/**", "label": "documentation", "priority": 30 },
  { "pattern": "src/api/**", "label": "api", "priority": 10 }
]
'@
        $tmp = Join-Path $TestDrive 'rules.json'
        $json | Set-Content -Path $tmp -Encoding utf8
        $rules = Import-LabelRules -Path $tmp
        $rules.Count | Should -Be 2
        $rules[0].pattern | Should -Be 'docs/**'
    }

    It 'throws a clear error when the rules file does not exist' {
        { Import-LabelRules -Path (Join-Path $TestDrive 'missing.json') } |
            Should -Throw -ExpectedMessage '*not found*'
    }

    It 'throws a clear error when the rules file contains invalid JSON' {
        $tmp = Join-Path $TestDrive 'broken.json'
        'this is not json{' | Set-Content -Path $tmp -Encoding utf8
        { Import-LabelRules -Path $tmp } | Should -Throw -ExpectedMessage '*JSON*'
    }
}
