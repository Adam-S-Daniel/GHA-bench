# Workflow structure tests: verify the GitHub Actions pipeline definition
# has the expected triggers, jobs, steps and script references, and that
# actionlint accepts it. YAML structure is asserted with targeted regexes
# (no external YAML module needed); actionlint provides full validation.

BeforeAll {
    $script:RepoRoot     = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:WorkflowPath = Join-Path $script:RepoRoot '.github/workflows/pr-label-assigner.yml'
    $script:Yaml         = Get-Content -LiteralPath $script:WorkflowPath -Raw
}

Describe 'workflow file structure' {

    It 'exists at the required path' {
        Test-Path $script:WorkflowPath | Should -BeTrue
    }

    It 'declares push, pull_request and workflow_dispatch triggers' {
        $script:Yaml | Should -Match '(?ms)^on:\s*$'
        $script:Yaml | Should -Match '(?m)^\s+push:'
        $script:Yaml | Should -Match '(?m)^\s+pull_request:'
        $script:Yaml | Should -Match '(?m)^\s+workflow_dispatch:'
    }

    It 'restricts permissions to contents: read' {
        $script:Yaml | Should -Match '(?ms)^permissions:\s*\n\s+contents:\s*read'
    }

    It 'defines the test and assign-labels jobs, with a dependency between them' {
        $script:Yaml | Should -Match '(?m)^\s{2}test:'
        $script:Yaml | Should -Match '(?m)^\s{2}assign-labels:'
        $script:Yaml | Should -Match '(?m)^\s+needs:\s*test\b'
    }

    It 'checks out the repository with actions/checkout@v4 and uses shell: pwsh' {
        $script:Yaml | Should -Match 'uses:\s*actions/checkout@v4'
        $script:Yaml | Should -Match 'shell:\s*pwsh'
        # Per the task rules, run steps must not shell out to pwsh manually.
        $script:Yaml | Should -Not -Match 'pwsh\s+-(Command|File)'
    }

    It 'runs the Pester suite and the label assigner script' {
        $script:Yaml | Should -Match 'Invoke-Pester'
        $script:Yaml | Should -Match '\./Invoke-LabelAssigner\.ps1'
    }

    It 'references only files that actually exist in the repo' {
        foreach ($rel in @(
            'Invoke-LabelAssigner.ps1',
            'LabelAssigner.psm1',
            'tests/LabelAssigner.Tests.ps1',
            'tests/InvokeLabelAssigner.Tests.ps1',
            'fixtures/changed-files.txt',
            'fixtures/label-rules.json'
        )) {
            Test-Path (Join-Path $script:RepoRoot $rel) |
                Should -BeTrue -Because "$rel is referenced by the workflow/env"
        }
    }
}

Describe 'actionlint validation' {

    It 'passes actionlint with exit code 0' {
        $lint = Get-Command actionlint -ErrorAction SilentlyContinue
        if (-not $lint) {
            Set-ItResult -Skipped -Because 'actionlint is not installed on this machine'
            return
        }
        $output = & $lint.Source $script:WorkflowPath 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ("actionlint output: " + ($output -join "`n"))
    }
}
