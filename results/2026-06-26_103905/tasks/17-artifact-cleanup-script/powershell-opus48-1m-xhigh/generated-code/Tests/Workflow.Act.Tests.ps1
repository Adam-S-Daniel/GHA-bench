# Act integration harness.
#
# Drives the workflow end-to-end through nektos/act in a throwaway git repo and
# asserts on the EXACT values the pipeline prints for every fixture/test case.
#
# Design note on the act-run budget: the workflow's cleanup job loops over *all*
# fixtures in a single run, so one `act push` executes every test case through
# the pipeline. We therefore need exactly one act invocation to cover the whole
# matrix, and we assert the per-case results out of that single run's output.
#
# Tagged 'Act' so it can be included/excluded independently (it needs Docker and
# takes ~1 minute, unlike the fast unit/structure suites).

# Known-good expected values for each fixture, computed from the retention rules
# and pinned so the harness asserts EXACT output, not just "a number". Declared
# at the top level (discovery time) so Pester's data-driven -ForEach can see it.
$expectedCases = @(
    @{ Case = 'standard.json';      Total = 7; Retained = 4; Deleted = 3; ReclaimedBytes = 4296704; ReclaimedHuman = '4.1 MB';  DryRun = 'true' }
    @{ Case = 'age-only.json';      Total = 4; Retained = 2; Deleted = 2; ReclaimedBytes = 6000;    ReclaimedHuman = '5.86 KB'; DryRun = 'true' }
    @{ Case = 'keep-and-size.json'; Total = 5; Retained = 1; Deleted = 4; ReclaimedBytes = 3600;    ReclaimedHuman = '3.52 KB'; DryRun = 'true' }
)

