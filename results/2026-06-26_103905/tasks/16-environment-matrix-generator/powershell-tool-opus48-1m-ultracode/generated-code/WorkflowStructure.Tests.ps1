<#
  WorkflowStructure.Tests.ps1
  ---------------------------
  Static checks on the workflow file (no Docker needed):
    * actionlint passes cleanly (exit 0)
    * the YAML parses and has the expected triggers / jobs / steps
    * the workflow references files that actually exist on disk
#>

BeforeAll {
    $script:Root = $PSScriptRoot
    $script:WorkflowPath = Join-Path $Root '.github/workflows/environment-matrix-generator.yml'

    Import-Module powershell-yaml -ErrorAction Stop
    $script:Raw = Get-Content -LiteralPath $WorkflowPath -Raw
    $script:Wf = ConvertFrom-Yaml $Raw

    # YAML 1.1 parses the bare key `on` as the boolean true; fetch the trigger map
    # under whichever key the parser produced.
    $script:Triggers =
        if ($Wf.Contains('on')) { $Wf['on'] }
        elseif ($Wf.Contains($true)) { $Wf[$true] }
        else { $null }
}

Describe 'actionlint' {
    It 'passes with no errors (exit 0)' {
        $null = & actionlint $WorkflowPath 2>&1
        $LASTEXITCODE | Should -Be 0
    }
}

Describe 'Workflow file structure' {
    It 'has a name' {
        $Wf['name'] | Should -Be 'Environment Matrix Generator'
    }

    It 'defines the expected trigger events' {
        $Triggers | Should -Not -BeNullOrEmpty
        $keys = @($Triggers.Keys | ForEach-Object { "$_" })
        $keys | Should -Contain 'push'
        $keys | Should -Contain 'pull_request'
        $keys | Should -Contain 'workflow_dispatch'
        $keys | Should -Contain 'schedule'
    }

    It 'requests least-privilege read permissions' {
        $Wf['permissions']['contents'] | Should -Be 'read'
    }

    It 'declares the generate and build jobs' {
        $Wf['jobs'].Keys | Should -Contain 'generate'
        $Wf['jobs'].Keys | Should -Contain 'build'
    }

    It 'runs generate on ubuntu-latest with steps' {
        $Wf['jobs']['generate']['runs-on'] | Should -Be 'ubuntu-latest'
        @($Wf['jobs']['generate']['steps']).Count | Should -BeGreaterThan 0
    }

    It 'checks out the repository with actions/checkout@v4' {
        $steps = @($Wf['jobs']['generate']['steps'])
        ($steps | Where-Object { $_['uses'] -eq 'actions/checkout@v4' }).Count | Should -BeGreaterOrEqual 1
    }

    It 'invokes the generator script' {
        $steps = @($Wf['jobs']['generate']['steps'])
        ($steps | Where-Object { $_['run'] -and $_['run'] -match 'Invoke-MatrixGenerator\.ps1' }).Count |
            Should -BeGreaterOrEqual 1
    }

    It 'uses shell: pwsh for the generator step (not pwsh -File from bash)' {
        $steps = @($Wf['jobs']['generate']['steps'])
        $genStep = $steps | Where-Object { $_['run'] -and $_['run'] -match 'Invoke-MatrixGenerator\.ps1' } | Select-Object -First 1
        $genStep['shell'] | Should -Be 'pwsh'
        $Raw | Should -Not -Match 'pwsh\s+-File'
    }

    It 'exposes the generated matrix as a job output' {
        $Wf['jobs']['generate']['outputs']['matrix'] | Should -Match 'steps\.gen\.outputs\.matrix'
    }

    It 'makes build depend on generate and consume the matrix via fromJSON' {
        $needs = $Wf['jobs']['build']['needs']
        @($needs) | Should -Contain 'generate'
        $matrixExpr = $Wf['jobs']['build']['strategy']['matrix']
        $matrixExpr | Should -Match 'fromJSON\('
        $matrixExpr | Should -Match 'needs\.generate\.outputs\.matrix'
    }
}

Describe 'Workflow references existing files' {
    It 'has the generator script and module on disk' {
        Test-Path (Join-Path $Root 'Invoke-MatrixGenerator.ps1') | Should -BeTrue
        Test-Path (Join-Path $Root 'BuildMatrix.psm1') | Should -BeTrue
    }

    It 'points PRIMARY_CONFIG at an existing config file' {
        $primary = $Wf['env']['PRIMARY_CONFIG']
        $primary | Should -Be 'fixtures/a-basic.json'
        Test-Path (Join-Path $Root $primary) | Should -BeTrue
    }

    It 'has every fixture the pipeline iterates over' {
        $fixturesDir = Join-Path $Root $Wf['env']['FIXTURES_DIR']
        Test-Path $fixturesDir | Should -BeTrue
        foreach ($name in 'a-basic', 'b-include', 'c-oversize', 'd-features', 'e-partial') {
            Test-Path (Join-Path $fixturesDir "$name.json") | Should -BeTrue
        }
    }
}
