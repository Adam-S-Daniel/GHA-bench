# Act pipeline tests: every functional test case runs through the ACTUAL
# GitHub Actions workflow via `act push --rm`, in an isolated Docker
# container (nektos/act) -- not by calling the script directly.
#
# For each case: build a throwaway temp git repo containing the project
# files + that case's fixture data (a specific fixtures/mock-licenses*.json
# swapped in as fixtures/mock-licenses.json), run `act push --rm`, capture
# the full output, append it to act-result.txt, and assert on exact
# expected values from the compliance report the workflow printed.

BeforeAll {
    $script:repoRoot = Join-Path $PSScriptRoot '..'
    $script:actResultPath = Join-Path $script:repoRoot 'act-result.txt'

    function Invoke-ActTestCase {
        param(
            [string]$CaseName,
            [string]$MockFixtureFile
        )

        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "license-checker-act-$CaseName-$([guid]::NewGuid().ToString('N'))"
        New-Item -ItemType Directory -Path $tempDir | Out-Null

        try {
            foreach ($item in @('.github', 'src', 'tests', 'fixtures', 'Check-Licenses.ps1', '.actrc')) {
                Copy-Item -Path (Join-Path $script:repoRoot $item) -Destination $tempDir -Recurse -Force
            }

            # Swap in this case's fixture data as the mock license source the
            # workflow reads (fixtures/ci-mock-licenses.json -- kept distinct
            # from fixtures/mock-licenses.json so the unit test suite's own
            # fixtures aren't disturbed by the case being exercised here).
            $sourceMock = Join-Path $script:repoRoot 'fixtures' $MockFixtureFile
            $destMock = Join-Path $tempDir 'fixtures' 'ci-mock-licenses.json'
            Copy-Item -Path $sourceMock -Destination $destMock -Force

            Push-Location $tempDir
            try {
                git init -q
                git -c user.email='act-test@example.com' -c user.name='act-test' add -A
                git -c user.email='act-test@example.com' -c user.name='act-test' commit -q -m "test case: $CaseName"

                $output = & act push --rm --pull=false 2>&1 | Out-String
                $exitCode = $LASTEXITCODE
            }
            finally {
                Pop-Location
            }

            $delimiter = "===== ACT TEST CASE: $CaseName ====="
            Add-Content -Path $script:actResultPath -Value $delimiter
            Add-Content -Path $script:actResultPath -Value $output
            Add-Content -Path $script:actResultPath -Value "===== EXIT CODE: $exitCode ====="
            Add-Content -Path $script:actResultPath -Value ''

            return [pscustomobject]@{
                CaseName = $CaseName
                Output   = $output
                ExitCode = $exitCode
            }
        }
        finally {
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # Reset the result file once per full test-harness run (all cases append below).
    if (Test-Path -LiteralPath $script:actResultPath) {
        Remove-Item -LiteralPath $script:actResultPath -Force
    }
    New-Item -ItemType File -Path $script:actResultPath | Out-Null

    $script:compliantResult = Invoke-ActTestCase -CaseName 'all-approved' -MockFixtureFile 'mock-licenses.json'
    $script:deniedResult = Invoke-ActTestCase -CaseName 'has-denied-license' -MockFixtureFile 'mock-licenses-with-deny.json'
    $script:unknownResult = Invoke-ActTestCase -CaseName 'partial-unknown-licenses' -MockFixtureFile 'mock-licenses-partial.json'
}

Describe 'act-result.txt artifact' {
    It 'exists after the act pipeline runs' {
        Test-Path -LiteralPath $script:actResultPath | Should -BeTrue
    }
}

Describe 'act push: all-approved case (mock-licenses.json)' {
    It 'exits 0' {
        $script:compliantResult.ExitCode | Should -Be 0
    }

    It 'shows the job succeeded' {
        $script:compliantResult.Output | Should -Match 'Job succeeded'
    }

    It 'reports the exact known-good summary line: 4 Approved, 0 Denied, 0 Unknown' {
        $script:compliantResult.Output | Should -Match 'Summary: 4 Approved, 0 Denied, 0 Unknown'
    }

    It 'reports lodash as Approved with license MIT' {
        $script:compliantResult.Output | Should -Match 'lodash\s+4\.17\.21\s+MIT\s+Approved'
    }

    It 'reports the exact COMPLIANCE PASSED result' {
        $script:compliantResult.Output | Should -Match 'COMPLIANCE PASSED\.'
    }
}

Describe 'act push: has-denied-license case (mock-licenses-with-deny.json)' {
    It 'still exits 0 (compliance failures are surfaced, not a hard CI failure)' {
        $script:deniedResult.ExitCode | Should -Be 0
    }

    It 'shows the job succeeded' {
        $script:deniedResult.Output | Should -Match 'Job succeeded'
    }

    It 'reports the exact known-good summary line: 3 Approved, 1 Denied, 0 Unknown' {
        $script:deniedResult.Output | Should -Match 'Summary: 3 Approved, 1 Denied, 0 Unknown'
    }

    It 'reports express as Denied with license GPL-3.0' {
        $script:deniedResult.Output | Should -Match 'express\s+4\.18\.2\s+GPL-3\.0\s+Denied'
    }

    It 'reports the exact known-good failure message' {
        $script:deniedResult.Output | Should -Match 'COMPLIANCE FAILED: 1 dependencies use a denied license\.'
    }
}

Describe 'act push: partial-unknown-licenses case (mock-licenses-partial.json)' {
    It 'exits 0' {
        $script:unknownResult.ExitCode | Should -Be 0
    }

    It 'shows the job succeeded' {
        $script:unknownResult.Output | Should -Match 'Job succeeded'
    }

    It 'reports the exact known-good summary line: 2 Approved, 0 Denied, 2 Unknown' {
        $script:unknownResult.Output | Should -Match 'Summary: 2 Approved, 0 Denied, 2 Unknown'
    }

    It 'reports jest as Unknown with license UNKNOWN' {
        $script:unknownResult.Output | Should -Match 'jest\s+29\.0\.0\s+UNKNOWN\s+Unknown'
    }

    It 'reports the exact known-good COMPLIANCE PASSED result' {
        $script:unknownResult.Output | Should -Match 'COMPLIANCE PASSED\.'
    }
}
