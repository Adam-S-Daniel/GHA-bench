# Workflow.Tests.ps1
#
# Pester tests for the GitHub Actions integration. Two layers:
#
#   1. WORKFLOW STRUCTURE TESTS - parse the workflow YAML and assert on its
#      triggers / jobs / steps, confirm it references the project's scripts by
#      paths that exist, and confirm `actionlint` validates it cleanly.
#
#   2. ACT PIPELINE TESTS - every functional test case is executed *through the
#      workflow* via `act` (nektos/act). The expensive act runs are performed by
#      Invoke-ActHarness.ps1, which caches each case's output in act-results.json
#      and appends the raw logs to the act-result.txt artifact. These tests load
#      that cache and assert EXACT expected values (resolved combinations,
#      strategy size, fail-fast, max-parallel) for each case, plus that act
#      exited 0 and every job reported "Job succeeded".
#
# Run with:  Invoke-Pester -Path ./Workflow.Tests.ps1
#
# NOTE: this file is intentionally NOT the suite the workflow itself runs in CI
# (that is BuildMatrix.Tests.ps1). Keeping them separate prevents act-inside-act
# recursion.

# ---------------------------------------------------------------------------
# Discovery-phase data (must be top-level so -ForEach can see it).
#
# Each case's EXACT expected results were derived from the fixture by hand and
# confirmed against real act output:
#   * basic            - 2 os x 2 node = 4 combos, defaults (fail-fast true).
#   * exclude-include  - windows/18 excluded, ubuntu/20 gains coverage=true -> 3.
#   * include-new      - macos/21 is a brand-new include not matching any axis -> 3.
# Jobs = 1 generate + N build (one per combo) + 1 report.
# ---------------------------------------------------------------------------
$script:Cases = @(
    @{
        Case        = 'basic'
        Combos      = @('os=ubuntu-latest node=18', 'os=ubuntu-latest node=20',
                        'os=windows-latest node=18', 'os=windows-latest node=20')
        FailFast    = 'True'
        MaxParallel = ''      # not configured -> empty output
        Size        = 4
        Jobs        = 6       # 1 + 4 + 1
    },
    @{
        Case        = 'exclude-include'
        Combos      = @('os=ubuntu-latest node=18', 'os=ubuntu-latest node=20',
                        'os=windows-latest node=20')
        FailFast    = 'False'
        MaxParallel = '2'
        Size        = 3
        Jobs        = 5       # 1 + 3 + 1
    },
    @{
        Case        = 'include-new'
        Combos      = @('os=ubuntu-latest node=20', 'os=windows-latest node=20',
                        'os=macos-latest node=21')
        FailFast    = 'True'
        MaxParallel = '4'
        Size        = 3
        Jobs        = 5       # 1 + 3 + 1
    }
)

BeforeAll {
    $script:Root         = $PSScriptRoot
    $script:WorkflowPath = Join-Path $Root '.github/workflows/environment-matrix-generator.yml'
    $script:HarnessPath  = Join-Path $Root 'Invoke-ActHarness.ps1'
    $script:ResultsJson  = Join-Path $Root 'act-results.json'
    $script:ArtifactPath = Join-Path $Root 'act-result.txt'

    # --- Parse the workflow YAML once. --------------------------------------
    Import-Module powershell-yaml -ErrorAction Stop
    $script:Wf = ConvertFrom-Yaml (Get-Content -Raw $WorkflowPath)
    # `on` survives as a string key with powershell-yaml, but guard for the
    # YAML-1.1 boolean-coercion gotcha just in case.
    $script:OnNode = if ($Wf.Contains('on')) { $Wf['on'] } elseif ($Wf.Contains($true)) { $Wf[$true] } else { $null }

    # --- Ensure act results exist. ------------------------------------------
    # Invoke-ActHarness is idempotent: it only runs act for cases that have no
    # cached result, so this is a no-op once the artifact has been produced.
    if (-not (Test-Path $ResultsJson)) {
        & pwsh -NoProfile -File $HarnessPath | Out-Null
    }
    if (-not (Test-Path $ResultsJson)) {
        throw "act results not found at $ResultsJson and the harness did not produce them."
    }

    $loaded = Get-Content -Raw $ResultsJson | ConvertFrom-Json
    $script:ActResults = @{}
    foreach ($p in $loaded.PSObject.Properties) {
        $script:ActResults[$p.Name] = $p.Value
    }

    # Helper: count regex matches in a string.
    function script:Count-Match([string] $Text, [string] $Pattern) {
        return ([regex]::Matches($Text, $Pattern)).Count
    }
}

