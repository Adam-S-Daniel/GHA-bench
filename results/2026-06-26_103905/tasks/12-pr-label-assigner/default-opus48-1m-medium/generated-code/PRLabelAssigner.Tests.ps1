# PRLabelAssigner.Tests.ps1
#
# Pester unit tests for the PR Label Assigner, written using red/green TDD.
# Each Describe block was added one assertion at a time: write a failing test,
# implement the minimum code in PRLabelAssigner.ps1 to make it pass, refactor.
#
# Run locally with:  pwsh -c "Invoke-Pester ./PRLabelAssigner.Tests.ps1"

BeforeAll {
    # Dot-source the script under test so Get-PRLabels is available in scope.
    . "$PSScriptRoot/PRLabelAssigner.ps1"
}

Describe 'Get-PRLabels' {

    Context 'TDD step 1: a single file matching one rule' {
        It 'returns the label for a file that matches docs/**' {
            $rules = @(
                @{ Pattern = 'docs/**'; Label = 'documentation' }
            )
            $files = @('docs/intro.md')

            Get-PRLabels -ChangedFiles $files -Rules $rules | Should -Be 'documentation'
        }
    }

    Context 'TDD step 2: glob segment semantics (* vs **)' {
        It 'single * does NOT cross a directory boundary' {
            $rules = @( @{ Pattern = 'src/*'; Label = 'src-top' } )
            # src/api/foo.js has an extra segment, so src/* must not match it.
            Get-PRLabels -ChangedFiles @('src/api/foo.js') -Rules $rules | Should -BeNullOrEmpty
        }

        It 'single * matches within one segment' {
            $rules = @( @{ Pattern = 'src/*'; Label = 'src-top' } )
            Get-PRLabels -ChangedFiles @('src/main.ps1') -Rules $rules | Should -Be 'src-top'
        }

        It '** crosses directory boundaries' {
            $rules = @( @{ Pattern = 'src/**'; Label = 'src-any' } )
            Get-PRLabels -ChangedFiles @('src/api/v1/foo.js') -Rules $rules | Should -Be 'src-any'
        }
    }

    Context 'TDD step 3: basename patterns (no slash matches the file name)' {
        It 'matches *.test.* against a nested file' {
            $rules = @( @{ Pattern = '*.test.*'; Label = 'tests' } )
            Get-PRLabels -ChangedFiles @('src/widget.test.js') -Rules $rules | Should -Be 'tests'
        }

        It 'does not match a file whose basename lacks the pattern' {
            $rules = @( @{ Pattern = '*.test.*'; Label = 'tests' } )
            Get-PRLabels -ChangedFiles @('src/widget.js') -Rules $rules | Should -BeNullOrEmpty
        }
    }

    Context 'TDD step 4: a single file can receive multiple labels' {
        It 'collects every matching rule label for one file' {
            $rules = @(
                @{ Pattern = 'src/api/**'; Label = 'api' }
                @{ Pattern = '*.test.*';   Label = 'tests' }
            )
            $result = Get-PRLabels -ChangedFiles @('src/api/users.test.js') -Rules $rules
            $result | Should -Contain 'api'
            $result | Should -Contain 'tests'
            $result.Count | Should -Be 2
        }
    }

    Context 'TDD step 5: labels are de-duplicated across files' {
        It 'returns a label only once even if many files match' {
            $rules = @( @{ Pattern = 'docs/**'; Label = 'documentation' } )
            $files = @('docs/a.md', 'docs/b.md', 'docs/sub/c.md')
            $result = @(Get-PRLabels -ChangedFiles $files -Rules $rules)
            $result.Count | Should -Be 1
            $result[0]    | Should -Be 'documentation'
        }
    }

    Context 'TDD step 6: priority ordering when rules conflict' {
        It 'orders labels by descending priority, then alphabetically' {
            $rules = @(
                @{ Pattern = 'docs/**';    Label = 'documentation'; Priority = 1 }
                @{ Pattern = 'src/api/**'; Label = 'api';           Priority = 100 }
                @{ Pattern = 'src/**';     Label = 'source';        Priority = 50 }
            )
            $files = @('docs/x.md', 'src/api/y.js', 'src/z.js')
            $result = @(Get-PRLabels -ChangedFiles $files -Rules $rules)
            # api (100) > source (50) > documentation (1)
            $result | Should -Be @('api', 'source', 'documentation')
        }

        It 'breaks ties alphabetically for equal priority' {
            $rules = @(
                @{ Pattern = 'b/**'; Label = 'beta';  Priority = 5 }
                @{ Pattern = 'a/**'; Label = 'alpha'; Priority = 5 }
            )
            $result = @(Get-PRLabels -ChangedFiles @('a/1', 'b/2') -Rules $rules)
            $result | Should -Be @('alpha', 'beta')
        }
    }

    Context 'TDD step 7: graceful handling of empty / missing input' {
        It 'returns nothing when there are no changed files' {
            $rules = @( @{ Pattern = 'docs/**'; Label = 'documentation' } )
            Get-PRLabels -ChangedFiles @() -Rules $rules | Should -BeNullOrEmpty
        }

        It 'returns nothing when no rules are supplied' {
            Get-PRLabels -ChangedFiles @('docs/a.md') -Rules @() | Should -BeNullOrEmpty
        }
    }

    Context 'TDD step 8: meaningful errors on malformed rules' {
        It 'throws when a rule is missing its Pattern' {
            $rules = @( @{ Label = 'oops' } )
            { Get-PRLabels -ChangedFiles @('docs/a.md') -Rules $rules } |
                Should -Throw -ExpectedMessage '*Pattern*'
        }

        It 'throws when a rule is missing its Label' {
            $rules = @( @{ Pattern = 'docs/**' } )
            { Get-PRLabels -ChangedFiles @('docs/a.md') -Rules $rules } |
                Should -Throw -ExpectedMessage '*Label*'
        }
    }
}

Describe 'Import-LabelRules (config loading)' {
    It 'loads rules from a JSON config file' {
        $json = @'
{
  "rules": [
    { "pattern": "docs/**", "label": "documentation", "priority": 1 },
    { "pattern": "*.test.*", "label": "tests", "priority": 10 }
  ]
}
'@
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("rules_" + [guid]::NewGuid().ToString('N') + '.json')
        Set-Content -Path $tmp -Value $json -Encoding utf8
        try {
            $rules = Import-LabelRules -Path $tmp
            $rules.Count | Should -Be 2
            $rules[0].Pattern  | Should -Be 'docs/**'
            $rules[0].Label    | Should -Be 'documentation'
            $rules[1].Priority | Should -Be 10
        }
        finally {
            Remove-Item $tmp -ErrorAction SilentlyContinue
        }
    }

    It 'throws a meaningful error when the config file is missing' {
        { Import-LabelRules -Path '/no/such/config.json' } |
            Should -Throw -ExpectedMessage '*not found*'
    }
}
