# Pester tests for the PR Label Assigner tool.
# Red/Green TDD: each Describe block below was written before its
# corresponding implementation in ../PrLabelAssigner.psm1.

BeforeAll {
    Import-Module "$PSScriptRoot/../PrLabelAssigner.psm1" -Force
}

Describe 'Get-PrLabels - basic glob matching' {
    It 'assigns the "documentation" label to a file under docs/' {
        $rules = @(
            @{ Pattern = 'docs/**'; Label = 'documentation' }
        )
        $files = @('docs/readme.md')

        $labels = Get-PrLabels -ChangedFiles $files -Rules $rules

        $labels | Should -Contain 'documentation'
    }

    It 'does not assign a label when no file matches the pattern' {
        $rules = @(
            @{ Pattern = 'docs/**'; Label = 'documentation' }
        )
        $files = @('src/main.ps1')

        $labels = Get-PrLabels -ChangedFiles $files -Rules $rules

        $labels | Should -Not -Contain 'documentation'
        $labels.Count | Should -Be 0
    }

    It 'matches a file extension pattern like *.test.*' {
        $rules = @(
            @{ Pattern = '*.test.*'; Label = 'tests' }
        )
        $files = @('src/foo.test.ps1')

        $labels = Get-PrLabels -ChangedFiles $files -Rules $rules

        $labels | Should -Contain 'tests'
    }
}

Describe 'Get-PrLabels - multiple labels per file and multiple rules' {
    It 'applies multiple labels when a single file matches multiple rules' {
        $rules = @(
            @{ Pattern = 'src/api/**'; Label = 'api' }
            @{ Pattern = '*.test.*'; Label = 'tests' }
        )
        $files = @('src/api/handler.test.ps1')

        $labels = Get-PrLabels -ChangedFiles $files -Rules $rules

        $labels | Should -Contain 'api'
        $labels | Should -Contain 'tests'
        $labels.Count | Should -Be 2
    }

    It 'de-duplicates a label when multiple files match the same rule' {
        $rules = @(
            @{ Pattern = 'docs/**'; Label = 'documentation' }
        )
        $files = @('docs/readme.md', 'docs/guide.md')

        $labels = Get-PrLabels -ChangedFiles $files -Rules $rules

        ($labels | Where-Object { $_ -eq 'documentation' }).Count | Should -Be 1
    }

    It 'returns labels for every distinct matching rule across multiple files' {
        $rules = @(
            @{ Pattern = 'docs/**'; Label = 'documentation' }
            @{ Pattern = 'src/api/**'; Label = 'api' }
        )
        $files = @('docs/readme.md', 'src/api/handler.ps1', 'src/other/file.ps1')

        $labels = Get-PrLabels -ChangedFiles $files -Rules $rules

        $labels | Should -Contain 'documentation'
        $labels | Should -Contain 'api'
        $labels.Count | Should -Be 2
    }
}

Describe 'Get-PrLabels - priority ordering when rules conflict' {
    It 'assigns only the highest-priority label when rules are mutually exclusive by priority' {
        # Lower Priority number = higher priority (wins conflicts).
        $rules = @(
            @{ Pattern = 'src/api/**'; Label = 'api'; Priority = 1; Exclusive = $true }
            @{ Pattern = 'src/**'; Label = 'source'; Priority = 2; Exclusive = $true }
        )
        $files = @('src/api/handler.ps1')

        $labels = Get-PrLabels -ChangedFiles $files -Rules $rules

        $labels | Should -Contain 'api'
        $labels | Should -Not -Contain 'source'
        $labels.Count | Should -Be 1
    }

    It 'keeps non-exclusive labels alongside the winning exclusive label' {
        $rules = @(
            @{ Pattern = 'src/api/**'; Label = 'api'; Priority = 1; Exclusive = $true }
            @{ Pattern = 'src/**'; Label = 'source'; Priority = 2; Exclusive = $true }
            @{ Pattern = '*.test.*'; Label = 'tests' }
        )
        $files = @('src/api/handler.test.ps1')

        $labels = Get-PrLabels -ChangedFiles $files -Rules $rules

        $labels | Should -Contain 'api'
        $labels | Should -Contain 'tests'
        $labels | Should -Not -Contain 'source'
        $labels.Count | Should -Be 2
    }
}

Describe 'Get-PrLabels - error handling' {
    It 'throws a meaningful error when ChangedFiles is empty' {
        $rules = @(@{ Pattern = 'docs/**'; Label = 'documentation' })

        { Get-PrLabels -ChangedFiles @() -Rules $rules } | Should -Throw '*ChangedFiles*'
    }

    It 'throws a meaningful error when a rule is missing a Pattern' {
        $rules = @(@{ Label = 'documentation' })

        { Get-PrLabels -ChangedFiles @('docs/readme.md') -Rules $rules } | Should -Throw '*Pattern*'
    }

    It 'throws a meaningful error when a rule is missing a Label' {
        $rules = @(@{ Pattern = 'docs/**' })

        { Get-PrLabels -ChangedFiles @('docs/readme.md') -Rules $rules } | Should -Throw '*Label*'
    }
}

Describe 'Import-PrLabelRules - loading rule configuration' {
    It 'loads rules from a JSON configuration file' {
        $configPath = "$PSScriptRoot/../fixtures/label-rules.json"

        $rules = Import-PrLabelRules -Path $configPath

        $rules.Count | Should -BeGreaterThan 0
        ($rules | Where-Object { $_.Label -eq 'documentation' }) | Should -Not -BeNullOrEmpty
    }

    It 'throws a meaningful error when the configuration file does not exist' {
        { Import-PrLabelRules -Path "$PSScriptRoot/../fixtures/does-not-exist.json" } | Should -Throw '*not found*'
    }
}

Describe 'Invoke-LabelAssigner.ps1 - CLI entry point' {
    It 'prints the comma-separated label set for a docs-only mocked changed-file list' {
        $scriptPath = "$PSScriptRoot/../Invoke-LabelAssigner.ps1"
        $changedFilesPath = "$PSScriptRoot/../fixtures/changed-files-docs.txt"
        $rulesPath = "$PSScriptRoot/../fixtures/label-rules.json"

        $output = & $scriptPath -ChangedFilesPath $changedFilesPath -RulesPath $rulesPath

        $output | Should -Be 'documentation'
    }

    It 'prints multiple exclusive-resolved labels for a mixed changed-file list' {
        $scriptPath = "$PSScriptRoot/../Invoke-LabelAssigner.ps1"
        $changedFilesPath = "$PSScriptRoot/../fixtures/changed-files-mixed.txt"
        $rulesPath = "$PSScriptRoot/../fixtures/label-rules.json"

        $output = & $scriptPath -ChangedFilesPath $changedFilesPath -RulesPath $rulesPath

        # src/api/** (exclusive, priority 1) beats src/** (exclusive, priority 2);
        # documentation and tests are non-exclusive and additive.
        $labels = $output -split ','
        $labels | Should -Contain 'api'
        $labels | Should -Contain 'documentation'
        $labels | Should -Contain 'tests'
        $labels | Should -Not -Contain 'source'
    }
}
