# End-to-end integration tests that run the PR Label Assigner THROUGH the
# GitHub Actions pipeline using nektos/act.
#
# For each test case this harness:
#   1. Builds a throwaway temp git repo containing the project files plus that
#      case's fixture data (the mock list of changed files).
#   2. Runs `act push --rm` against that repo (the custom act image ships pwsh +
#      Pester pre-installed).
#   3. Appends the full act output to ./act-result.txt, clearly delimited.
#   4. Asserts act exited 0, that every job reports "Job succeeded", and that the
#      computed label set matches the EXACT expected value for that input.
#
# Run with:  Invoke-Pester -Path ./tests/Act.Tests.ps1
#
# NOTE: each case is one `act push` run. Keep the case count small.

BeforeAll {
    $script:repoRoot   = Split-Path -Parent $PSScriptRoot
    $script:resultFile = Join-Path $script:repoRoot 'act-result.txt'
    $script:image      = 'act-ubuntu-pwsh:latest'

    # Start each full run with a fresh aggregate output file.
    Set-Content -LiteralPath $script:resultFile -Value "PR Label Assigner - act integration results`n" -Encoding utf8

    # Build a temporary git repo seeded with the project + a case's changed files.
    function script:New-CaseRepo {
        param(
            [Parameter(Mandatory)][string] $ChangedFilesContent
        )
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) ('plr-act-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $dir 'tests')   -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $dir 'config')  -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $dir 'fixtures') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $dir '.github/workflows') -Force | Out-Null

        # Copy the project files the pipeline needs.
        Copy-Item (Join-Path $script:repoRoot 'PRLabelAssigner.psm1')     (Join-Path $dir 'PRLabelAssigner.psm1')
        Copy-Item (Join-Path $script:repoRoot 'Invoke-LabelAssigner.ps1') (Join-Path $dir 'Invoke-LabelAssigner.ps1')
        Copy-Item (Join-Path $script:repoRoot 'config/label-rules.json')  (Join-Path $dir 'config/label-rules.json')
        Copy-Item (Join-Path $script:repoRoot 'tests/PRLabelAssigner.Tests.ps1') (Join-Path $dir 'tests/PRLabelAssigner.Tests.ps1')
        Copy-Item (Join-Path $script:repoRoot '.github/workflows/pr-label-assigner.yml') (Join-Path $dir '.github/workflows/pr-label-assigner.yml')
        if (Test-Path (Join-Path $script:repoRoot '.actrc')) {
            Copy-Item (Join-Path $script:repoRoot '.actrc') (Join-Path $dir '.actrc')
        }

        # Inject THIS case's mock changed-file list.
        Set-Content -LiteralPath (Join-Path $dir 'fixtures/changed-files.txt') -Value $ChangedFilesContent -Encoding utf8

        # Initialise a git repo so act has commit history to operate on.
        Push-Location $dir
        try {
            git init -q 2>&1 | Out-Null
            git checkout -q -b main 2>&1 | Out-Null
            git config user.email 'ci@example.com' 2>&1 | Out-Null
            git config user.name  'CI' 2>&1 | Out-Null
            git add -A 2>&1 | Out-Null
            git commit -q -m 'fixture' 2>&1 | Out-Null
        }
        finally {
            Pop-Location
        }
        return $dir
    }

    # Run act against a case repo and return the captured output + exit code.
    function script:Invoke-Act {
        param(
            [Parameter(Mandatory)][string] $RepoDir,
            [Parameter(Mandatory)][string] $CaseName
        )
        $out = & act push `
            --rm `
            --directory $RepoDir `
            --pull=false `
            -P "ubuntu-latest=$script:image" 2>&1
        $code = $LASTEXITCODE
        $text = ($out | Out-String)

        # Append this case's output to the aggregate artifact, clearly delimited.
        $delim = ('=' * 70)
        Add-Content -LiteralPath $script:resultFile -Value $delim
        Add-Content -LiteralPath $script:resultFile -Value "TEST CASE: $CaseName  (act exit code: $code)"
        Add-Content -LiteralPath $script:resultFile -Value $delim
        Add-Content -LiteralPath $script:resultFile -Value $text

        return [pscustomobject]@{ ExitCode = $code; Text = $text }
    }

    # Pull the "LABELS: ..." line printed by the entry script out of act output.
    function script:Get-LabelsLine {
        param([Parameter(Mandatory)][string] $Text)
        $m = [regex]::Match($Text, 'LABELS:\s*(?<v>.*)')
        if ($m.Success) { return $m.Groups['v'].Value.Trim() }
        return $null
    }
}

Describe 'PR Label Assigner via act' {

    # Each entry: a mock changed-file list and the EXACT expected label output.
    # Expected values are computed by hand from config/label-rules.json and
    # asserted verbatim (not just "some output appeared").
    $cases = @(
        @{
            Name          = 'docs-and-api'
            ChangedFiles  = "docs/intro.md`nsrc/api/server.js"
            ExpectedLabels = 'api, backend, documentation, source'
            ExpectedCount = 4
        }
        @{
            Name          = 'tests-and-frontend'
            ChangedFiles  = "src/web/Button.jsx`nsrc/web/Button.test.jsx"
            ExpectedLabels = 'frontend, tests, source'
            ExpectedCount = 3
        }
        @{
            Name          = 'ci-only-with-unmatched-file'
            ChangedFiles  = ".github/workflows/ci.yml`nLICENSE"
            ExpectedLabels = 'ci'
            ExpectedCount = 1
        }
    )

    It 'case <Name>: act exits 0, every job succeeds, labels are exactly <ExpectedLabels>' -ForEach $cases {
        $repo = script:New-CaseRepo -ChangedFilesContent $ChangedFiles
        try {
            $run = script:Invoke-Act -RepoDir $repo -CaseName $Name

            # 1. act must succeed.
            $run.ExitCode | Should -Be 0 -Because "act push should succeed for case '$Name'`n$($run.Text)"

            # 2. Both jobs (test, assign-labels) must report success.
            ([regex]::Matches($run.Text, 'Job succeeded')).Count |
                Should -BeGreaterOrEqual 2 -Because "both jobs should report 'Job succeeded'`n$($run.Text)"

            # 3. The Pester unit tests inside the pipeline must have passed.
            $run.Text | Should -Match 'unit tests passed'

            # 4. EXACT expected label set and count.
            $labels = script:Get-LabelsLine -Text $run.Text
            $labels | Should -Be $ExpectedLabels -Because "computed labels must match exactly`n$($run.Text)"
            $run.Text | Should -Match "LABEL_COUNT: $ExpectedCount"
        }
        finally {
            if (Test-Path $repo) { Remove-Item $repo -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}
