#requires -Module Pester

# TDD suite for the CLI entry point Generate-Matrix.ps1. The script is the
# surface the GitHub Actions workflow calls: it reads a config file, prints the
# generated matrix between machine-readable markers, exposes scalar summary
# lines, and (when running in Actions) writes step outputs to $GITHUB_OUTPUT.
#
# The script is exercised exactly the way `act` runs it: as a fresh pwsh
# subprocess. That gives real exit codes, real stderr, and means a script-level
# `exit` cannot disturb the Pester host.

BeforeAll {
    $script:Root     = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:Script   = Join-Path $script:Root 'Generate-Matrix.ps1'
    $script:Fixtures = Join-Path $script:Root 'fixtures'

    # Run Generate-Matrix.ps1 in a child pwsh; capture stdout lines, stderr,
    # and the exit code. Child inherits the parent environment (so setting
    # $env:GITHUB_OUTPUT before calling routes step outputs to our temp file).
    function Invoke-Cli {
        param([string[]] $CliArgs)
        $errFile = [System.IO.Path]::GetTempFileName()
        try {
            $out  = & pwsh -NoProfile -File $script:Script @CliArgs 2>$errFile
            $code = $LASTEXITCODE
            $err  = (Get-Content -Path $errFile -Raw -ErrorAction SilentlyContinue)
            return [pscustomobject]@{ ExitCode = $code; Out = @($out); Err = "$err" }
        } finally {
            Remove-Item $errFile -ErrorAction SilentlyContinue
        }
    }

    function Get-EmittedMatrixJson {
        param([string[]] $Lines)
        $text  = ($Lines -join "`n")
        $start = $text.IndexOf('===MATRIX-JSON-START===')
        $end   = $text.IndexOf('===MATRIX-JSON-END===')
        if ($start -lt 0 -or $end -lt 0) { throw "matrix markers not found in output:`n$text" }
        $start = $text.IndexOf("`n", $start) + 1
        return $text.Substring($start, $end - $start)
    }

    function Get-EmittedScalar {
        param([string[]] $Lines, [string] $Key)
        $line = $Lines | Where-Object { $_ -match "^$([regex]::Escape($Key))=" } | Select-Object -First 1
        if (-not $line) { return $null }
        return ($line -split '=', 2)[1]
    }
}

