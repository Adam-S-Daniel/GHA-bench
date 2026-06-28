# Workflow.Tests.ps1
#
# Tests for the GitHub Actions workflow that wraps the semantic version bumper:
#
#   1. Structure tests  - parse the workflow YAML and assert it has the expected
#                         triggers, jobs, steps, outputs and script references,
#                         and that the referenced files actually exist.
#   2. actionlint       - run actionlint as a subprocess and assert exit code 0.
#   3. Execution (act)  - for each fixture case, build a temp git repo containing
#                         the project + that case's fixture data, run the workflow
#                         in Docker via `act push`, append the output to
#                         act-result.txt, and assert on the EXACT expected values
#                         (new version, previous version, bump type) as well as
#                         every job reporting success.
#
# Per the task, the functional bump scenarios are exercised ONLY through the
# pipeline (act), not by calling the script directly. Pester unit tests for the
# pure logic live in SemanticVersionBumper.Tests.ps1.

# ---------------------------------------------------------------------------
# Discovery-time data (top level so Pester's -ForEach can see it during
# discovery). Each case: the fixture folder name, plus the EXACT expected
# outputs the pipeline must produce for that fixture (the known-good results).
# ---------------------------------------------------------------------------

$Cases = @(
    @{ Name = 'minor'; Previous = '1.1.0'; New = '1.2.0'; Bump = 'minor' }
    @{ Name = 'patch'; Previous = '2.3.4'; New = '2.3.5'; Bump = 'patch' }
    @{ Name = 'major'; Previous = '0.5.2'; New = '1.0.0'; Bump = 'major' }
)

# Optional subset filter for fast local validation, e.g.
#   $env:SVB_ACT_CASES = 'minor'
# Defaults to all cases (required for the full act-result.txt artifact).
if (-not [string]::IsNullOrWhiteSpace($env:SVB_ACT_CASES)) {
    $wanted = $env:SVB_ACT_CASES.Split(',').ForEach({ $_.Trim() })
    $Cases = $Cases.Where({ $wanted -contains $_.Name })
}

