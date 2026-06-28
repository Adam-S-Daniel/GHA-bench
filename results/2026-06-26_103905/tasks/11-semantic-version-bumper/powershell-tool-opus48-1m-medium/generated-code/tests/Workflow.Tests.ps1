<#
    Integration + structure tests for the GitHub Actions workflow.

    Per the task requirements, EVERY functional test case is executed end-to-end
    through the workflow via `act` (nektos/act). We never invoke the script directly
    here. For each fixture case we:
      1. assemble a temp git repo (project files + that case's fixture data),
      2. run `act push --rm --pull=false`, capturing the output,
      3. append the output to act-result.txt (clearly delimited),
      4. assert act exited 0, "Job succeeded" appears, and the EXACT expected
         NEW_VERSION value is present.

    Structure tests parse the YAML and assert triggers/jobs/steps, that referenced
    scripts exist, and that actionlint passes.
#>

# Each case: which fixture, and the exact expected new version it must produce.
# Defined at top level (discovery scope) so the data-driven `It -ForEach` below
# can enumerate the cases when Pester discovers tests.
$Cases = @(
    @{ Name = 'feat-minor';     Expected = '1.2.0'; BumpType = 'minor' }
    @{ Name = 'fix-patch';      Expected = '1.4.3'; BumpType = 'patch' }
    @{ Name = 'breaking-major'; Expected = '2.0.0'; BumpType = 'major' }
    @{ Name = 'pkgjson-patch';  Expected = '2.3.5'; BumpType = 'patch' }
    @{ Name = 'no-bump';        Expected = '0.5.0'; BumpType = 'none'  }
    @{ Name = 'multi-mixed';    Expected = '2.1.0'; BumpType = 'minor' }
)

BeforeAll {
    Import-Module powershell-yaml -ErrorAction Stop

    $script:RepoRoot     = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:WorkflowPath = Join-Path $script:RepoRoot '.github' 'workflows' 'semantic-version-bumper.yml'
    $script:FixturesRoot = Join-Path $script:RepoRoot 'tests' 'fixtures'
    $script:ActResult    = Join-Path $script:RepoRoot 'act-result.txt'

    # Re-declare the case list in run scope (BeforeAll cannot see discovery-scope locals).
    $script:Cases = @(
        @{ Name = 'feat-minor';     Expected = '1.2.0'; BumpType = 'minor' }
        @{ Name = 'fix-patch';      Expected = '1.4.3'; BumpType = 'patch' }
        @{ Name = 'breaking-major'; Expected = '2.0.0'; BumpType = 'major' }
        @{ Name = 'pkgjson-patch';  Expected = '2.3.5'; BumpType = 'patch' }
        @{ Name = 'no-bump';        Expected = '0.5.0'; BumpType = 'none'  }
        @{ Name = 'multi-mixed';    Expected = '2.1.0'; BumpType = 'minor' }
    )

    # Fresh aggregate output file for this run.
    Set-Content -LiteralPath $script:ActResult -Value "ACT INTEGRATION RUN`n" -NoNewline

    # Runs one fixture case through act and returns @{ ExitCode; Output }.
    function Invoke-ActCase {
        param([Parameter(Mandatory)][string] $CaseName)

        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("act-" + [System.Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        try {
            # Project files needed inside the container.
            Copy-Item (Join-Path $script:RepoRoot 'src') $tmp -Recurse
            Copy-Item (Join-Path $script:RepoRoot 'Invoke-Bumper.ps1') $tmp
            New-Item -ItemType Directory -Path (Join-Path $tmp '.github' 'workflows') -Force | Out-Null
            Copy-Item $script:WorkflowPath (Join-Path $tmp '.github' 'workflows')

            # Fixture data for this case (version source + commit log).
            $fixtureDir = Join-Path $script:FixturesRoot $CaseName
            Copy-Item (Join-Path $fixtureDir '*') $tmp -Recurse

            # Local .actrc: map ubuntu-latest to the prebuilt pwsh image.
            Set-Content -LiteralPath (Join-Path $tmp '.actrc') -Value '-P ubuntu-latest=act-ubuntu-pwsh:latest'

            # act requires a git repo to resolve the event.
            Push-Location $tmp
            try {
                git init -q 2>&1 | Out-Null
                git add -A 2>&1 | Out-Null
                git -c user.email='ci@example.com' -c user.name='ci' commit -qm 'fixture' 2>&1 | Out-Null
                # --pull=false forces use of the local image (avoids a registry pull).
                $output = & act push --rm --pull=false 2>&1 | Out-String
                $exit = $LASTEXITCODE
            }
            finally { Pop-Location }

            # Append delimited output to the aggregate artifact.
            $delim = "`n========== CASE: $CaseName (exit=$exit) ==========`n"
            Add-Content -LiteralPath $script:ActResult -Value $delim
            Add-Content -LiteralPath $script:ActResult -Value $output

            return @{ ExitCode = $exit; Output = $output }
        }
        finally {
            if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }

    # Run every case once up front; tests then assert on the captured results.
    $script:Results = @{}
    foreach ($c in $script:Cases) {
        $script:Results[$c.Name] = Invoke-ActCase -CaseName $c.Name
    }
}

Describe 'Workflow structure' {

    BeforeAll {
        $script:Yaml = Get-Content -LiteralPath $script:WorkflowPath -Raw | ConvertFrom-Yaml
    }

    It 'is valid YAML with a name' {
        $script:Yaml.name | Should -Be 'Semantic Version Bumper'
    }

    It 'declares the expected trigger events' {
        $on = $script:Yaml['on']
        $on.Keys | Should -Contain 'push'
        $on.Keys | Should -Contain 'pull_request'
        $on.Keys | Should -Contain 'workflow_dispatch'
        $on.Keys | Should -Contain 'schedule'
    }

    It 'defines a bump job running on ubuntu-latest' {
        $script:Yaml.jobs.Keys | Should -Contain 'bump'
        $script:Yaml.jobs.bump.'runs-on' | Should -Be 'ubuntu-latest'
    }

    It 'checks out the repo with actions/checkout@v4' {
        $uses = $script:Yaml.jobs.bump.steps.uses
        $uses | Should -Contain 'actions/checkout@v4'
    }

    It 'runs the bumper through pwsh shell' {
        $shells = $script:Yaml.jobs.bump.steps.shell | Where-Object { $_ }
        $shells | Should -Contain 'pwsh'
    }

    It 'declares least-privilege permissions' {
        $script:Yaml.permissions.contents | Should -Be 'read'
    }

    It 'references the bumper script that actually exists on disk' {
        $runText = ($script:Yaml.jobs.bump.steps.run -join "`n")
        $runText | Should -Match 'Invoke-Bumper\.ps1'
        (Test-Path (Join-Path $script:RepoRoot 'Invoke-Bumper.ps1')) | Should -BeTrue
        (Test-Path (Join-Path $script:RepoRoot 'src' 'SemanticVersionBumper.psm1')) | Should -BeTrue
    }
}

Describe 'actionlint validation' {
    It 'passes actionlint with exit code 0' {
        $out = & actionlint $script:WorkflowPath 2>&1
        $code = $LASTEXITCODE
        if ($code -ne 0) { Write-Host ($out | Out-String) }
        $code | Should -Be 0
    }
}

Describe 'act end-to-end pipeline' {

    It 'produced an act-result.txt artifact' {
        Test-Path $script:ActResult | Should -BeTrue
    }

    It '<Name> exits 0, job succeeds, and produces version <Expected>' -ForEach $Cases {
        $res = $script:Results[$Name]
        $res | Should -Not -BeNullOrEmpty

        # 1. act must exit 0 for this case.
        $res.ExitCode | Should -Be 0 -Because "act should succeed for case '$Name'"

        # 2. Every job must report success.
        $res.Output | Should -Match 'Job succeeded'

        # 3. EXACT expected version must be emitted by the pipeline.
        $res.Output | Should -Match ([regex]::Escape("NEW_VERSION=$Expected"))

        # 4. The classified bump type must match too.
        $res.Output | Should -Match ([regex]::Escape("BUMP_TYPE=$BumpType"))
    }
}
