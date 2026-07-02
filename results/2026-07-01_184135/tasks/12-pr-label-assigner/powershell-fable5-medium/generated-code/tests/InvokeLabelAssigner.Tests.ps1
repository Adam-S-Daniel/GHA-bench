# Tests for the CLI wrapper Invoke-LabelAssigner.ps1 (written before the
# script existed — red/green TDD). The wrapper is what the GitHub Actions
# workflow calls: it reads a newline-delimited changed-files list (the mocked
# PR file list) and a JSON rules config, and prints the final label set.

BeforeAll {
    $script:Cli = Join-Path $PSScriptRoot '..' 'Invoke-LabelAssigner.ps1'

    # Helper: write a fixture pair into a temp dir and return the paths.
    function New-Fixture {
        param([string[]]$Files, [string]$RulesJson)
        $dir = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path $dir | Out-Null
        $filesPath = Join-Path $dir 'changed-files.txt'
        $rulesPath = Join-Path $dir 'rules.json'
        Set-Content -Path $filesPath -Value ($Files -join "`n")
        Set-Content -Path $rulesPath -Value $RulesJson
        [pscustomobject]@{ Files = $filesPath; Rules = $rulesPath; Dir = $dir }
    }

    $script:DefaultRules = @'
[
  { "Pattern": "docs/**",          "Labels": ["documentation"] },
  { "Pattern": "src/api/**",      "Labels": ["api"] },
  { "Pattern": "*.test.*",        "Labels": ["tests"] },
  { "Pattern": "docs/internal/**","Labels": ["internal-docs"], "Priority": 10, "Exclusive": true }
]
'@
}

Describe 'Invoke-LabelAssigner.ps1' {

    It 'prints the final label set as a stable comma-separated LABELS line' {
        $fx = New-Fixture -Files @('docs/readme.md', 'src/api/users.ps1', 'src/core/util.test.ts') -RulesJson $script:DefaultRules
        # In-process invocation: success == no exception thrown.
        $out = & $script:Cli -ChangedFilesPath $fx.Files -RulesPath $fx.Rules
        ($out -join "`n") | Should -Match ([regex]::Escape('LABELS: api,documentation,tests'))
    }

    It 'prints LABELS: (none) when no rule matches' {
        $fx = New-Fixture -Files @('Makefile') -RulesJson $script:DefaultRules
        $out = & $script:Cli -ChangedFilesPath $fx.Files -RulesPath $fx.Rules
        ($out -join "`n") | Should -Match ([regex]::Escape('LABELS: (none)'))
    }

    It 'resolves conflicts via priority: exclusive internal-docs rule wins' {
        $fx = New-Fixture -Files @('docs/internal/secrets.md') -RulesJson $script:DefaultRules
        $out = & $script:Cli -ChangedFilesPath $fx.Files -RulesPath $fx.Rules
        ($out -join "`n") | Should -Match ([regex]::Escape('LABELS: internal-docs'))
        ($out -join "`n") | Should -Not -Match 'documentation'
    }

    It 'fails with a meaningful error when the changed-files list is missing' {
        $fx = New-Fixture -Files @('a.txt') -RulesJson $script:DefaultRules
        { & $script:Cli -ChangedFilesPath (Join-Path $fx.Dir 'nope.txt') -RulesPath $fx.Rules -ErrorAction Stop } |
            Should -Throw '*Changed-files list not found*'
    }

    It 'fails with a meaningful error when the rules file is missing' {
        $fx = New-Fixture -Files @('a.txt') -RulesJson $script:DefaultRules
        { & $script:Cli -ChangedFilesPath $fx.Files -RulesPath (Join-Path $fx.Dir 'nope.json') -ErrorAction Stop } |
            Should -Throw '*Rules file not found*'
    }

    It 'fails with a meaningful error on invalid JSON in the rules file' {
        $fx = New-Fixture -Files @('a.txt') -RulesJson '{ not valid json ]'
        { & $script:Cli -ChangedFilesPath $fx.Files -RulesPath $fx.Rules -ErrorAction Stop } |
            Should -Throw '*not valid JSON*'
    }
}