Describe 'Generate-Matrix.ps1 - happy path' {
    It 'prints a parseable matrix JSON for the basic fixture' {
        $r = Invoke-Cli -CliArgs @('-ConfigPath', (Join-Path $script:Fixtures 'basic.json'))
        $r.ExitCode | Should -Be 0

        $parsed = (Get-EmittedMatrixJson -Lines $r.Out) | ConvertFrom-Json
        $parsed.count          | Should -Be 3
        @($parsed.matrix.include).Count | Should -Be 3
        $parsed.'max-parallel' | Should -Be 2
        $parsed.'fail-fast'    | Should -Be $false
    }

    It 'emits exact scalar summary lines' {
        $r = Invoke-Cli -CliArgs @('-ConfigPath', (Join-Path $script:Fixtures 'basic.json'))
        (Get-EmittedScalar -Lines $r.Out -Key 'matrix-count')        | Should -Be '3'
        (Get-EmittedScalar -Lines $r.Out -Key 'matrix-max-parallel') | Should -Be '2'
        (Get-EmittedScalar -Lines $r.Out -Key 'matrix-fail-fast')    | Should -Be 'false'
    }

    It 'expands the features fixture (exclude + include merge) to 6 jobs' {
        $r = Invoke-Cli -CliArgs @('-ConfigPath', (Join-Path $script:Fixtures 'features.json'))
        $r.ExitCode | Should -Be 0
        $parsed = (Get-EmittedMatrixJson -Lines $r.Out) | ConvertFrom-Json
        $parsed.count | Should -Be 6
        $exp = @($parsed.matrix.include | Where-Object { $_.experimental -eq 'true' })
        $exp.Count      | Should -Be 1
        $exp[0].os      | Should -Be 'ubuntu-latest'
        $exp[0].python  | Should -Be '3.12'
        $exp[0].feature | Should -Be 'full'
    }

    It 'expands the includes fixture (cache merge + new macos job) to 5 jobs' {
        $r = Invoke-Cli -CliArgs @('-ConfigPath', (Join-Path $script:Fixtures 'includes.json'))
        $r.ExitCode | Should -Be 0
        $parsed = (Get-EmittedMatrixJson -Lines $r.Out) | ConvertFrom-Json
        $parsed.count | Should -Be 5
        @($parsed.matrix.include | Where-Object { $_.cache -eq 'true' }).Count | Should -Be 2
        $mac = @($parsed.matrix.include | Where-Object { $_.os -eq 'macos-latest' })
        $mac.Count           | Should -Be 1
        $mac[0].node         | Should -Be '22'
        $mac[0].experimental | Should -Be 'true'
    }

    It 'accepts an inline -ConfigJson string' {
        $r = Invoke-Cli -CliArgs @('-ConfigJson', '{ "matrix": { "os": ["ubuntu-latest"], "node": ["20"] } }')
        $r.ExitCode | Should -Be 0
        $parsed = (Get-EmittedMatrixJson -Lines $r.Out) | ConvertFrom-Json
        $parsed.count | Should -Be 1
    }

    It 'writes the full matrix JSON to -OutFile' {
        $outFile = Join-Path ([System.IO.Path]::GetTempPath()) ("mtx-" + [guid]::NewGuid() + ".json")
        try {
            $r = Invoke-Cli -CliArgs @('-ConfigPath', (Join-Path $script:Fixtures 'basic.json'), '-OutFile', $outFile)
            $r.ExitCode | Should -Be 0
            Test-Path $outFile | Should -BeTrue
            (Get-Content $outFile -Raw | ConvertFrom-Json).count | Should -Be 3
        } finally {
            Remove-Item $outFile -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Generate-Matrix.ps1 - GitHub Actions step outputs' {
    It 'writes matrix / count / max-parallel / fail-fast to $GITHUB_OUTPUT' {
        $ghOut = Join-Path ([System.IO.Path]::GetTempPath()) ("ghout-" + [guid]::NewGuid() + ".txt")
        $saved = $env:GITHUB_OUTPUT
        $env:GITHUB_OUTPUT = $ghOut
        try {
            $r = Invoke-Cli -CliArgs @('-ConfigPath', (Join-Path $script:Fixtures 'basic.json'))
            $r.ExitCode | Should -Be 0
            $content = Get-Content $ghOut -Raw

            $content | Should -Match '(?m)^count=3$'
            $content | Should -Match '(?m)^maxParallel=2$'
            $content | Should -Match '(?m)^failFast=false$'

            # the matrix output is a heredoc block; extract and parse it
            $m = [regex]::Match($content, '(?ms)^matrix<<(?<d>\S+)\r?\n(?<v>.*?)\r?\n\k<d>\s*$')
            $m.Success | Should -BeTrue
            $matrixObj = $m.Groups['v'].Value | ConvertFrom-Json
            @($matrixObj.include).Count | Should -Be 3
        } finally {
            $env:GITHUB_OUTPUT = $saved
            Remove-Item $ghOut -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Generate-Matrix.ps1 - error handling' {
    It 'exits non-zero with a clear message when the config file is missing' {
        $r = Invoke-Cli -CliArgs @('-ConfigPath', (Join-Path $script:Fixtures 'does-not-exist.json'))
        $r.ExitCode | Should -Not -Be 0
        $r.Err | Should -Match 'not found'
    }

    It 'exits non-zero with a clear message on malformed JSON' {
        $r = Invoke-Cli -CliArgs @('-ConfigPath', (Join-Path $script:Fixtures 'malformed.json'))
        $r.ExitCode | Should -Not -Be 0
        $r.Err | Should -Match 'JSON'
    }

    It 'exits non-zero and reports the max-size error for an oversize config' {
        $r = Invoke-Cli -CliArgs @('-ConfigPath', (Join-Path $script:Fixtures 'oversize.json'))
        $r.ExitCode | Should -Not -Be 0
        $r.Err | Should -Match 'exceeds the maximum'
    }
}