# Run-phase setup. A top-level BeforeAll (run phase) defines the $script:-scoped
# paths AND the act helper so they are visible inside the deferred BeforeAll/It
# blocks of every Describe. (Top-level statements run only during discovery, so
# run-phase code must live in BeforeAll.)
BeforeAll {
    $script:ProjectRoot   = $PSScriptRoot
    $script:WorkflowPath  = Join-Path $script:ProjectRoot '.github/workflows/semantic-version-bumper.yml'
    $script:ActResultFile = Join-Path $script:ProjectRoot 'act-result.txt'

    # Helper: run one fixture case end-to-end through act. Returns the captured
    # output and exit code.
    function Invoke-ActCase {
        param(
            [hashtable] $Case,
            [string]    $ProjectRoot,
            [string]    $ReleaseDate = '2026-06-28'
        )

        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("svb-act-" + [System.Guid]::NewGuid())
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $tmp '.github/workflows') -Force | Out-Null

        try {
            # Copy the project files the workflow needs into the throwaway repo.
            Copy-Item (Join-Path $ProjectRoot 'Invoke-VersionBump.ps1')          $tmp
            Copy-Item (Join-Path $ProjectRoot 'SemanticVersionBumper.psm1')       $tmp
            Copy-Item (Join-Path $ProjectRoot 'SemanticVersionBumper.Tests.ps1')  $tmp
            Copy-Item (Join-Path $ProjectRoot 'CHANGELOG.md')                     $tmp
            Copy-Item (Join-Path $ProjectRoot '.actrc')                          $tmp
            Copy-Item (Join-Path $ProjectRoot '.github/workflows/semantic-version-bumper.yml') (Join-Path $tmp '.github/workflows')

            # This case's fixture data becomes the repo's VERSION + commit log.
            Copy-Item (Join-Path $ProjectRoot "fixtures/$($Case.Name)/VERSION")     (Join-Path $tmp 'VERSION')
            Copy-Item (Join-Path $ProjectRoot "fixtures/$($Case.Name)/commits.txt") (Join-Path $tmp 'commits.txt')

            Push-Location $tmp
            try {
                # Build a minimal git repo on a 'main' branch so the push event
                # matches the workflow's branch filter. symbolic-ref works on
                # every git version and never errors on an unborn branch.
                git init --quiet
                git symbolic-ref HEAD refs/heads/main
                git config user.email 'svb-test@example.com'
                git config user.name  'SVB Test'
                git add -A
                git commit --quiet -m "test: $($Case.Name) fixture" | Out-Null

                # Run the workflow in Docker. --pull=false because the image is
                # local-only (the .actrc maps ubuntu-latest -> act-ubuntu-pwsh).
                $output = & act push --rm --pull=false --env "RELEASE_DATE=$ReleaseDate" 2>&1 | Out-String
                $code = $LASTEXITCODE
            }
            finally {
                Pop-Location
            }

            return [pscustomobject]@{
                Output   = $output
                ExitCode = $code
            }
        }
        finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ---------------------------------------------------------------------------
# 1. Workflow structure
# ---------------------------------------------------------------------------

Describe 'Workflow structure' {
    BeforeAll {
        Import-Module powershell-yaml -ErrorAction Stop
        $script:RawYaml = Get-Content -LiteralPath $script:WorkflowPath -Raw
        $script:Wf = $script:RawYaml | ConvertFrom-Yaml
    }

    It 'is valid, parseable YAML' {
        $script:Wf | Should -Not -BeNullOrEmpty
        $script:Wf.Keys | Should -Contain 'jobs'
    }

    It 'declares the expected trigger events' {
        # powershell-yaml keeps the "on" key as a string (no boolean coercion).
        $triggers = $script:Wf['on']
        $triggers.Keys | Should -Contain 'push'
        $triggers.Keys | Should -Contain 'pull_request'
        $triggers.Keys | Should -Contain 'schedule'
        $triggers.Keys | Should -Contain 'workflow_dispatch'
    }

    It 'sets workflow-level permissions' {
        $script:Wf.Keys | Should -Contain 'permissions'
    }

    It 'defines a bump job and a verify job' {
        $script:Wf['jobs'].Keys | Should -Contain 'bump'
        $script:Wf['jobs'].Keys | Should -Contain 'verify'
    }

    It 'makes the verify job depend on the bump job' {
        $script:Wf['jobs']['verify']['needs'] | Should -Be 'bump'
    }

    It 'exposes the new version as a bump-job output' {
        $script:Wf['jobs']['bump']['outputs'].Keys | Should -Contain 'new_version'
    }

    It 'checks out the repo with actions/checkout@v4' {
        $uses = $script:Wf['jobs']['bump']['steps'] | ForEach-Object { $_['uses'] }
        $uses | Should -Contain 'actions/checkout@v4'
    }

    It 'runs the bumper script using shell: pwsh' {
        $bumpStep = $script:Wf['jobs']['bump']['steps'] | Where-Object { $_['id'] -eq 'bump' }
        $bumpStep | Should -Not -BeNullOrEmpty
        $bumpStep['shell'] | Should -Be 'pwsh'
        $bumpStep['run']   | Should -Match 'Invoke-VersionBump\.ps1'
    }
}

# ---------------------------------------------------------------------------
# 2. Referenced files exist on disk
# ---------------------------------------------------------------------------

Describe 'Workflow references existing project files' {
    It 'references Invoke-VersionBump.ps1, which exists' {
        (Get-Content -LiteralPath $script:WorkflowPath -Raw) | Should -Match 'Invoke-VersionBump\.ps1'
        Test-Path (Join-Path $script:ProjectRoot 'Invoke-VersionBump.ps1') | Should -BeTrue
    }

    It 'ships the module the script imports' {
        Test-Path (Join-Path $script:ProjectRoot 'SemanticVersionBumper.psm1') | Should -BeTrue
    }

    It 'provides every fixture case referenced by the test harness' -ForEach $Cases {
        Test-Path (Join-Path $script:ProjectRoot "fixtures/$Name/VERSION")     | Should -BeTrue
        Test-Path (Join-Path $script:ProjectRoot "fixtures/$Name/commits.txt") | Should -BeTrue
    }
}

# ---------------------------------------------------------------------------
# 3. actionlint static validation
# ---------------------------------------------------------------------------

Describe 'actionlint validation' {
    It 'passes actionlint with exit code 0' {
        $out = & actionlint $script:WorkflowPath 2>&1 | Out-String
        $code = $LASTEXITCODE
        if ($code -ne 0) { Write-Host $out }
        $code | Should -Be 0
    }
}

# ---------------------------------------------------------------------------
# 4. Workflow execution via act (every functional case runs through the pipeline)
# ---------------------------------------------------------------------------

Describe 'Workflow execution via act' {
    BeforeAll {
        # Start a fresh artifact file for this run.
        $header = "Semantic Version Bumper - act execution log`nGenerated by Workflow.Tests.ps1`n"
        Set-Content -LiteralPath $script:ActResultFile -Value $header
    }

    It 'bumps the <Name> case to exactly <New> through the pipeline' -ForEach $Cases {
        $result = Invoke-ActCase -Case $_ -ProjectRoot $script:ProjectRoot

        # Persist the full output to the required artifact BEFORE asserting, so
        # the log is captured even if an assertion below fails.
        $delim = "`n" + ('=' * 78) + "`n"
        $banner = "CASE: $Name  (expect previous=$Previous new=$New bump=$Bump)  exit=$($result.ExitCode)"
        Add-Content -LiteralPath $script:ActResultFile -Value ($delim + $banner + $delim + $result.Output)

        # act must exit cleanly.
        $result.ExitCode | Should -Be 0 -Because "act push should succeed for the $Name case"

        # Exact-value assertions on the bump-job output (\b prevents 1.2.0 from
        # matching a longer string like 1.2.05).
        $result.Output | Should -Match ("PREVIOUS_VERSION=" + [regex]::Escape($Previous) + '\b')
        $result.Output | Should -Match ("BUMP_TYPE=" + [regex]::Escape($Bump) + '\b')
        $result.Output | Should -Match ("NEW_VERSION=" + [regex]::Escape($New) + '\b')

        # The downstream verify job must have received the same value via the
        # job output (proves cross-job wiring works).
        $result.Output | Should -Match ("VERIFIED_NEW_VERSION=" + [regex]::Escape($New) + '\b')

        # Both jobs (bump, verify) must report success, and none may fail.
        $succeeded = ([regex]::Matches($result.Output, 'Job succeeded')).Count
        $succeeded | Should -BeGreaterOrEqual 2 -Because 'both the bump and verify jobs must succeed'
        $result.Output | Should -Not -Match 'Job failed'
    }

    It 'produced the act-result.txt artifact' {
        Test-Path $script:ActResultFile | Should -BeTrue
        (Get-Content -LiteralPath $script:ActResultFile -Raw).Length | Should -BeGreaterThan 0
    }
}
