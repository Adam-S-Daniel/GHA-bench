<#
.SYNOPSIS
    End-to-end pipeline tests: every test case runs THROUGH the GitHub
    Actions workflow via `act push` in Docker.

.DESCRIPTION
    For each case the harness:
      1. builds a temp git repo containing the project files plus that
         case's fixture data (VERSION + commit-log.txt contents),
      2. runs `act push --rm` against it,
      3. appends the full act output to act-result.txt in the repo root,
      4. asserts act exited 0, that every job reports "Job succeeded",
         and that the output contains the EXACT expected new version
         (e.g. "NEW_VERSION=1.2.0") and changelog lines.

    Tagged 'Act' (requires Docker + act; excluded from the in-container
    CI test job, which only runs tests/unit).
#>

BeforeDiscovery {
    # Cases are needed at discovery time to generate one It per case.
    $script:ActCases = @(
        @{
            Name            = 'feat commit bumps minor: 1.1.0 -> 1.2.0'
            Version         = '1.1.0'
            CommitLog       = 'feat.txt'
            ExpectedVersion = '1.2.0'
            ChangelogChecks = @('### Features', '- add user login endpoint', '- **ui:** add dark mode toggle')
        }
        @{
            Name            = 'fix commit bumps patch: 2.3.4 -> 2.3.5'
            Version         = '2.3.4'
            CommitLog       = 'fix.txt'
            ExpectedVersion = '2.3.5'
            ChangelogChecks = @('### Bug Fixes', '- handle null auth token gracefully')
        }
        @{
            Name            = 'breaking commit bumps major: 1.5.2 -> 2.0.0'
            Version         = '1.5.2'
            CommitLog       = 'breaking.txt'
            ExpectedVersion = '2.0.0'
            ChangelogChecks = @('### Breaking Changes', '- drop legacy v1 API endpoints')
        }
    )
}

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    $script:ActResultFile = Join-Path $RepoRoot 'act-result.txt'

    # Fresh act-result.txt per suite run; each case appends to it.
    Remove-Item $ActResultFile -Force -ErrorAction SilentlyContinue
}

Describe 'Workflow execution through act' -Tag 'Act' {
    It '<Name>' -ForEach $script:ActCases {
        # --- 1. Temp git repo with project files + case fixture data ---
        $tempRepo = Join-Path ([IO.Path]::GetTempPath()) "svb-act-$([guid]::NewGuid())"
        New-Item -ItemType Directory -Path $tempRepo | Out-Null
        try {
            Copy-Item -Recurse (Join-Path $RepoRoot 'src') (Join-Path $tempRepo 'src')
            Copy-Item -Recurse (Join-Path $RepoRoot 'fixtures') (Join-Path $tempRepo 'fixtures')
            New-Item -ItemType Directory (Join-Path $tempRepo 'tests') | Out-Null
            Copy-Item -Recurse (Join-Path $RepoRoot 'tests' 'unit') (Join-Path $tempRepo 'tests' 'unit')
            Copy-Item -Recurse (Join-Path $RepoRoot '.github') (Join-Path $tempRepo '.github')

            # Case-specific pipeline inputs.
            Set-Content (Join-Path $tempRepo 'VERSION') $Version
            Copy-Item (Join-Path $RepoRoot 'fixtures' 'commit-logs' $CommitLog) `
                (Join-Path $tempRepo 'commit-log.txt')

            Push-Location $tempRepo
            try {
                git init --quiet --initial-branch=main 2>&1 | Out-Null
                git add -A 2>&1 | Out-Null
                git -c user.email='test@example.com' -c user.name='Test Harness' `
                    commit --quiet -m 'test: act harness case' 2>&1 | Out-Null

                # --- 2. Run the workflow through act ---
                $actOutput = & act push --rm --pull=false `
                    -P ubuntu-latest=act-ubuntu-pwsh:latest 2>&1 |
                    ForEach-Object { $_.ToString() }
                $actExit = $LASTEXITCODE
            }
            finally {
                Pop-Location
            }

            # --- 3. Append delimited output to the required artifact ---
            $delimiter = @(
                '=' * 78
                "TEST CASE: $Name"
                "  input version : $Version"
                "  commit fixture: $CommitLog"
                "  expected      : NEW_VERSION=$ExpectedVersion"
                "  act exit code : $actExit"
                '=' * 78
            )
            Add-Content -Path $ActResultFile -Value ($delimiter + $actOutput + '')

            # --- 4. Assertions on exact expected values ---
            $joined = $actOutput -join "`n"

            $actExit | Should -Be 0 -Because 'act must run the workflow successfully'

            # Exact new-version contract line printed by the bump job.
            $joined | Should -Match ([regex]::Escape("NEW_VERSION=$ExpectedVersion"))

            # The updated VERSION file printed by the artifacts step.
            $joined | Should -Match ([regex]::Escape($ExpectedVersion))

            # Changelog entry content generated from the commits.
            foreach ($check in $ChangelogChecks) {
                $joined | Should -Match ([regex]::Escape($check))
            }

            # --- 5. Every job (test + bump) must report success ---
            @($actOutput | Where-Object { $_ -match 'Job succeeded' }).Count |
                Should -BeGreaterOrEqual 2 -Because 'both the test and bump jobs must succeed'
        }
        finally {
            Remove-Item -Recurse -Force $tempRepo -ErrorAction SilentlyContinue
        }
    }

    It 'produced the act-result.txt artifact' {
        Test-Path $ActResultFile | Should -BeTrue
        (Get-Content $ActResultFile -Raw).Length | Should -BeGreaterThan 0
    }
}
