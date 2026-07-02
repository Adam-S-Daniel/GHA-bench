#Requires -Modules Pester
<#
    Asserts on the captured act-result.txt output from running the workflow
    locally with `act push --rm --pull=false` against the default fixture
    (fixtures/ci-config.json). Verifies exact expected matrix values, not
    just that some output appeared.
#>

BeforeAll {
    $script:ResultPath = Join-Path $PSScriptRoot '../act-result.txt'
    $script:ResultText = Get-Content -LiteralPath $script:ResultPath -Raw
}

Describe 'act-result.txt captured run' {

    It 'exists as a required artifact' {
        Test-Path -LiteralPath $script:ResultPath | Should -Be $true
    }

    It 'recorded an overall exit code of 0' {
        $script:ResultText | Should -Match 'EXIT CODE: 0'
    }

    It 'shows the Pester unit test job succeeded with all tests passing' {
        $script:ResultText | Should -Match 'Tests Passed: \d+, .*Failed: 0,'
        $script:ResultText | Should -Match 'Run Pester unit tests\]\s*🏁\s*Job succeeded'
    }

    It 'shows the generate-matrix job succeeded and emitted the exact expected matrix JSON' {
        $script:ResultText | Should -Match 'Generate build matrix\]\s*🏁\s*Job succeeded'
        $expectedMatrixJson = 'matrix={"include":[{"experimental":true,"language_version":"3.10","os":"ubuntu-latest"},{"language_version":"3.11","os":"ubuntu-latest"}]}'
        $script:ResultText.Contains($expectedMatrixJson) | Should -BeTrue
    }

    It 'shows the exact expected max-parallel and fail-fast output values' {
        $script:ResultText | Should -Match 'max-parallel=2'
        $script:ResultText | Should -Match 'fail-fast=false'
    }

    It 'shows both build matrix jobs ran with the exact expected per-combination values and succeeded' {
        $script:ResultText.Contains('Running on os=ubuntu-latest language_version=3.10 experimental=true') | Should -BeTrue
        $script:ResultText.Contains('Running on os=ubuntu-latest language_version=3.11 experimental=') | Should -BeTrue
        $script:ResultText | Should -Match 'Build \(ubuntu-latest, 3\.10\)-1\]\s*🏁\s*Job succeeded'
        $script:ResultText | Should -Match 'Build \(ubuntu-latest, 3\.11\)-2\]\s*🏁\s*Job succeeded'
    }

    It 'does not contain any act-level error messages' {
        $script:ResultText | Should -Not -Match 'level=error'
    }
}
