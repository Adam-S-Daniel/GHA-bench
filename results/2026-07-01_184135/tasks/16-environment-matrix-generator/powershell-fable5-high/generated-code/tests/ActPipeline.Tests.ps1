<#
.SYNOPSIS
    End-to-end pipeline tests: every test case runs THROUGH the GitHub
    Actions workflow via `act push` (nektos/act) in an isolated temp repo.

.DESCRIPTION
    For each test case this harness:
      1. Creates a temp directory, copies the project files into it, and
         swaps fixtures/ci-config.json for the case's fixture config.
      2. Initializes a git repo and commits everything.
      3. Runs `act push --rm --pull=false` and captures all output.
      4. Appends the output (clearly delimited) to act-result.txt in the
         project root - a required artifact.
      5. Asserts: act exit code 0, the EXACT expected strategy JSON between
         the MATRIX-JSON-BEGIN/END markers, the exact expected COMBO line for
         every matrix leg, the exact number of 'Job succeeded' lines
         (test + generate-matrix + one consume-matrix leg per combination),
         and zero 'Job failed' lines.

    Docker + act are required; each case takes ~1-2 minutes.
#>

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:ActResultPath = Join-Path $RepoRoot 'act-result.txt'
    # Fresh artifact per suite run.
    if (Test-Path $ActResultPath) { Remove-Item $ActResultPath -Force }

    function Invoke-ActCase {
        <#
            Runs one test case through the workflow via act and returns the
            captured output + exit code. Appends everything to act-result.txt.
        #>
        param(
            [Parameter(Mandatory)][string]$CaseName,
            [Parameter(Mandatory)][string]$ConfigFixture
        )

        $temp = Join-Path ([IO.Path]::GetTempPath()) "matrix-gen-act-$CaseName-$([guid]::NewGuid().ToString('N'))"
        New-Item -ItemType Directory -Path $temp | Out-Null
        try {
            # Project files the workflow needs inside the container.
            foreach ($item in @('Invoke-MatrixGenerator.ps1', 'src', 'tests', 'fixtures', '.github', '.actrc')) {
                Copy-Item -Path (Join-Path $script:RepoRoot $item) -Destination $temp -Recurse -Force
            }
            # The case's fixture becomes the pipeline's config.
            Copy-Item -Path (Join-Path $script:RepoRoot 'fixtures' $ConfigFixture) `
                -Destination (Join-Path $temp 'fixtures' 'ci-config.json') -Force
            # The act harness itself must not run inside the container.
            Remove-Item -Path (Join-Path $temp 'tests' 'ActPipeline.Tests.ps1') -Force

            Push-Location $temp
            try {
                git init -q -b main 2>&1 | Out-Null
                git -c user.email='harness@example.com' -c user.name='Harness' add -A 2>&1 | Out-Null
                git -c user.email='harness@example.com' -c user.name='Harness' commit -q -m 'test case' 2>&1 | Out-Null

                $output = act push --rm --pull=false 2>&1 | ForEach-Object { [string]$_ }
                $exitCode = $LASTEXITCODE
            }
            finally {
                Pop-Location
            }

            # Append the delimited output to the required artifact.
            $banner = @(
                '=' * 78
                "== TEST CASE: $CaseName  (config: fixtures/$ConfigFixture)"
                "== act exit code: $exitCode"
                '=' * 78
            )
            Add-Content -Path $script:ActResultPath -Value ($banner + $output + @(''))

            return [pscustomobject]@{
                Output   = ($output -join "`n")
                Lines    = $output
                ExitCode = $exitCode
            }
        }
        finally {
            Remove-Item -Path $temp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    function Get-MarkedJson {
        <#
            Extracts the JSON line the workflow echoes between the
            MATRIX-JSON-BEGIN/END markers, stripping act's "[job] | " prefix.
        #>
        # AllowEmptyString: act output legitimately contains blank lines, and
        # a Mandatory [string[]] would otherwise reject them at binding time.
        param([Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Lines)

        for ($i = 0; $i -lt $Lines.Count - 1; $i++) {
            if ($Lines[$i] -match 'MATRIX-JSON-BEGIN') {
                return ($Lines[$i + 1] -replace '^.*?\|\s*', '').Trim()
            }
        }
        return $null
    }
}

Describe 'Pipeline via act: case1 - basic 2x2 matrix with fail-fast and max-parallel' -Tag 'Act' {
    BeforeAll {
        $script:result = Invoke-ActCase -CaseName 'case1' -ConfigFixture 'case1-config.json'
        $script:expectedJson = (Get-Content (Join-Path $RepoRoot 'fixtures' 'case1-expected.json') -Raw).Trim()
    }

    It 'act exits with code 0' {
        $result.ExitCode | Should -Be 0
    }

    It 'the generate-matrix job emits the exact expected strategy JSON' {
        Get-MarkedJson -Lines $result.Lines | Should -Be $expectedJson
    }

    It 'spawns exactly the four expected matrix combinations' {
        $result.Output | Should -BeLike '*COMBO :: os=ubuntu-22.04 version=3.11*'
        $result.Output | Should -BeLike '*COMBO :: os=ubuntu-22.04 version=3.12*'
        $result.Output | Should -BeLike '*COMBO :: os=windows-2022 version=3.11*'
        $result.Output | Should -BeLike '*COMBO :: os=windows-2022 version=3.12*'
        @($result.Lines | Where-Object { $_ -match 'COMBO ::' }).Count | Should -Be 4
    }

    It 'every job reports success (test + generate-matrix + 4 matrix legs = 6)' {
        @($result.Lines | Where-Object { $_ -match 'Job succeeded' }).Count | Should -Be 6
        @($result.Lines | Where-Object { $_ -match 'Job failed' }).Count | Should -Be 0
    }
}

Describe 'Pipeline via act: case2 - feature flags with include/exclude rules' -Tag 'Act' {
    BeforeAll {
        $script:result = Invoke-ActCase -CaseName 'case2' -ConfigFixture 'case2-config.json'
        $script:expectedJson = (Get-Content (Join-Path $RepoRoot 'fixtures' 'case2-expected.json') -Raw).Trim()
    }

    It 'act exits with code 0' {
        $result.ExitCode | Should -Be 0
    }

    It 'the generate-matrix job emits the exact expected strategy JSON' {
        Get-MarkedJson -Lines $result.Lines | Should -Be $expectedJson
    }

    It 'spawns exactly the four expected combinations (exclude dropped macos+experimental, includes merged/appended)' {
        $result.Output | Should -BeLike '*COMBO :: flags=standard os=ubuntu-22.04 version=3.12*'
        # The include rule merged coverage=true into the experimental leg.
        $result.Output | Should -BeLike '*COMBO :: coverage=True flags=experimental os=ubuntu-22.04 version=3.12*'
        $result.Output | Should -BeLike '*COMBO :: flags=standard os=macos-14 version=3.12*'
        # The non-matching include was appended as a brand-new combination.
        $result.Output | Should -BeLike '*COMBO :: flags=standard os=windows-2022 version=3.13*'
        # The excluded combination must NOT run.
        $result.Output | Should -Not -BeLike '*COMBO :: flags=experimental os=macos-14*'
        @($result.Lines | Where-Object { $_ -match 'COMBO ::' }).Count | Should -Be 4
    }

    It 'every job reports success (test + generate-matrix + 4 matrix legs = 6)' {
        @($result.Lines | Where-Object { $_ -match 'Job succeeded' }).Count | Should -Be 6
        @($result.Lines | Where-Object { $_ -match 'Job failed' }).Count | Should -Be 0
    }
}

Describe 'act-result.txt artifact' -Tag 'Act' {
    It 'exists and contains both delimited test cases' {
        Test-Path $ActResultPath | Should -BeTrue
        $content = Get-Content $ActResultPath -Raw
        $content | Should -BeLike '*TEST CASE: case1*'
        $content | Should -BeLike '*TEST CASE: case2*'
    }
}
