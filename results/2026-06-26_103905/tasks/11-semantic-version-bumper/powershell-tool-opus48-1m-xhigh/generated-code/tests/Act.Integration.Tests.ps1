# Act.Integration.Tests.ps1
#
# End-to-end integration tests that exercise the ENTIRE GitHub Actions pipeline
# through nektos/act. Every test case here:
#   1. builds a throwaway git repo containing the project files + that case's
#      fixture data (a version file + a commit log),
#   2. runs `act push --rm` against the real workflow,
#   3. appends the full act output to ../act-result.txt (clearly delimited),
#   4. asserts act exited 0, that the EXACT expected version/bump was produced,
#      and that every job reported "Job succeeded".
#
# These are real Pester tests, so they run with Invoke-Pester like everything
# else — but all assertions are made against output that came out of act, not
# from calling the script directly.
#
# NOTE: each `It` performs one `act push` run (slow). There are 3 cases by
# design (minor / patch / major), one per bump precedence level.

BeforeDiscovery {
    # Cases are needed at discovery time for -ForEach. Each case carries its
    # fixture data and the known-good result the pipeline must produce.
    $script:Cases = @(
        @{
            Name            = 'minor-from-feat'
            VersionFileName = 'version.txt'
            VersionContent  = '1.1.0'
            Commits         = @('feat(search): add fuzzy search', 'chore: bump tooling')
            ExpectedPrev    = '1.1.0'
            ExpectedNew     = '1.2.0'
            ExpectedType    = 'minor'
        },
        @{
            Name            = 'patch-from-fix'
            VersionFileName = 'version.txt'
            VersionContent  = '1.4.7'
            Commits         = @('fix(rounding): correct half-up rounding', 'docs: add example')
            ExpectedPrev    = '1.4.7'
            ExpectedNew     = '1.4.8'
            ExpectedType    = 'patch'
        },
        @{
            Name            = 'major-from-breaking-packagejson'
            VersionFileName = 'package.json'
            VersionContent  = '{ "name": "demo", "version": "2.3.4", "private": true }'
            Commits         = @('feat!: remove the deprecated v1 API', 'fix: tidy logging')
            ExpectedPrev    = '2.3.4'
            ExpectedNew     = '3.0.0'
            ExpectedType    = 'major'
        }
    )
}

BeforeAll {
    $script:Root          = Split-Path -Parent $PSScriptRoot
    $script:ActResultFile = Join-Path $script:Root 'act-result.txt'

    # Truncate the artifact and write a header. Each case appends below.
    $stamp = (Get-Date).ToString('s')
    Set-Content -LiteralPath $script:ActResultFile -Value @(
        '================================================================'
        " act integration run — semantic version bumper"
        " generated: $stamp"
        '================================================================'
        ''
    )

    # Build a throwaway repo containing everything the workflow needs in an
    # isolated container, then overlay the case-specific fixture files.
    function script:New-ActWorkspace {
        param(
            [Parameter(Mandatory)] [hashtable] $Case
        )
        $work = Join-Path ([IO.Path]::GetTempPath()) ('act-svb-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $work | Out-Null

        # Project files required inside the container.
        Copy-Item -Recurse -Path (Join-Path $script:Root 'src') -Destination (Join-Path $work 'src')
        Copy-Item -Path (Join-Path $script:Root 'bump-version.ps1') -Destination $work
        Copy-Item -Path (Join-Path $script:Root '.actrc') -Destination $work
        New-Item -ItemType Directory -Path (Join-Path $work '.github/workflows') -Force | Out-Null
        Copy-Item -Path (Join-Path $script:Root '.github/workflows/semantic-version-bumper.yml') `
                  -Destination (Join-Path $work '.github/workflows/')
        # Only the unit-test file is needed by the pipeline's test job.
        New-Item -ItemType Directory -Path (Join-Path $work 'tests') -Force | Out-Null
        Copy-Item -Path (Join-Path $script:Root 'tests/SemanticVersionBumper.Tests.ps1') `
                  -Destination (Join-Path $work 'tests/')
        # Seed an empty changelog for the bumper to prepend to.
        Set-Content -LiteralPath (Join-Path $work 'CHANGELOG.md') -Value "# Changelog`n"

        # Case-specific fixture data.
        Set-Content -LiteralPath (Join-Path $work $Case.VersionFileName) -Value $Case.VersionContent
        Set-Content -LiteralPath (Join-Path $work 'commits.txt')         -Value $Case.Commits

        return $work
    }

    # Initialise a git repo (act needs a HEAD commit) and run the workflow.
    function script:Invoke-ActPush {
        param([Parameter(Mandatory)] [string] $WorkDir)

        Push-Location $WorkDir
        try {
            git init --quiet --initial-branch=main 2>&1 | Out-Null
            git config user.email 'ci@example.com' 2>&1 | Out-Null
            git config user.name  'CI' 2>&1            | Out-Null
            git add -A 2>&1 | Out-Null
            git -c commit.gpgsign=false commit --quiet -m 'test fixture' 2>&1 | Out-Null

            # Run the push-triggered workflow.
            #   --rm    : remove the job container when done
            #   --pull=false : the custom image is already local; don't try to
            #                  re-pull it from a registry (which needs auth)
            $output = & act push --rm --pull=false 2>&1 | Out-String
            $code   = $LASTEXITCODE
        }
        finally {
            Pop-Location
        }

        return [pscustomobject]@{ ExitCode = $code; Output = $output }
    }

    function script:Save-ActResult {
        param([string] $Name, [pscustomobject] $Result)
        Add-Content -LiteralPath $script:ActResultFile -Value @(
            ''
            '----------------------------------------------------------------'
            "TEST CASE: $Name"
            "act exit code: $($Result.ExitCode)"
            '----------------------------------------------------------------'
            $Result.Output.TrimEnd()
            ''
        )
    }
}

Describe 'Pipeline (act push)' {
    It 'produces <ExpectedNew> (<ExpectedType>) for case <Name>' -ForEach $script:Cases {
        $work   = script:New-ActWorkspace -Case $_
        $result = script:Invoke-ActPush -WorkDir $work

        # Always persist the raw output BEFORE asserting, so a failure is
        # fully diagnosable from act-result.txt.
        script:Save-ActResult -Name $Name -Result $result

        try {
            # (a) the pipeline must succeed
            $result.ExitCode | Should -Be 0 -Because "act should exit 0 for case '$Name'`n$($result.Output)"

            # (b) every job must report success (test job + bump job = 2)
            $succeeded = ([regex]::Matches($result.Output, 'Job succeeded')).Count
            $succeeded | Should -BeGreaterOrEqual 2 -Because "both jobs should report 'Job succeeded'`n$($result.Output)"
            $result.Output | Should -Not -Match 'Job failed'

            # (c) EXACT expected values, parsed from the pipeline's own output
            $result.Output | Should -Match ("PREVIOUS_VERSION=" + [regex]::Escape($ExpectedPrev))
            $result.Output | Should -Match ("BUMP_TYPE=" + [regex]::Escape($ExpectedType))
            $result.Output | Should -Match ("NEW_VERSION=" + [regex]::Escape($ExpectedNew) + '\b')

            # Guard against an accidental match of a different version string.
            $result.Output | Should -Not -Match 'NEW_VERSION=0\.0\.0'
        }
        finally {
            Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