BeforeAll {
    $script:Root      = Split-Path -Parent $PSScriptRoot
    $script:ResultLog = Join-Path $script:Root 'act-result.txt'

    if (-not (Get-Command act -ErrorAction SilentlyContinue)) {
        throw "act is not installed; the integration harness cannot run."
    }

    # --- Build an isolated git repo containing only the project files ----------
    $script:TempRepo = Join-Path ([System.IO.Path]::GetTempPath()) ("act-artifact-cleanup-" + (New-Guid).ToString('N'))
    New-Item -ItemType Directory -Path $script:TempRepo -Force | Out-Null

    $copy = @(
        'ArtifactCleanup.psm1',
        'Invoke-ArtifactCleanup.ps1',
        '.actrc'
    )
    foreach ($file in $copy) {
        Copy-Item -LiteralPath (Join-Path $script:Root $file) -Destination (Join-Path $script:TempRepo $file) -Force
    }
    Copy-Item -LiteralPath (Join-Path $script:Root 'fixtures') -Destination (Join-Path $script:TempRepo 'fixtures') -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $script:Root '.github')  -Destination (Join-Path $script:TempRepo '.github')  -Recurse -Force

    # The workflow only runs the unit test file, so that is all the pipeline needs.
    New-Item -ItemType Directory -Path (Join-Path $script:TempRepo 'Tests') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $script:Root 'Tests/ArtifactCleanup.Tests.ps1') `
              -Destination (Join-Path $script:TempRepo 'Tests/ArtifactCleanup.Tests.ps1') -Force

    Push-Location $script:TempRepo
    try {
        git init -q -b main 2>&1 | Out-Null
        git -c user.email='ci@example.com' -c user.name='ci' add -A 2>&1 | Out-Null
        git -c user.email='ci@example.com' -c user.name='ci' commit -q -m 'act fixture repo' 2>&1 | Out-Null

        # --- Single act run exercising every fixture through the pipeline ------
        # --pull=false: the runner image (act-ubuntu-pwsh) is built locally and
        # has no registry to pull from.
        $script:ActArgs = @('push', '--rm', '--pull=false')
        $script:ActOutput = (& act @script:ActArgs 2>&1 | Out-String)
        $script:ActExit = $LASTEXITCODE
    } finally {
        Pop-Location
    }

    # --- Persist the required artifact ----------------------------------------
    $header = @(
        '################################################################'
        '# ACT INTEGRATION RESULTS'
        "# Command:   act $($script:ActArgs -join ' ')"
        "# Exit code: $($script:ActExit)"
        '# Each fixture/test case is delimited by "=== CASE: <name> ===" /'
        '#   "=== END CASE: <name> ===" markers emitted by the script.'
        '################################################################'
        ''
    ) -join [Environment]::NewLine
    Set-Content -LiteralPath $script:ResultLog -Value ($header + $script:ActOutput) -Encoding utf8

    # Helper: pull the output block for a single fixture case.
    function Get-CaseBlock {
        param([string]$Name)
        $escaped = [regex]::Escape($Name)
        $pattern = "(?s)=== CASE: $escaped ===(.*?)=== END CASE: $escaped ==="
        $m = [regex]::Match($script:ActOutput, $pattern)
        if (-not $m.Success) { return $null }
        return $m.Groups[1].Value
    }
}

AfterAll {
    if ($script:TempRepo -and (Test-Path $script:TempRepo)) {
        Remove-Item -LiteralPath $script:TempRepo -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Act pipeline run' -Tag 'Act' {

    It 'writes the act-result.txt artifact' {
        Test-Path -LiteralPath $script:ResultLog | Should -BeTrue
    }

    It 'exits with code 0' {
        $script:ActExit | Should -Be 0 -Because "act output:`n$script:ActOutput"
    }

    It 'runs the Pester unit tests inside the pipeline' {
        $script:ActOutput | Should -Match 'Tests Passed:\s*\d+'
        $script:ActOutput | Should -Not -Match 'Tests Passed:\s*0,'
    }

    It 'reports "Job succeeded" for the <JobName> job' -ForEach @(
        @{ JobName = 'Pester unit tests' }
        @{ JobName = 'Generate cleanup plan' }
    ) {
        # act prints e.g. "[Artifact Cleanup/Pester unit tests] 🏁  Job succeeded"
        $script:ActOutput | Should -Match ([regex]::Escape($JobName) + '.*Job succeeded')
    }

    It 'shows a Job succeeded line for every job (>= 2)' {
        $succeeded = ([regex]::Matches($script:ActOutput, 'Job succeeded')).Count
        $succeeded | Should -BeGreaterOrEqual 2
    }
}

Describe 'Act pipeline - exact per-case results' -Tag 'Act' {

    It 'produces a delimited output block for <Case>' -ForEach $expectedCases {
        Get-CaseBlock -Name $Case | Should -Not -BeNullOrEmpty
    }

    It 'reports exact metrics for <Case>' -ForEach $expectedCases {
        $block = Get-CaseBlock -Name $Case
        $block | Should -Not -BeNullOrEmpty -Because "case '$Case' block must exist in act output"

        ([regex]::Match($block, 'ARTIFACTS_TOTAL=(\d+)')).Groups[1].Value      | Should -Be ([string]$Total)
        ([regex]::Match($block, 'ARTIFACTS_RETAINED=(\d+)')).Groups[1].Value   | Should -Be ([string]$Retained)
        ([regex]::Match($block, 'ARTIFACTS_DELETED=(\d+)')).Groups[1].Value    | Should -Be ([string]$Deleted)
        ([regex]::Match($block, 'SPACE_RECLAIMED_BYTES=(\d+)')).Groups[1].Value | Should -Be ([string]$ReclaimedBytes)
        ([regex]::Match($block, 'SPACE_RECLAIMED_HUMAN=([^\r\n]+)')).Groups[1].Value.Trim() | Should -Be $ReclaimedHuman
        ([regex]::Match($block, 'DRY_RUN=(\w+)')).Groups[1].Value              | Should -Be $DryRun
    }
}
