# Red/Green TDD - Step 4: the CLI entry point script (Check-Licenses.ps1)
# that wires manifest + policy + mock lookup together and prints a report.

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..' 'Check-Licenses.ps1'
    $modulePath = Join-Path $PSScriptRoot '..' 'src' 'LicenseChecker.psm1'
    Import-Module $modulePath -Force
}

Describe 'Check-Licenses.ps1' {
    BeforeAll {
        $manifestPath = Join-Path $PSScriptRoot '..' 'fixtures' 'package.json'
        $policyPath = Join-Path $PSScriptRoot '..' 'fixtures' 'license-policy.json'
        $mockDataPath = Join-Path $PSScriptRoot '..' 'fixtures' 'mock-licenses.json'
    }

    It 'exits 0 and reports zero denied packages when nothing is on the deny-list' {
        & $scriptPath -ManifestPath $manifestPath -PolicyPath $policyPath -MockDataPath $mockDataPath | Out-Null
        $LASTEXITCODE | Should -Be 0
    }

    It 'prints an Approved status line for lodash' {
        $output = & $scriptPath -ManifestPath $manifestPath -PolicyPath $policyPath -MockDataPath $mockDataPath
        ($output -join "`n") | Should -Match 'lodash.*Approved'
    }

    It 'exits 1 when a denied license is present' {
        $denyMockPath = Join-Path $PSScriptRoot '..' 'fixtures' 'mock-licenses-with-deny.json'
        & $scriptPath -ManifestPath $manifestPath -PolicyPath $policyPath -MockDataPath $denyMockPath | Out-Null
        $LASTEXITCODE | Should -Be 1
    }

    It 'throws a terminating, meaningful error for a missing manifest file' {
        { & $scriptPath -ManifestPath 'missing.json' -PolicyPath $policyPath -MockDataPath $mockDataPath -ErrorAction Stop } | Should -Throw '*not found*'
    }
}
