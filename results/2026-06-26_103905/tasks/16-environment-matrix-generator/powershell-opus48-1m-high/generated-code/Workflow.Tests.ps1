#requires -Modules Pester

<#
    Integration test harness.

    Every test case is exercised end-to-end THROUGH the GitHub Actions workflow
    via nektos/act -- the script is never invoked directly here. Because the
    workflow verifies every fixture in `fixtures/` within a single run, one
    `act push` covers all cases (basic / exclude / include / oversize) plus the
    dynamic build-matrix fan-out. This respects the "at most 3 act runs" budget.

    The harness:
      1. Builds a throwaway git repo containing the project + all fixtures.
      2. Runs `act push --rm`, capturing combined output.
      3. Appends that output to ./act-result.txt (delimited).
      4. Asserts act exited 0.
      5. Parses the output and asserts EXACT expected values per fixture.
      6. Asserts every job shows "Job succeeded" and none failed.
#>

BeforeAll {
    $script:ProjectDir  = $PSScriptRoot
    $script:ResultFile  = Join-Path $script:ProjectDir 'act-result.txt'

    # Files the workflow needs inside the isolated container/repo.
    $script:ProjectFiles = @(
        'BuildMatrix.psm1',
        'New-BuildMatrix.ps1',
        'BuildMatrix.Tests.ps1',
        '.actrc'
    )

    function Invoke-ActPush {
        <#
            Sets up a temp git repo with the project files + fixtures, runs
            `act push --rm`, returns @{ Output = <string>; ExitCode = <int> }.
        #>
        param([string] $Label)

        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("act-emg-" + [System.Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        try {
            # Copy project files, the workflow, and fixtures into the temp repo.
            foreach ($f in $script:ProjectFiles) {
                Copy-Item -Path (Join-Path $script:ProjectDir $f) -Destination (Join-Path $tmp $f) -Force
            }
            New-Item -ItemType Directory -Path (Join-Path $tmp '.github/workflows') -Force | Out-Null
            Copy-Item -Path (Join-Path $script:ProjectDir '.github/workflows/environment-matrix-generator.yml') `
                      -Destination (Join-Path $tmp '.github/workflows/environment-matrix-generator.yml') -Force
            Copy-Item -Path (Join-Path $script:ProjectDir 'fixtures') -Destination (Join-Path $tmp 'fixtures') -Recurse -Force

            # A git repo is required for actions/checkout to operate under act.
            Push-Location $tmp
            try {
                git init -q 2>&1 | Out-Null
                git config user.email 'ci@example.com' 2>&1 | Out-Null
                git config user.name 'CI' 2>&1 | Out-Null
                git add -A 2>&1 | Out-Null
                git commit -q -m 'fixture' 2>&1 | Out-Null

                # --rm cleans up containers; --pull=false uses the local
                # act-ubuntu-pwsh image (avoids a registry pull); stderr->stdout.
                $output = & act push --rm --pull=false 2>&1 | Out-String
                $code = $LASTEXITCODE
            }
            finally {
                Pop-Location
            }

            # Persist output to the required artifact, clearly delimited.
            $banner = "===== ACT RUN: $Label =====`n"
            Add-Content -Path $script:ResultFile -Value ($banner + $output + "`n===== END: $Label (exit=$code) =====`n") -Encoding utf8

            return @{ Output = $output; ExitCode = $code }
        }
        finally {
            Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # Start each test session with a fresh artifact file.
    Set-Content -Path $script:ResultFile -Value "act-result.txt - environment-matrix-generator integration run`n" -Encoding utf8

    # Single act run covers all fixture cases + the build fan-out.
    $script:Run = Invoke-ActPush -Label 'push-all-fixtures'
    $script:Out = $script:Run.Output

    # Helper: extract the block of lines between a fixture's markers.
    function Get-FixtureBlock {
        param([string] $Name)
        $lines = $script:Out -split "`r?`n"
        $start = $null; $end = $null
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($null -eq $start -and $lines[$i] -match "::FIXTURE:: $Name(\s|$)") { $start = $i }
            elseif ($null -ne $start -and $lines[$i] -match "::END:: $Name(\s|$)") { $end = $i; break }
        }
        if ($null -eq $start -or $null -eq $end) { return @() }
        return $lines[$start..$end]
    }
}

Describe 'Workflow execution via act' {
    It 'exits with code 0' {
        $script:Run.ExitCode | Should -Be 0
    }

    It 'wrote the act-result.txt artifact' {
        Test-Path $script:ResultFile | Should -BeTrue
        (Get-Content $script:ResultFile -Raw).Length | Should -BeGreaterThan 0
    }

    It 'every job succeeded and none failed' {
        # 6 jobs total: test + generate-matrix + 4 build (matrix) jobs.
        $succeeded = ([regex]::Matches($script:Out, 'Job succeeded')).Count
        $succeeded | Should -Be 6
        $script:Out | Should -Not -Match 'Job failed'
    }
}

Describe 'Fixture: basic' {
    BeforeAll { $script:Block = (Get-FixtureBlock 'basic') -join "`n" }

    It 'reports exactly 4 jobs' {
        $script:Block | Should -Match 'JOB_COUNT=4'
    }
    It 'carries fail-fast=false and max-parallel=2 from the config' {
        $script:Block | Should -Match 'FAIL_FAST=False'
        $script:Block | Should -Match 'MAX_PARALLEL=2'
    }
    It 'lists the four expected os/node combinations' {
        $script:Block | Should -Match 'os=ubuntu-latest; node=18'
        $script:Block | Should -Match 'os=ubuntu-latest; node=20'
        $script:Block | Should -Match 'os=windows-latest; node=18'
        $script:Block | Should -Match 'os=windows-latest; node=20'
    }
}

Describe 'Fixture: exclude' {
    BeforeAll { $script:Block = (Get-FixtureBlock 'exclude') -join "`n" }

    It 'reports exactly 4 jobs after exclusions' {
        $script:Block | Should -Match 'JOB_COUNT=4'
    }
    It 'keeps the surviving combinations' {
        $script:Block | Should -Match 'os=ubuntu-latest; python=3.10'
        $script:Block | Should -Match 'os=ubuntu-latest; python=3.11'
        $script:Block | Should -Match 'os=windows-latest; python=3.10'
        $script:Block | Should -Match 'os=macos-latest; python=3.11'
    }
    It 'dropped the two excluded combinations' {
        $script:Block | Should -Not -Match 'os=macos-latest; python=3.10'
        $script:Block | Should -Not -Match 'os=windows-latest; python=3.11'
    }
}

Describe 'Fixture: include' {
    BeforeAll { $script:Block = (Get-FixtureBlock 'include') -join "`n" }

    It 'reports exactly 6 jobs (GitHub canonical expansion)' {
        $script:Block | Should -Match 'JOB_COUNT=6'
    }
    It 'merges includes into matching combinations' {
        $script:Block | Should -Match 'fruit=apple; animal=cat; color=pink; shape=circle'
        $script:Block | Should -Match 'fruit=apple; animal=dog; color=green; shape=circle'
        $script:Block | Should -Match 'fruit=pear; animal=cat; color=pink'
    }
    It 'appends the two standalone banana combinations' {
        $script:Block | Should -Match 'fruit=banana; animal=cat'
        $script:Block | Should -Match 'JOB= fruit=banana(\r?\n|$)'
    }
}

Describe 'Fixture: oversize' {
    BeforeAll { $script:Block = (Get-FixtureBlock 'oversize') -join "`n" }

    It 'is rejected by the size validation with a meaningful message' {
        $script:Block | Should -Match 'VALIDATION_REJECTED='
        $script:Block | Should -Match 'exceeds the maximum allowed size of 4'
    }
    It 'does not emit a job list for the rejected fixture' {
        $script:Block | Should -Not -Match 'JOB_COUNT='
    }
}

Describe 'Dynamic build matrix fan-out' {
    It 'ran a build job for each of the 4 basic combinations' {
        $script:Out | Should -Match 'BUILD_JOB= os=ubuntu-latest; node=18'
        $script:Out | Should -Match 'BUILD_JOB= os=ubuntu-latest; node=20'
        $script:Out | Should -Match 'BUILD_JOB= os=windows-latest; node=18'
        $script:Out | Should -Match 'BUILD_JOB= os=windows-latest; node=20'
    }
    It 'propagated the job-count output to the build jobs' {
        $script:Out | Should -Match 'Total jobs in matrix: 4'
    }
}
