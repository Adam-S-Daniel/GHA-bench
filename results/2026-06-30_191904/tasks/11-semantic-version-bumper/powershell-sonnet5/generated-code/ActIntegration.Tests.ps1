<#
    Integration tests that prove the GitHub Actions workflow actually
    works by running it inside a real Docker container via `act`
    (nektos/act) -- once per conventional-commit scenario (feat -> minor,
    fix -> patch, breaking change -> major).

    Per the task's "all tests must run through act" requirement, these are
    the tests that validate end-to-end pipeline behavior; they do not
    invoke the PowerShell scripts directly. Each test case:

      1. Builds a fresh, isolated temp git repo containing only the
         project files the workflow needs (module, orchestration script,
         unit tests, fixtures, and the workflow file itself) plus a
         VERSION file fixed at "1.1.0".
      2. Commits with that scenario's conventional-commit message.
      3. Runs `act push --rm` against the act-ubuntu-pwsh:latest image
         (the same image configured in .actrc) and captures all output.
      4. Appends the output to act-result.txt and asserts exact,
         known-good values: exit code 0, "Job succeeded", and the precise
         bumped version string -- not just that "a version" was printed.
#>

BeforeAll {
    $script:ProjectRoot = $PSScriptRoot
    $script:ResultFile = Join-Path $script:ProjectRoot 'act-result.txt'
    Set-Content -Path $script:ResultFile -Value '' -NoNewline

    $script:FilesToCopy = @(
        'VersionBumper.psm1',
        'Invoke-VersionBump.ps1',
        'VersionBumper.Tests.ps1'
    )

    function Remove-AnsiCodes {
        param([string] $Text)
        return ($Text -replace "`e\[[0-9;]*[a-zA-Z]", '')
    }

    function Invoke-ActScenario {
        <#
            Sets up an isolated temp git repo for one test case, runs the
            workflow via `act push --rm`, records the output, and returns
            the exit code + cleaned output for assertions.
        #>
        param(
            [Parameter(Mandatory)] [string] $Name,
            [Parameter(Mandatory)] [string] $CommitSubject,
            [string] $CommitBody
        )

        $repoDir = Join-Path ([System.IO.Path]::GetTempPath()) "act-scenario-$Name-$([System.Guid]::NewGuid())"
        New-Item -ItemType Directory -Path $repoDir | Out-Null

        try {
            foreach ($file in $script:FilesToCopy) {
                Copy-Item -Path (Join-Path $script:ProjectRoot $file) -Destination $repoDir
            }
            Copy-Item -Path (Join-Path $script:ProjectRoot 'fixtures') -Destination $repoDir -Recurse
            Copy-Item -Path (Join-Path $script:ProjectRoot '.github') -Destination $repoDir -Recurse
            Set-Content -Path (Join-Path $repoDir 'VERSION') -Value '1.1.0' -NoNewline

            Push-Location $repoDir
            try {
                git init --quiet --initial-branch=main 2>&1 | Out-Null
                git config user.email 'act-harness@example.com' 2>&1 | Out-Null
                git config user.name 'Act Harness' 2>&1 | Out-Null
                git add -A 2>&1 | Out-Null
                if ($CommitBody) {
                    git commit --quiet -m $CommitSubject -m $CommitBody 2>&1 | Out-Null
                }
                else {
                    git commit --quiet -m $CommitSubject 2>&1 | Out-Null
                }

                $rawOutput = act push --rm --pull=false -P ubuntu-latest=act-ubuntu-pwsh:latest 2>&1 | Out-String
                $exitCode = $LASTEXITCODE
            }
            finally {
                Pop-Location
            }

            $cleanOutput = Remove-AnsiCodes -Text $rawOutput
            $bodyNote = if ($CommitBody) { " / $CommitBody" } else { '' }
            $delimiter = '=' * 80
            $header = "$delimiter`nTEST CASE: $Name`nCommit message: $CommitSubject$bodyNote`nExit code: $exitCode`n$delimiter"
            Add-Content -Path $script:ResultFile -Value "$header`n$cleanOutput`n"

            return [pscustomobject]@{
                ExitCode = $exitCode
                Output   = $cleanOutput
            }
        }
        finally {
            Remove-Item -Path $repoDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Semantic Version Bumper workflow (executed via act)' {
    It 'bumps a minor version for a feat commit (1.1.0 -> 1.2.0)' {
        $result = Invoke-ActScenario -Name 'feat' -CommitSubject 'feat: add new login page'

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'Job succeeded'
        $result.Output | Should -Match 'Tests Passed: 30, Failed: 0'
        $result.Output | Should -Match 'Bump type: minor'
        $result.Output | Should -Match 'New version: 1\.2\.0'
        $result.Output | Should -Not -Match 'New version: 1\.1\.1'
        $result.Output | Should -Not -Match 'New version: 2\.0\.0'
    }

    It 'bumps a patch version for a fix commit (1.1.0 -> 1.1.1)' {
        $result = Invoke-ActScenario -Name 'fix' -CommitSubject 'fix: correct null pointer in parser'

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'Job succeeded'
        $result.Output | Should -Match 'Tests Passed: 30, Failed: 0'
        $result.Output | Should -Match 'Bump type: patch'
        $result.Output | Should -Match 'New version: 1\.1\.1'
        $result.Output | Should -Not -Match 'New version: 1\.2\.0'
        $result.Output | Should -Not -Match 'New version: 2\.0\.0'
    }

    It 'bumps a major version for a breaking-change commit (1.1.0 -> 2.0.0)' {
        $result = Invoke-ActScenario -Name 'breaking' -CommitSubject 'feat: redesign public API' -CommitBody 'BREAKING CHANGE: removes deprecated v1 endpoints'

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'Job succeeded'
        $result.Output | Should -Match 'Tests Passed: 30, Failed: 0'
        $result.Output | Should -Match 'Bump type: major'
        $result.Output | Should -Match 'New version: 2\.0\.0'
        $result.Output | Should -Not -Match 'New version: 1\.2\.0'
        $result.Output | Should -Not -Match 'New version: 1\.1\.1'
    }
}

AfterAll {
    if (Test-Path -LiteralPath $script:ResultFile -PathType Leaf) {
        Write-Host "act output written to: $script:ResultFile"
    }
}
