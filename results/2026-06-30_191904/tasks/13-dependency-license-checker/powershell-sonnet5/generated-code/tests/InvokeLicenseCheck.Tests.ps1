#Requires -Modules Pester

<#
    TDD tests for the CLI entry point (Invoke-LicenseCheck.ps1) that CI runs.
    Written RED-first, before the script existed.
#>

BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '..' 'Invoke-LicenseCheck.ps1'
    $script:PolicyPath = Join-Path $PSScriptRoot '..' 'fixtures' 'policy-fixture.json'
    $script:DbPath = Join-Path $PSScriptRoot '..' 'fixtures' 'license-database-fixture.json'

    @{
        AllowList = @('MIT', 'Apache-2.0')
        DenyList  = @('GPL-3.0')
    } | ConvertTo-Json | Set-Content -Path $script:PolicyPath

    @{
        lodash      = 'MIT'
        'gpl-package' = 'GPL-3.0'
    } | ConvertTo-Json | Set-Content -Path $script:DbPath
}

AfterAll {
    Remove-Item -Path $script:PolicyPath -ErrorAction SilentlyContinue
    Remove-Item -Path $script:DbPath -ErrorAction SilentlyContinue
}

Describe 'Invoke-LicenseCheck.ps1' {

    It 'prints a Summary line with exact Approved/Denied/Unknown counts and exits 0' {
        $manifest = Join-Path $PSScriptRoot '..' 'fixtures' 'package-denied.json'

        $output = & $script:ScriptPath -ManifestPath $manifest -PolicyPath $script:PolicyPath -LicenseDatabasePath $script:DbPath 2>&1 | Out-String
        $exitCode = $LASTEXITCODE

        $exitCode | Should -Be 0
        $output | Should -Match 'Summary: Approved=1, Denied=1, Unknown=0'
    }

    It 'exits non-zero with a meaningful message when the manifest is missing' {
        & $script:ScriptPath -ManifestPath './no-such-manifest.json' -PolicyPath $script:PolicyPath -LicenseDatabasePath $script:DbPath 2>&1 |
            Out-String -OutVariable output | Out-Null
        $exitCode = $LASTEXITCODE

        $exitCode | Should -Be 1
        $output | Should -Match 'not found'
    }
}
