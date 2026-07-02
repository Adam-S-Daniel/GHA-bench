#Requires -Modules Pester

# Harness that drives the real GitHub Actions workflow through `act`,
# proving it actually runs successfully in a Docker-based pipeline rather
# than only being asserted against statically.
#
# Tagged 'Act' so the workflow's own "Run unit tests" step (which invokes
# Invoke-Pester on the *other* test files) never picks this file up --
# running it from inside the very container `act` spins up would mean
# Docker-in-Docker, which is neither supported nor desired here. Run it
# explicitly with: Invoke-Pester -Path ./Tests/ActPipeline.Tests.ps1
#
# Our committed workflow (.github/workflows/secret-rotation-validator.yml)
# already embeds two independently-asserted, fixture-driven scenarios as
# two steps of the same job: mixed-secrets.json (a mix of expired/warning/ok
# secrets) and all-healthy-secrets.json (exercises the -FailOnExpired gate
# on a clean bill of health). Because a single `act push` invocation runs
# the entire workflow -- all jobs, all steps -- one invocation exercises
# both test cases end to end. We assert on both sets of exact expected
# values from that single invocation's captured output, which keeps us
# comfortably inside the "at most 3 act push runs" budget.

BeforeAll {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:ResultPath = Join-Path $RepoRoot 'act-result.txt'
}

Describe 'GitHub Actions workflow via act' -Tag 'Act' {

    BeforeAll {
        $script:TempRepo = Join-Path ([System.IO.Path]::GetTempPath()) ("secret-rotation-act-{0}" -f ([guid]::NewGuid()))
        New-Item -ItemType Directory -Path $TempRepo | Out-Null

        # Set up a temp git repo containing a copy of the project files
        # (this test case's fixture data is already part of the repo under
        # Tests/fixtures/, so no separate copy step is needed for it).
        Get-ChildItem -Path $RepoRoot -Force |
            Where-Object { $_.Name -notin @('.git', 'act-result.txt') } |
            ForEach-Object { Copy-Item -Path $_.FullName -Destination $TempRepo -Recurse -Force }

        Push-Location $TempRepo
        try {
            git init -q
            git config user.email 'act-harness@example.com'
            git config user.name 'Act Harness'
            git add -A
            git commit -q -m 'act harness test commit'

            $script:ActOutput = (& act push --rm 2>&1 | Out-String)
            $script:ActExitCode = $LASTEXITCODE
        } finally {
            Pop-Location
        }

        $header = @"
================================================================================
ACT PUSH INVOCATION
Workflow: .github/workflows/secret-rotation-validator.yml
Trigger: push
Exit code: $ActExitCode
Covers:
  TEST CASE 1: Tests/fixtures/mixed-secrets.json
               (expect Expired=2, Warning=3, Ok=1)
  TEST CASE 2: Tests/fixtures/all-healthy-secrets.json with -FailOnExpired
               (expect the fail-on-expired gate does not trigger)
================================================================================
"@
        Set-Content -LiteralPath $ResultPath -Value $header
        Add-Content -LiteralPath $ResultPath -Value $ActOutput
        Add-Content -LiteralPath $ResultPath -Value "================================================================================`nEND OF INVOCATION`n"
    }

    AfterAll {
        if (Test-Path $TempRepo) {
            Remove-Item -Recurse -Force $TempRepo -ErrorAction SilentlyContinue
        }
    }

    It 'exits with code 0' {
        $ActExitCode | Should -Be 0
    }

    It 'writes act-result.txt as a required artifact' {
        Test-Path $ResultPath | Should -BeTrue
    }

    It 'reports Job succeeded for the "test" job' {
        $ActOutput | Should -Match '\[Secret Rotation Validator/Run Pester unit tests\][^\n]*Job succeeded'
    }

    It 'reports Job succeeded for the "validate-secrets" job' {
        $ActOutput | Should -Match '\[Secret Rotation Validator/Validate secret rotation status\][^\n]*Job succeeded'
    }

    It 'reports no failed jobs' {
        $ActOutput | Should -Not -Match 'Job failed'
    }

    It 'TEST CASE 1 (mixed fixture): produces the exact expected Expired/Warning/Ok counts' {
        $ActOutput | Should -Match '"ExpiredCount":\s*2'
        $ActOutput | Should -Match '"WarningCount":\s*3'
        $ActOutput | Should -Match '"OkCount":\s*1'
        $ActOutput | Should -Match 'Mixed fixture check passed: Expired=2 Warning=3 Ok=1'
    }

    It 'TEST CASE 2 (all-healthy fixture): FailOnExpired gate passes with the exact expected message' {
        $ActOutput | Should -Match 'Healthy fixture check passed: FailOnExpired gate did not trigger'
    }
}
