#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# End-to-end integration test: for each fixture case below, this spins up a
# throwaway git repo containing a copy of the project plus that case's
# secrets-config.json, runs the real GitHub Actions workflow through `act
# push --rm`, and asserts on the EXACT values the workflow produced (not
# just that some output appeared). All act output is appended to
# act-result.txt at the repo root, clearly delimited per case.
#
# This is deliberately NOT unit testing the PowerShell module directly -
# the module already has its own Pester coverage in
# SecretRotationValidator.Tests.ps1. This file's job is to prove the
# workflow itself (checkout -> Pester job -> report job -> artifacts) works
# end to end inside a real `act` run.
#
# NOTES ON PESTER v5 DISCOVERY VS RUN:
# - It's -TestCases is evaluated during *discovery*, so $IntegrationTestCases
#   must be a plain top-level variable built before the Describe block.
# - BeforeAll/It bodies execute during the later *run* phase, which does NOT
#   see plain top-level discovery-time variables - only $script: scoped ones
#   survive that boundary. So anything BeforeAll/It needs (paths, helper
#   functions) is defined with $script: scope / inside BeforeAll itself.

$Now = Get-Date

# Fixture dates are computed relative to "now" (with generous margins away
# from the 14-day warning boundary) so the expected classification is
# deterministic no matter what day this suite runs on.
function Format-FixtureDate([int]$DaysAgo) {
    $Now.AddDays(-$DaysAgo).ToString('yyyy-MM-dd')
}

$IntegrationTestCases = @(
    @{
        CaseName = 'mixed-urgency'
        Secrets  = @(
            # due 10 days ago -> Expired
            [ordered]@{ Name = 'db-password'; LastRotated = (Format-FixtureDate 40); RotationPolicyDays = 30; RequiredBy = @('billing-service') }
            # due in ~5 days -> Warning (inside the 14-day default window)
            [ordered]@{ Name = 'api-key'; LastRotated = (Format-FixtureDate 85); RotationPolicyDays = 90; RequiredBy = @('checkout-service') }
            # due in ~365 days -> Ok
            [ordered]@{ Name = 'tls-cert'; LastRotated = (Format-FixtureDate 0); RotationPolicyDays = 365; RequiredBy = @('edge-proxy') }
        )
        Expected = @{
            Total        = 3
            ExpiredCount = 1
            WarningCount = 1
            OkCount      = 1
            ExpiredNames = @('db-password')
            WarningNames = @('api-key')
            OkNames      = @('tls-cert')
        }
    }
    @{
        CaseName = 'all-healthy'
        Secrets  = @(
            # due in ~180 days -> Ok
            [ordered]@{ Name = 'ssh-key'; LastRotated = (Format-FixtureDate 0); RotationPolicyDays = 180; RequiredBy = @('deploy-bot') }
        )
        Expected = @{
            Total        = 1
            ExpiredCount = 0
            WarningCount = 0
            OkCount      = 1
            ExpiredNames = @()
            WarningNames = @()
            OkNames      = @('ssh-key')
        }
    }
)

