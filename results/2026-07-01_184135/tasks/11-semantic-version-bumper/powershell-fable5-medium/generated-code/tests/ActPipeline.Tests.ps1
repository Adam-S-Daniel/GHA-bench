# End-to-end pipeline tests: every test case is executed THROUGH the GitHub
# Actions workflow via `act` (nektos/act), never by calling the script
# directly. For each case a temp git repo is built from the project files
# plus that case's fixture inputs, `act push --rm` runs the workflow, and we
# assert on the exact expected version in the captured output.
#
# All act output is appended (clearly delimited) to act-result.txt in the
# project root.
#
# Set VB_SKIP_ACT=1 to skip these (each case costs a ~1 min Docker run).

BeforeDiscovery {
    # One entry per pipeline test case: fixture commit log + start version
    # + the exact expected result.
    $script:ActCases = @(
        @{ Name = 'feat-minor';     Fixture = 'commits-feat.txt';     StartVersion = '1.1.0'; ExpectedVersion = '1.2.0'; ExpectedBump = 'minor' }
        @{ Name = 'fix-patch';      Fixture = 'commits-fix.txt';      StartVersion = '2.3.4'; ExpectedVersion = '2.3.5'; ExpectedBump = 'patch' }
        @{ Name = 'breaking-major'; Fixture = 'commits-breaking.txt'; StartVersion = '1.2.3'; ExpectedVersion = '2.0.0'; ExpectedBump = 'major' }
    )
    $script:SkipAct = $env:VB_SKIP_ACT -eq '1'
}

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:ResultFile = Join-Path $RepoRoot 'act-result.txt'
    # Fresh result log per test run.
    Set-Content -Path $ResultFile -Value "act pipeline test results - $(Get-Date -Format o)`n"

    function script:Invoke-ActCase {
        param([hashtable]$Case)

        $work = Join-Path ([IO.Path]::GetTempPath()) ("act-" + $Case.Name + "-" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $work | Out-Null
        try {
            # Project files the workflow needs inside the container.
            foreach ($item in @('src', 'tests', 'fixtures', 'Invoke-VersionBump.ps1', '.github', '.actrc')) {
                Copy-Item -Recurse -Path (Join-Path $RepoRoot $item) -Destination (Join-Path $work $item)
            }
            # Case-specific inputs consumed by the workflow's bump job.
            Set-Content -Path (Join-Path $work 'version.txt') -Value $Case.StartVersion
            Copy-Item (Join-Path $RepoRoot 'fixtures' $Case.Fixture) (Join-Path $work 'commits.txt')

            # act requires a git repo to derive the push event from.
            & git -C $work init -q -b main
            & git -C $work -c user.email=test@example.com -c user.name=test add -A
            & git -C $work -c user.email=test@example.com -c user.name=test commit -q -m 'test fixture'

            Push-Location $work
            try {
                # --pull=false: the runner image is a local build.
                $output = & act push --rm --pull=false 2>&1 | Out-String
                $exit = $LASTEXITCODE
            }
            finally {
                Pop-Location
            }

            # Append delimited output to the required artifact.
            Add-Content -Path $ResultFile -Value @"
============================================================
CASE: $($Case.Name)  (start=$($Case.StartVersion), fixture=$($Case.Fixture), expect=$($Case.ExpectedVersion))
act exit code: $exit
============================================================
$output
"@
            return [pscustomobject]@{ ExitCode = $exit; Output = $output }
        }
        finally {
            Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
        }
    }
}

Describe 'GitHub Actions pipeline via act' -Skip:$SkipAct {

    It 'bumps <StartVersion> to exactly <ExpectedVersion> for case <Name>' -ForEach $ActCases {
        $result = Invoke-ActCase -Case $_

        # 1. act itself must succeed.
        $result.ExitCode | Should -Be 0 -Because 'act must exit 0'

        # 2. Every job must report success (test job + bump job).
        $succeeded = ([regex]::Matches($result.Output, 'Job succeeded')).Count
        $succeeded | Should -BeGreaterOrEqual 2 -Because 'both the test and bump jobs must succeed'

        # 3. Exact expected values, not just "some version".
        $result.Output | Should -Match ([regex]::Escape("OLD_VERSION=$($_.StartVersion)"))
        $result.Output | Should -Match ([regex]::Escape("NEW_VERSION=$($_.ExpectedVersion)"))
        $result.Output | Should -Match ([regex]::Escape("BUMP_TYPE=$($_.ExpectedBump)"))

        # 4. The step-output plumbing must carry the same exact version.
        $result.Output | Should -Match ([regex]::Escape("New version from step output: $($_.ExpectedVersion)"))

        # 5. The changelog produced inside the container mentions the new version.
        $result.Output | Should -Match ([regex]::Escape("## [$($_.ExpectedVersion)]"))

        # 6. The in-container Pester suite ran and passed (test job).
        $result.Output | Should -Match 'Tests Passed: 28'
    }

    It 'wrote all act output to act-result.txt' {
        $ResultFile | Should -Exist
        $content = Get-Content $ResultFile -Raw
        foreach ($case in $ActCases) {
            $content | Should -Match ([regex]::Escape("CASE: $($case.Name)"))
        }
    }
}
