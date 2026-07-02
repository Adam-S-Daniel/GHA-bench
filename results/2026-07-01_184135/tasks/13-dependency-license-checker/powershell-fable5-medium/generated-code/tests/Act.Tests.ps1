<#
.SYNOPSIS
    End-to-end pipeline tests: every test case runs THROUGH the GitHub
    Actions workflow via `act push` (nektos/act) in an isolated temp repo.

.DESCRIPTION
    For each case:
      1. Build a temp git repo containing the project files plus that case's
         fixture manifest(s) committed under test-input/.
      2. Run `act push --rm` against it (one act run per case, 3 total).
      3. Append the full act output to act-result.txt (delimited per case).
      4. Assert exit code 0, "Job succeeded" for BOTH jobs, and the EXACT
         expected RESULT|/SUMMARY| lines for that case's input.

    NOTE: these tests invoke Docker and take ~1-2 minutes per case.
#>

BeforeDiscovery {
    # Case table is needed at discovery time to generate the Context blocks.
    $script:ActCases = @(
        @{
            CaseName   = 'case1-npm'
            FixtureDir = 'fixtures/case1-npm'
            Expected   = @(
                'MANIFEST|package.json'
                'RESULT|evil-lib|2.0.0|GPL-3.0|Denied'
                'RESULT|express|4.18.2|MIT|Approved'
                'RESULT|left-pad|1.3.0|UNKNOWN|Unknown'
                'SUMMARY|Approved=1|Denied=1|Unknown=1|Total=3'
            )
        }
        @{
            CaseName   = 'case2-pip'
            FixtureDir = 'fixtures/case2-pip'
            Expected   = @(
                'MANIFEST|requirements.txt'
                'RESULT|flask|3.0.0|BSD-3-Clause|Approved'
                'RESULT|mystery-pkg|0.1.0|SSPL-1.0|Denied'
                'RESULT|requests|2.31.0|Apache-2.0|Approved'
                'SUMMARY|Approved=2|Denied=1|Unknown=0|Total=3'
            )
        }
        @{
            CaseName   = 'case3-mixed'
            FixtureDir = 'fixtures/case3-mixed'
            Expected   = @(
                'MANIFEST|package.json'
                'RESULT|evil-lib|2.0.0|GPL-3.0|Denied'
                'RESULT|express|4.18.2|MIT|Approved'
                'RESULT|left-pad|1.3.0|UNKNOWN|Unknown'
                'SUMMARY|Approved=1|Denied=1|Unknown=1|Total=3'
                'MANIFEST|requirements.txt'
                'RESULT|flask|3.0.0|BSD-3-Clause|Approved'
                'RESULT|mystery-pkg|0.1.0|SSPL-1.0|Denied'
                'RESULT|requests|2.31.0|Apache-2.0|Approved'
                'SUMMARY|Approved=2|Denied=1|Unknown=0|Total=3'
            )
        }
    )
}

BeforeAll {
    $script:RepoRoot   = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:ResultFile = Join-Path $script:RepoRoot 'act-result.txt'
    # Fresh result artifact for this run.
    Set-Content -Path $script:ResultFile -Value "act test run started`n"

    function script:Invoke-ActCase {
        param([string]$CaseName, [string]$FixtureDir)

        # 1. Assemble an isolated repo: project files + this case's fixture
        #    manifests as test-input/ (the directory the workflow audits).
        $tempRepo = Join-Path ([IO.Path]::GetTempPath()) "act-$CaseName-$([guid]::NewGuid().ToString('N').Substring(0,8))"
        New-Item -ItemType Directory -Path $tempRepo | Out-Null
        foreach ($item in '.github', 'src', 'scripts', 'config', 'fixtures', 'tests') {
            Copy-Item -Recurse (Join-Path $script:RepoRoot $item) (Join-Path $tempRepo $item)
        }
        # The act harness itself must not run inside the container.
        Remove-Item (Join-Path $tempRepo 'tests/Act.Tests.ps1') -Force
        New-Item -ItemType Directory -Path (Join-Path $tempRepo 'test-input') | Out-Null
        Copy-Item (Join-Path $script:RepoRoot $FixtureDir '*') (Join-Path $tempRepo 'test-input') -Recurse

        git -C $tempRepo init -q -b main
        git -C $tempRepo -c user.email=ci@test.local -c user.name=ci add -A
        git -C $tempRepo -c user.email=ci@test.local -c user.name=ci commit -q -m "fixture $CaseName"

        # 2. Run the workflow through act with the pwsh-enabled runner image.
        Push-Location $tempRepo
        try {
            $output = & act push --rm --pull=false `
                -P ubuntu-latest=act-ubuntu-pwsh:latest 2>&1 | Out-String
            $exitCode = $LASTEXITCODE
        }
        finally {
            Pop-Location
            Remove-Item -Recurse -Force $tempRepo -ErrorAction SilentlyContinue
        }

        # 3. Append delimited output to the required artifact.
        Add-Content -Path $script:ResultFile -Value @(
            "===================== CASE: $CaseName (exit=$exitCode) ====================="
            $output
            "===================== END CASE: $CaseName ====================="
        )

        @{ ExitCode = $exitCode; Output = $output }
    }
}

Describe 'Workflow end-to-end via act' {
    Context '<CaseName>' -ForEach $script:ActCases {
        BeforeAll {
            $script:Run = Invoke-ActCase -CaseName $CaseName -FixtureDir $FixtureDir
        }

        It 'act exits with code 0' {
            $script:Run.ExitCode | Should -Be 0
        }

        It 'both jobs report Job succeeded' {
            $script:Run.Output | Should -BeLike '*Pester unit tests*Job succeeded*'
            $script:Run.Output | Should -BeLike '*License compliance report*Job succeeded*'
        }

        It 'all 21 unit tests passed inside the pipeline' {
            $script:Run.Output | Should -BeLike '*PESTER|Passed=21|Failed=0*'
        }

        It "report contains the exact expected line: <_>" -ForEach $Expected {
            $script:Run.Output | Should -BeLike "*$_*"
        }
    }
}

AfterAll {
    Add-Content -Path $script:ResultFile -Value 'act test run finished'
}