Describe 'Workflow structure' {

    It 'passes actionlint with exit code 0' {
        $null = & actionlint $script:WorkflowPath 2>&1
        $LASTEXITCODE | Should -Be 0
    }

    It 'is a single workflow named "Environment Matrix Generator"' {
        $script:Wf['name'] | Should -Be 'Environment Matrix Generator'
    }

    It 'declares all the expected trigger events' {
        $script:OnNode | Should -Not -BeNullOrEmpty
        $triggers = @($script:OnNode.Keys)
        $triggers | Should -Contain 'push'
        $triggers | Should -Contain 'pull_request'
        $triggers | Should -Contain 'workflow_dispatch'
        $triggers | Should -Contain 'schedule'
    }

    It 'sets least-privilege contents:read permissions' {
        $script:Wf['permissions']['contents'] | Should -Be 'read'
    }

    It 'defines the three expected jobs' {
        $jobs = @($script:Wf['jobs'].Keys)
        $jobs | Should -Contain 'generate'
        $jobs | Should -Contain 'build'
        $jobs | Should -Contain 'report'
    }

    It 'checks out the repo with actions/checkout@v4 in the generate job' {
        $uses = $script:Wf['jobs']['generate']['steps'] | ForEach-Object { $_['uses'] }
        $uses | Should -Contain 'actions/checkout@v4'
    }

    It 'runs the Pester unit-test suite in the generate job' {
        $runText = ($script:Wf['jobs']['generate']['steps'] | ForEach-Object { $_['run'] }) -join "`n"
        $runText | Should -Match 'Invoke-Pester'
        $runText | Should -Match 'BuildMatrix\.Tests\.ps1'
    }

    It 'invokes Generate-Matrix.ps1 in the generate job' {
        $runText = ($script:Wf['jobs']['generate']['steps'] | ForEach-Object { $_['run'] }) -join "`n"
        $runText | Should -Match 'Generate-Matrix\.ps1'
    }

    It 'uses shell: pwsh for every run step (PowerShell mode requirement)' {
        foreach ($jobName in $script:Wf['jobs'].Keys) {
            foreach ($step in $script:Wf['jobs'][$jobName]['steps']) {
                if ($step.Contains('run')) {
                    $step['shell'] | Should -Be 'pwsh' -Because "step '$($step['name'])' in job '$jobName' runs a script"
                }
            }
        }
    }

    It 'consumes the generated matrix dynamically via fromJSON of the generate output' {
        $script:Wf['jobs']['build']['needs'] | Should -Be 'generate'
        $script:Wf['jobs']['build']['strategy']['matrix'] |
            Should -Be '${{ fromJSON(needs.generate.outputs.matrix) }}'
    }

    It 'exposes the matrix and strategy settings as generate-job outputs' {
        $outputs = $script:Wf['jobs']['generate']['outputs']
        $outputs['matrix']       | Should -Match 'steps\.gen\.outputs\.matrix'
        $outputs['fail-fast']    | Should -Match 'steps\.gen\.outputs\.fail-fast'
        $outputs['max-parallel'] | Should -Match 'steps\.gen\.outputs\.max-parallel'
    }

    It 'references project script files that actually exist on disk' {
        foreach ($f in @('BuildMatrix.psm1', 'Generate-Matrix.ps1', 'BuildMatrix.Tests.ps1')) {
            Test-Path (Join-Path $script:Root $f) | Should -BeTrue -Because "$f is required by the workflow"
        }
    }
}

Describe 'Act pipeline produces the required artifact' {

    It 'wrote act-result.txt' {
        Test-Path $script:ArtifactPath | Should -BeTrue
    }

    It 'recorded a result for every test case' {
        foreach ($c in $script:Cases) {
            $script:ActResults.ContainsKey($c.Case) | Should -BeTrue -Because "case '$($c.Case)' must have run through act"
        }
    }

    It 'delimits each case clearly in the artifact' {
        $artifact = Get-Content -Raw $script:ArtifactPath
        foreach ($c in $script:Cases) {
            $artifact | Should -Match ("TEST CASE: " + [regex]::Escape($c.Case))
        }
    }
}

Describe 'Act pipeline: <Case>' -ForEach $script:Cases {

    BeforeEach {
        $script:Result = $script:ActResults[$Case]
        $script:Out    = $script:Result.output
    }

    It 'exited act with code 0' {
        $script:Result.exitCode | Should -Be 0
    }

    It 'ran the Pester unit suite inside CI with zero failures' {
        $script:Out | Should -Match 'Tests Passed: 32,'
        $script:Out | Should -Match 'Failed: 0,'
    }

    It 'reports the exact resolved matrix size (<Size>)' {
        # Surfaced both by Generate-Matrix (MATRIX_SIZE) and the report job (STRATEGY_SIZE).
        [regex]::Match($script:Out, 'MATRIX_SIZE=(\d+)').Groups[1].Value   | Should -Be ([string]$Size)
        [regex]::Match($script:Out, 'STRATEGY_SIZE=(\d+)').Groups[1].Value | Should -Be ([string]$Size)
    }

    It 'produces exactly the expected resolved combinations' {
        $got = [regex]::Matches($script:Out, 'BUILD_COMBO (os=\S+ node=\S+)') |
            ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
        $expected = $Combos | Sort-Object -Unique
        $got | Should -Be $expected
    }

    It 'launches exactly one build job per combination (<Size> build jobs)' {
        # Each matrix job is named "Build-N" by act.
        $buildJobs = Count-Match $script:Out 'Build-\d+[^\]]*\][^\n]*Job succeeded'
        $buildJobs | Should -Be $Size
    }

    It 'reports fail-fast=<FailFast> from the resolved strategy' {
        [regex]::Match($script:Out, 'STRATEGY_FAIL_FAST=([^\r\n]*)').Groups[1].Value.Trim() |
            Should -Be $FailFast
    }

    It 'reports max-parallel=<MaxParallel> from the resolved strategy' {
        [regex]::Match($script:Out, 'STRATEGY_MAX_PARALLEL=([^\r\n]*)').Groups[1].Value.Trim() |
            Should -Be $MaxParallel
    }

    It 'shows every job succeeding and none failing (<Jobs> jobs)' {
        (Count-Match $script:Out 'Job succeeded') | Should -Be $Jobs
        (Count-Match $script:Out 'Job failed')    | Should -Be 0
        # The two singleton jobs are present by name.
        $script:Out | Should -Match 'Generate matrix\][^\n]*Job succeeded'
        $script:Out | Should -Match 'Report strategy settings\][^\n]*Job succeeded'
    }
}