Describe 'Secret rotation validator workflow (via act)' {

    BeforeAll {
        # Recomputed here (not read from the discovery-time top-level
        # variable) because Pester v5 does not carry plain top-level
        # variables across the discovery -> run boundary, even when
        # assigned with $script: scope at the top of the file. $PSScriptRoot
        # itself, however, is reliably provided by Pester in every phase.
        $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
        $script:ActResultPath = Join-Path $script:RepoRoot 'act-result.txt'

        function New-FixtureRepo {
            param(
                [Parameter(Mandatory)][string]$DestinationDir,
                [Parameter(Mandatory)][object[]]$Secrets
            )

            New-Item -ItemType Directory -Path $DestinationDir -Force | Out-Null

            Get-ChildItem -Path $script:RepoRoot -Force |
                Where-Object { $_.Name -notin @('.git', 'act-result.txt') } |
                ForEach-Object { Copy-Item -Path $_.FullName -Destination $DestinationDir -Recurse -Force }

            $Secrets | ConvertTo-Json | Set-Content -Path (Join-Path $DestinationDir 'secrets-config.json')

            Push-Location $DestinationDir
            try {
                git init -q -b main
                git config user.email 'workflow-integration-test@example.com'
                git config user.name 'Workflow Integration Test'
                git add -A
                git commit -q -m 'fixture commit' --no-verify
            }
            finally {
                Pop-Location
            }
        }

        function Invoke-ActPush {
            param([Parameter(Mandatory)][string]$WorkingDirectory)

            Push-Location $WorkingDirectory
            try {
                $output = & act push --rm 2>&1 | Out-String
                $exitCode = $LASTEXITCODE
            }
            finally {
                Pop-Location
            }

            [PSCustomObject]@{
                Output   = $output
                ExitCode = $exitCode
            }
        }

        function Get-EmbeddedJsonReport {
            param([Parameter(Mandatory)][string]$ActOutput)

            # Each act log line is prefixed with "[Workflow/Job]  ". Strip
            # that prefix, then pull out everything between the delimiter
            # markers emitted by the "Emit machine-readable summary" step.
            $strippedLines = $ActOutput -split "`n" | ForEach-Object {
                $_ -replace '^\[[^\]]+\]\s*', ''
            }

            $startIndex = ($strippedLines | Select-String -Pattern '<<<ROTATION_REPORT_JSON>>>' -SimpleMatch | Select-Object -First 1).LineNumber
            $endIndex = ($strippedLines | Select-String -Pattern '<<<END_ROTATION_REPORT_JSON>>>' -SimpleMatch | Select-Object -First 1).LineNumber

            if (-not $startIndex -or -not $endIndex -or $endIndex -le $startIndex) {
                throw "Could not locate <<<ROTATION_REPORT_JSON>>> markers in act output"
            }

            # Select-String line numbers are 1-based; the JSON body is
            # strictly between the two marker lines.
            $jsonLines = $strippedLines[$startIndex..($endIndex - 2)]
            return ($jsonLines -join "`n") | ConvertFrom-Json
        }

        if (Test-Path $script:ActResultPath) {
            Remove-Item $script:ActResultPath -Force
        }
        New-Item -ItemType File -Path $script:ActResultPath | Out-Null
    }

    It 'runs the "<CaseName>" fixture through the real workflow with exact expected results' -TestCases $IntegrationTestCases {
        param($CaseName, $Secrets, $Expected)

        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "secret-rotation-act-$CaseName-$([guid]::NewGuid().ToString('N').Substring(0,8))"
        New-FixtureRepo -DestinationDir $tempDir -Secrets $Secrets

        try {
            $result = Invoke-ActPush -WorkingDirectory $tempDir

            Add-Content -Path $script:ActResultPath -Value "===== TEST CASE: $CaseName ====="
            Add-Content -Path $script:ActResultPath -Value "Exit code: $($result.ExitCode)"
            Add-Content -Path $script:ActResultPath -Value $result.Output
            Add-Content -Path $script:ActResultPath -Value "===== END TEST CASE: $CaseName ====="
            Add-Content -Path $script:ActResultPath -Value ''

            # 1. act must exit 0.
            $result.ExitCode | Should -Be 0 -Because "act push should succeed for fixture '$CaseName'"

            # 2. Both jobs must report success.
            $result.Output | Should -Match 'Run Pester unit tests\]\s+🏁\s+Job succeeded'
            $result.Output | Should -Match 'Generate rotation report\]\s+🏁\s+Job succeeded'

            # 3. Parse the JSON the workflow itself produced and assert
            #    exact expected values - not just that output appeared.
            $parsed = Get-EmbeddedJsonReport -ActOutput $result.Output

            $parsed.Summary.Total | Should -Be $Expected.Total
            $parsed.Summary.ExpiredCount | Should -Be $Expected.ExpiredCount
            $parsed.Summary.WarningCount | Should -Be $Expected.WarningCount
            $parsed.Summary.OkCount | Should -Be $Expected.OkCount

            @($parsed.Expired | ForEach-Object Name) | Should -Be $Expected.ExpiredNames
            @($parsed.Warning | ForEach-Object Name) | Should -Be $Expected.WarningNames
            @($parsed.Ok | ForEach-Object Name) | Should -Be $Expected.OkNames
        }
        finally {
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
