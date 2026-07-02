<#
.SYNOPSIS
    End-to-end pipeline tests: run every test case THROUGH the GitHub Actions
    workflow with nektos/act, and assert on exact known-good output values.

.DESCRIPTION
    For each test case this harness:
      1. Builds a temp git repo containing the project files plus the case's
         fixture manifest under test-input/ (the workflow picks that up).
      2. Runs `act push --rm` against the repo.
      3. Appends the full act output to act-result.txt (clearly delimited).
      4. Asserts act exited 0, that every job reports "Job succeeded", and
         that the report lines match the case's exact expected values.

    NOTE: each Describe below costs one `act push` run (~30-90 s, requires
    Docker). Run selectively during development:
        Invoke-Pester -Path tests/Act.Tests.ps1
#>

BeforeDiscovery {
    # One entry per pipeline test case: which fixture goes into test-input/
    # and the exact report lines the workflow must produce for it.
    $script:actCases = @(
        @{
            CaseId   = 1
            Label    = 'npm manifest (package.json)'
            Fixture  = 'fixtures/package.json'
            Expected = @(
                'RESULT|express|4.18.2|MIT|approved'
                'RESULT|left-pad|1.3.0|WTFPL|denied'
                'RESULT|mystery-lib|2.0.0|UNKNOWN|unknown'
            )
            Summary  = 'SUMMARY|approved=1|denied=1|unknown=1'
        }
        @{
            CaseId   = 2
            Label    = 'pip manifest (requirements.txt)'
            Fixture  = 'fixtures/requirements.txt'
            Expected = @(
                'RESULT|requests|2.31.0|Apache-2.0|approved'
                'RESULT|flask|2.3.0|BSD-3-Clause|approved'
                'RESULT|copyleft-lib|1.0.0|GPL-3.0|denied'
                'RESULT|unknown-package|0.5.0|UNKNOWN|unknown'
            )
            Summary  = 'SUMMARY|approved=2|denied=1|unknown=1'
        }
    )
}

BeforeAll {
    $script:root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:resultFile = Join-Path $root 'act-result.txt'

    function Invoke-ActCase {
        <#
            Set up an isolated git repo for one test case and push it through
            the workflow with act. Returns the captured output + exit code.
        #>
        param(
            [Parameter(Mandatory)][int]$CaseId,
            [Parameter(Mandatory)][string]$Label,
            [Parameter(Mandatory)][string]$Fixture
        )

        $repo = Join-Path ([IO.Path]::GetTempPath()) "license-checker-act-case$CaseId"
        if (Test-Path $repo) { Remove-Item $repo -Recurse -Force }
        New-Item -ItemType Directory -Path $repo | Out-Null

        # Project files the workflow needs inside the container.
        Copy-Item (Join-Path $root 'DependencyLicenseChecker.psm1') $repo
        Copy-Item (Join-Path $root 'check-licenses.ps1') $repo
        Copy-Item (Join-Path $root '.actrc') $repo
        Copy-Item (Join-Path $root 'fixtures') (Join-Path $repo 'fixtures') -Recurse
        Copy-Item (Join-Path $root '.github') (Join-Path $repo '.github') -Recurse
        New-Item -ItemType Directory -Path (Join-Path $repo 'tests') | Out-Null
        Copy-Item (Join-Path $root 'tests/DependencyLicenseChecker.Tests.ps1') (Join-Path $repo 'tests')
        Copy-Item (Join-Path $root 'tests/Workflow.Tests.ps1') (Join-Path $repo 'tests')

        # The case-specific manifest the license-check job will pick up.
        New-Item -ItemType Directory -Path (Join-Path $repo 'test-input') | Out-Null
        Copy-Item (Join-Path $root $Fixture) (Join-Path $repo 'test-input')

        Push-Location $repo
        try {
            git init -q -b main 2>&1 | Out-Null
            git -c user.email='ci@example.com' -c user.name='CI Harness' add -A 2>&1 | Out-Null
            git -c user.email='ci@example.com' -c user.name='CI Harness' commit -q -m "case ${CaseId}: $Label" 2>&1 | Out-Null

            # --pull=false / offline mode: use the local runner image and the
            # cached actions/checkout so no network is required.
            $output = & act push --rm --pull=false --action-offline-mode 2>&1 |
                ForEach-Object { "$_" }
            $exitCode = $LASTEXITCODE
        }
        finally {
            Pop-Location
        }

        # Persist the evidence, clearly delimited per case (required artifact).
        $delimiter = "==================== CASE ${CaseId}: $Label ===================="
        Add-Content -Path $resultFile -Value $delimiter
        Add-Content -Path $resultFile -Value $output
        Add-Content -Path $resultFile -Value "-------------------- CASE $CaseId exit code: $exitCode --------------------`n"

        [pscustomobject]@{ Text = $output -join "`n"; ExitCode = $exitCode }
    }

    # Fresh artifact per harness run; cases append below.
    Set-Content -Path $resultFile -Value "act pipeline test results`n"
}

Describe 'workflow via act: case <CaseId> — <Label>' -ForEach $actCases {
    BeforeAll {
        $script:run = Invoke-ActCase -CaseId $CaseId -Label $Label -Fixture $Fixture
    }

    It 'act exits with code 0' {
        $run.ExitCode | Should -Be 0
    }

    It 'every job reports "Job succeeded" (test + license-check)' {
        ([regex]::Matches($run.Text, 'Job succeeded')).Count | Should -BeGreaterOrEqual 2
        $run.Text | Should -Match 'Pester unit tests.*Job succeeded'
        $run.Text | Should -Match 'License compliance report.*Job succeeded'
    }

    It 'emits the exact expected report line: <_>' -ForEach $Expected {
        $run.Text | Should -Match ([regex]::Escape($_))
    }

    It 'emits the exact expected summary: <Summary>' {
        $run.Text | Should -Match ([regex]::Escape($Summary))
    }

    It 'ran the Pester suite in CI with zero failures' {
        # The in-container Pester run prints its own tally; no failures
        # allowed. ANSI color codes may sit between the fields, hence `.*`.
        $run.Text | Should -Match 'Tests Passed: \d+,.*Failed: 0,'
    }
}

Describe 'act-result.txt artifact' {
    It 'exists and contains every case delimiter' {
        Test-Path $resultFile | Should -BeTrue
        $content = Get-Content $resultFile -Raw
        $content | Should -Match 'CASE 1: npm manifest'
        $content | Should -Match 'CASE 2: pip manifest'
    }
}
