#Requires -Modules Pester

<#
    Workflow.Tests.ps1

    Two kinds of tests:

      1. Structure / static validation of the GitHub Actions workflow
         (triggers, jobs, referenced script paths, actionlint clean).

      2. End-to-end tests that run the workflow through `act` (nektos/act) inside
         a Docker container. For each fixture case we build an isolated temp git
         repo containing the project files plus that case's fixture data, run
         `act push --rm`, capture the output to act-result.txt, and assert on the
         EXACT summary values the workflow is expected to print for that input.

    All script-under-test execution happens via the pipeline (act), never by
    calling the script directly.
#>

# Expected, known-good summary values for each fixture case. These are the heart
# of the test: the workflow must reproduce them exactly. Defined at script scope
# (not inside BeforeAll) so Pester can expand the -ForEach during DISCOVERY.
$script:Cases = @(
    @{ Name = 'case1-age';         DryRun = 'true';  Retained = 1; Deleted = 2; Reclaimed = 1500; RunIds = '101,201' }
    @{ Name = 'case2-keep-latest'; DryRun = 'false'; Retained = 2; Deleted = 1; Reclaimed = 100;  RunIds = '1' }
    @{ Name = 'case3-max-size';    DryRun = 'true';  Retained = 2; Deleted = 1; Reclaimed = 500;  RunIds = '1' }
)

BeforeAll {
    $script:ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:Workflow     = Join-Path $script:ProjectRoot '.github/workflows/artifact-cleanup-script.yml'
    $script:ActResult    = Join-Path $script:ProjectRoot 'act-result.txt'

    # Builds an isolated git repo for a case and runs the workflow via act.
    # Returns @{ ExitCode; Output }.
    function script:Invoke-ActForCase {
        param([string]$CaseName)

        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("act-" + $CaseName + "-" + ([System.IO.Path]::GetRandomFileName()))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        try {
            # Copy the files the workflow needs.
            Copy-Item (Join-Path $ProjectRoot 'ArtifactCleanup.psm1') $tmp
            Copy-Item (Join-Path $ProjectRoot 'Invoke-Cleanup.ps1') $tmp
            Copy-Item (Join-Path $ProjectRoot '.actrc') $tmp
            New-Item -ItemType Directory -Path (Join-Path $tmp '.github/workflows') -Force | Out-Null
            Copy-Item $Workflow (Join-Path $tmp '.github/workflows/')
            New-Item -ItemType Directory -Path (Join-Path $tmp 'tests') -Force | Out-Null
            Copy-Item (Join-Path $ProjectRoot 'tests/ArtifactCleanup.Tests.ps1') (Join-Path $tmp 'tests/')

            # Inject this case's fixture data at the path the workflow reads.
            New-Item -ItemType Directory -Path (Join-Path $tmp 'fixtures') -Force | Out-Null
            Copy-Item (Join-Path $ProjectRoot "tests/fixtures/$CaseName/artifacts.json") (Join-Path $tmp 'fixtures/artifacts.json')
            Copy-Item (Join-Path $ProjectRoot "tests/fixtures/$CaseName/policy.json") (Join-Path $tmp 'fixtures/policy.json')

            # act requires a git repo; the push trigger filters on main/master.
            Push-Location $tmp
            try {
                git init -b master *>&1 | Out-Null
                git config user.email 'ci@example.com' *>&1 | Out-Null
                git config user.name  'ci' *>&1 | Out-Null
                git add -A *>&1 | Out-Null
                git commit -m 'fixture' *>&1 | Out-Null

                # --pull=false: the act image is already present locally.
                $output = & act push --rm --pull=false 2>&1 | Out-String
                $code = $LASTEXITCODE
            } finally {
                Pop-Location
            }
            return @{ ExitCode = $code; Output = $output }
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Workflow static structure' {
    BeforeAll { $script:yaml = Get-Content -LiteralPath $script:Workflow -Raw }

    It 'is valid according to actionlint' {
        & actionlint $script:Workflow
        $LASTEXITCODE | Should -Be 0
    }

    It 'declares the expected trigger events' {
        $script:yaml | Should -Match '(?m)^\s*push:'
        $script:yaml | Should -Match '(?m)^\s*pull_request:'
        $script:yaml | Should -Match '(?m)^\s*schedule:'
        $script:yaml | Should -Match '(?m)^\s*workflow_dispatch:'
    }

    It 'declares least-privilege permissions' {
        $script:yaml | Should -Match 'contents:\s*read'
    }

    It 'defines a test job and a cleanup job with a dependency' {
        $script:yaml | Should -Match '(?m)^\s*test:'
        $script:yaml | Should -Match '(?m)^\s*cleanup:'
        $script:yaml | Should -Match 'needs:\s*test'
    }

    It 'uses actions/checkout@v4 and the pwsh shell' {
        $script:yaml | Should -Match 'actions/checkout@v4'
        $script:yaml | Should -Match 'shell:\s*pwsh'
    }

    It 'references scripts that actually exist in the repo' {
        $script:yaml | Should -Match 'Invoke-Cleanup\.ps1'
        $script:yaml | Should -Match 'tests/ArtifactCleanup\.Tests\.ps1'
        Test-Path (Join-Path $script:ProjectRoot 'Invoke-Cleanup.ps1') | Should -BeTrue
        Test-Path (Join-Path $script:ProjectRoot 'ArtifactCleanup.psm1') | Should -BeTrue
        Test-Path (Join-Path $script:ProjectRoot 'tests/ArtifactCleanup.Tests.ps1') | Should -BeTrue
    }
}

Describe 'Workflow end-to-end via act' {
    BeforeAll {
        # Fresh result file for this run; each case appends a delimited block.
        Set-Content -LiteralPath $script:ActResult -Value "ACT RESULTS`n" -Encoding utf8
    }

    It 'runs case <_.Name> and produces the exact expected deletion plan' -ForEach $script:Cases {
        $case = $_
        $run = Invoke-ActForCase -CaseName $case.Name

        # Persist the full act output for this case, clearly delimited.
        Add-Content -LiteralPath $script:ActResult -Value "`n===== CASE: $($case.Name) (exit=$($run.ExitCode)) =====" -Encoding utf8
        Add-Content -LiteralPath $script:ActResult -Value $run.Output -Encoding utf8

        $out = $run.Output

        # act (and thus the whole pipeline) must succeed.
        $run.ExitCode | Should -Be 0 -Because "act should exit 0 for $($case.Name)"

        # Both jobs must report success.
        ([regex]::Matches($out, 'Job succeeded')).Count | Should -BeGreaterOrEqual 2

        # Exact expected summary values for this fixture.
        $out | Should -Match ("DRY_RUN=" + $case.DryRun)
        $out | Should -Match ("RETAINED_COUNT=" + $case.Retained)
        $out | Should -Match ("DELETED_COUNT=" + $case.Deleted)
        $out | Should -Match ("SPACE_RECLAIMED=" + $case.Reclaimed)
        $out | Should -Match ("DELETED_RUN_IDS=" + [regex]::Escape($case.RunIds))
    }

    It 'leaves act-result.txt on disk as the required artifact' {
        Test-Path $script:ActResult | Should -BeTrue
    }
}
