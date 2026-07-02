# Pester tests for the minimal indentation-based YAML reader used by
# WorkflowStructure.Tests.ps1. We can't rely on the powershell-yaml module
# inside the act container (only pwsh + Pester are pre-installed there), so
# this hand-rolled reader covers just the subset of YAML GitHub Actions
# workflow files use: nested mappings and block sequences.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'Helpers' 'SimpleYaml.psm1') -Force
}

Describe 'ConvertFrom-SimpleYaml' {
    It 'parses flat scalar mappings' {
        $yaml = @(
            'name: PR Label Assigner'
            'foo: bar'
        )
        $doc = ConvertFrom-SimpleYaml -Lines $yaml
        $doc.name | Should -Be 'PR Label Assigner'
        $doc.foo | Should -Be 'bar'
    }

    It 'parses nested mappings' {
        $yaml = @(
            'jobs:'
            '  test:'
            '    runs-on: ubuntu-latest'
        )
        $doc = ConvertFrom-SimpleYaml -Lines $yaml
        $doc.jobs.test.'runs-on' | Should -Be 'ubuntu-latest'
    }

    It 'treats a key with no value and no nested block as an empty mapping' {
        $yaml = @(
            'on:'
            '  push:'
            '  pull_request:'
        )
        $doc = ConvertFrom-SimpleYaml -Lines $yaml
        $doc.on.Keys | Should -Contain 'push'
        $doc.on.Keys | Should -Contain 'pull_request'
    }

    It 'parses a block sequence of scalars' {
        $yaml = @(
            'options:'
            '  - a'
            '  - b'
        )
        $doc = ConvertFrom-SimpleYaml -Lines $yaml
        $doc.options.Count | Should -Be 2
        $doc.options[0] | Should -Be 'a'
        $doc.options[1] | Should -Be 'b'
    }

    It 'parses a block sequence of mappings (e.g. workflow steps)' {
        $yaml = @(
            'steps:'
            '  - name: Checkout'
            '    uses: actions/checkout@v4'
            '  - name: Run tests'
            '    shell: pwsh'
        )
        $doc = ConvertFrom-SimpleYaml -Lines $yaml
        $doc.steps.Count | Should -Be 2
        $doc.steps[0].name | Should -Be 'Checkout'
        $doc.steps[0].uses | Should -Be 'actions/checkout@v4'
        $doc.steps[1].shell | Should -Be 'pwsh'
    }

    It 'strips matching single or double quotes from scalar values' {
        $yaml = @(
            "cron: '17 3 * * *'"
            'label: "documentation"'
        )
        $doc = ConvertFrom-SimpleYaml -Lines $yaml
        $doc.cron | Should -Be '17 3 * * *'
        $doc.label | Should -Be 'documentation'
    }

    It 'reads a block scalar (key: |) as a single joined multi-line string' {
        $yaml = @(
            'steps:'
            '  - name: Run tests'
            '    run: |'
            '      Import-Module Pester'
            '      Invoke-Pester -Path ./tests'
            '  - name: Next step'
            '    uses: actions/checkout@v4'
        )
        $doc = ConvertFrom-SimpleYaml -Lines $yaml
        $doc.steps.Count | Should -Be 2
        $doc.steps[0].run | Should -Be "Import-Module Pester`nInvoke-Pester -Path ./tests"
        $doc.steps[1].uses | Should -Be 'actions/checkout@v4'
    }

    It 'tolerates blank lines inside and around a block scalar' {
        $yaml = @(
            'run: |'
            '  line one'
            ''
            '  line two'
            'next: value'
        )
        $doc = ConvertFrom-SimpleYaml -Lines $yaml
        $doc.run | Should -Be "line one`n`nline two"
        $doc.next | Should -Be 'value'
    }
}
