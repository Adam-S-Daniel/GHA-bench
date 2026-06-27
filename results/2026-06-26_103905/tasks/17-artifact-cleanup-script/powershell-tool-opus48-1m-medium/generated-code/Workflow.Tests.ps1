# Workflow.Tests.ps1
#
# End-to-end + structure tests for the GitHub Actions workflow.
#
#  * Structure tests parse the YAML and assert the expected triggers, jobs,
#    steps, and that the referenced script files exist; they also assert that
#    actionlint exits 0.
#  * The act tests run the FULL pipeline for each fixture case through
#    `act push --rm`, capture the output into act-result.txt, assert act exited
#    0, assert every job reports "Job succeeded", and assert the EXACT
#    PLAN_SUMMARY values produced for that case's input.
#
# Every functional assertion goes through the workflow via act — the script is
# never invoked directly here.

# Known-good expected results per fixture case, defined at DISCOVERY time so
# the data-driven `-ForEach` contexts below can expand. Values are derived by
# hand from each fixture's policies (see the README) so we assert exact
# results, not just "some output appeared".
$script:Cases = @(
    @{
        Name     = 'case-max-age'
        Fixture  = 'fixtures/case-max-age.json'
        Summary  = 'PLAN_SUMMARY total=3 deleted=2 retained=1 reclaimedBytes=950 retainedBytes=100 dryRun=true'
        Deletes  = @('DELETE name=ancient sizeBytes=700', 'DELETE name=old sizeBytes=250')
    },
    @{
        Name     = 'case-keep-latest'
        Fixture  = 'fixtures/case-keep-latest.json'
        Summary  = 'PLAN_SUMMARY total=5 deleted=1 retained=4 reclaimedBytes=30 retainedBytes=120 dryRun=true'
        Deletes  = @('DELETE name=w1-oldest sizeBytes=30')
    },
    @{
        Name     = 'case-combined'
        Fixture  = 'fixtures/case-combined.json'
        Summary  = 'PLAN_SUMMARY total=4 deleted=3 retained=1 reclaimedBytes=250 retainedBytes=100 dryRun=false'
        Deletes  = @('DELETE name=w1-extra sizeBytes=100', 'DELETE name=w2-keep sizeBytes=50', 'DELETE name=w2-old sizeBytes=100')
    }
)

BeforeAll {
    $script:ProjectRoot   = Split-Path -Parent $PSCommandPath
    $script:WorkflowPath  = Join-Path $script:ProjectRoot '.github/workflows/artifact-cleanup-script.yml'
    $script:ActResultPath = Join-Path $script:ProjectRoot 'act-result.txt'

    # Fresh act-result.txt for this run.
    Set-Content -LiteralPath $script:ActResultPath -Value "act run log - $($PSCommandPath)`n" -Encoding utf8

    # Helper: build an isolated temp git repo containing the project plus the
    # given case fixture mapped to fixtures/case.json, run act, and return the
    # combined output + exit code.
    function Invoke-ActForCase {
        param([string] $Name, [string] $Fixture)

        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("act-" + $Name + "-" + [guid]::NewGuid().ToString('N').Substring(0,8))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null

        try {
            # Copy the project files needed to run the workflow.
            Copy-Item (Join-Path $script:ProjectRoot 'ArtifactCleanup.psm1')        (Join-Path $tmp 'ArtifactCleanup.psm1')
            Copy-Item (Join-Path $script:ProjectRoot 'Invoke-ArtifactCleanup.ps1')  (Join-Path $tmp 'Invoke-ArtifactCleanup.ps1')
            Copy-Item (Join-Path $script:ProjectRoot 'ArtifactCleanup.Tests.ps1')   (Join-Path $tmp 'ArtifactCleanup.Tests.ps1')
            Copy-Item (Join-Path $script:ProjectRoot '.actrc')                       (Join-Path $tmp '.actrc')
            New-Item -ItemType Directory -Path (Join-Path $tmp '.github/workflows') -Force | Out-Null
            Copy-Item $script:WorkflowPath (Join-Path $tmp '.github/workflows/artifact-cleanup-script.yml')
            New-Item -ItemType Directory -Path (Join-Path $tmp 'fixtures') -Force | Out-Null
            # Map this case's fixture to the path the workflow reads.
            Copy-Item (Join-Path $script:ProjectRoot $Fixture) (Join-Path $tmp 'fixtures/case.json')

            # A git repo is required for actions/checkout under act.
            Push-Location $tmp
            try {
                git init -q 2>&1 | Out-Null
                git config user.email 'ci@example.com' 2>&1 | Out-Null
                git config user.name  'ci' 2>&1 | Out-Null
                git add -A 2>&1 | Out-Null
                git commit -qm 'fixture' 2>&1 | Out-Null

                $output = & act push --rm 2>&1 | Out-String
                $code   = $LASTEXITCODE
            }
            finally {
                Pop-Location
            }

            # Append to the shared act-result.txt with a clear delimiter.
            $delim = "`n========== ACT CASE: $Name (exit=$code) ==========`n"
            Add-Content -LiteralPath $script:ActResultPath -Value $delim -Encoding utf8
            Add-Content -LiteralPath $script:ActResultPath -Value $output -Encoding utf8

            return [pscustomobject]@{ Output = $output; ExitCode = $code }
        }
        finally {
            Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # Run every fixture case once, up front, and cache the results keyed by the
    # fixture base name (which matches the -ForEach case Name). Driving this from
    # the files on disk keeps it in run-phase scope (the discovery-scope
    # $script:Cases is not visible here) and avoids re-running act per It block.
    # The 'case-*.json' filter intentionally skips the default 'case.json'.
    $script:Results = @{}
    $fixtureFiles = Get-ChildItem -LiteralPath (Join-Path $script:ProjectRoot 'fixtures') -Filter 'case-*.json'
    foreach ($fx in $fixtureFiles) {
        $script:Results[$fx.BaseName] = Invoke-ActForCase -Name $fx.BaseName -Fixture "fixtures/$($fx.Name)"
    }
}

Describe 'Workflow structure' {

    It 'workflow file exists' {
        Test-Path -LiteralPath $script:WorkflowPath | Should -BeTrue
    }

    It 'passes actionlint with exit code 0' {
        & actionlint $script:WorkflowPath 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 0
    }

    Context 'Parsed YAML' {
        BeforeAll {
            # ConvertFrom-Yaml isn't guaranteed present; parse the structure we
            # care about from the raw text instead (robust + dependency-free).
            $script:Yaml = Get-Content -LiteralPath $script:WorkflowPath -Raw
        }

        It 'declares the expected trigger events' {
            foreach ($trigger in @('push:', 'pull_request:', 'schedule:', 'workflow_dispatch:')) {
                $script:Yaml | Should -Match ([regex]::Escape($trigger))
            }
        }

        It 'declares both jobs with a dependency edge' {
            $script:Yaml | Should -Match 'unit-tests:'
            $script:Yaml | Should -Match 'cleanup-plan:'
            $script:Yaml | Should -Match 'needs:\s*unit-tests'
        }

        It 'sets least-privilege permissions' {
            $script:Yaml | Should -Match 'permissions:'
            $script:Yaml | Should -Match 'contents:\s*read'
        }

        It 'references the script files via checkout and pwsh steps' {
            $script:Yaml | Should -Match 'actions/checkout@v4'
            $script:Yaml | Should -Match 'shell:\s*pwsh'
            $script:Yaml | Should -Match 'Invoke-ArtifactCleanup\.ps1'
            $script:Yaml | Should -Match 'ArtifactCleanup\.Tests\.ps1'
        }
    }

    It 'references script files that actually exist on disk' {
        foreach ($f in @('ArtifactCleanup.psm1', 'Invoke-ArtifactCleanup.ps1', 'ArtifactCleanup.Tests.ps1')) {
            Test-Path -LiteralPath (Join-Path $script:ProjectRoot $f) | Should -BeTrue
        }
    }
}

Describe 'Workflow execution through act' {

    It 'produced the act-result.txt artifact' {
        Test-Path -LiteralPath $script:ActResultPath | Should -BeTrue
    }

    Context 'Case <Name>' -ForEach $script:Cases {

        BeforeEach {
            $script:Res = $script:Results[$Name]
        }

        It 'act exited with code 0' {
            $script:Res.ExitCode | Should -Be 0
        }

        It 'every job reports Job succeeded' {
            # Two jobs (unit-tests, cleanup-plan) => two success markers.
            ([regex]::Matches($script:Res.Output, 'Job succeeded')).Count |
                Should -BeGreaterOrEqual 2
        }

        It 'reports the exact PLAN_SUMMARY for this case' {
            $script:Res.Output | Should -Match ([regex]::Escape($Summary))
        }

        It 'lists the exact artifacts to delete' {
            foreach ($d in $Deletes) {
                $script:Res.Output | Should -Match ([regex]::Escape($d))
            }
        }

        It 'reports PLAN_COMPLETE' {
            $script:Res.Output | Should -Match 'PLAN_COMPLETE'
        }
    }
}
