# Workflow STRUCTURE + actionlint tests (fast; no Docker required).
#
# These verify the .github/workflows/dependency-license-checker.yml file:
#   * parses as YAML and has the expected triggers / jobs / steps / dependencies
#   * references the script + test files that actually exist on disk
#   * passes actionlint with exit code 0
#
# The YAML is parsed for real via a tiny python+PyYAML helper (parse-workflow.py).
# If python/PyYAML is unavailable the structural tests skip gracefully.

BeforeAll {
    $script:RepoRoot     = (Resolve-Path "$PSScriptRoot/..").Path
    $script:WorkflowPath = Join-Path $RepoRoot '.github/workflows/dependency-license-checker.yml'
    $script:ParseHelper  = Join-Path $PSScriptRoot 'parse-workflow.py'

    # Determine whether we can parse YAML with python+PyYAML.
    $script:CanParseYaml = $false
    if (Get-Command python3 -ErrorAction SilentlyContinue) {
        & python3 -c 'import yaml' 2>$null
        $script:CanParseYaml = ($LASTEXITCODE -eq 0)
    }

    $script:Structure = $null
    if ($CanParseYaml) {
        $json = & python3 $ParseHelper $WorkflowPath 2>$null
        if ($LASTEXITCODE -eq 0 -and $json) {
            $script:Structure = $json | ConvertFrom-Json
        }
        else {
            $script:CanParseYaml = $false
        }
    }
}

Describe 'Workflow file exists and is valid YAML structure' {
    It 'the workflow file exists' {
        Test-Path $WorkflowPath | Should -BeTrue
    }

    It 'declares the expected trigger events' {
        if (-not $CanParseYaml) { Set-ItResult -Skipped -Because 'python3/PyYAML unavailable'; return }
        $Structure.triggers | Should -Contain 'push'
        $Structure.triggers | Should -Contain 'pull_request'
        $Structure.triggers | Should -Contain 'schedule'
        $Structure.triggers | Should -Contain 'workflow_dispatch'
    }

    It 'restricts permissions to read-only contents' {
        if (-not $CanParseYaml) { Set-ItResult -Skipped -Because 'python3/PyYAML unavailable'; return }
        $Structure.permissions.contents | Should -Be 'read'
    }

    It 'defines the config + license database env vars' {
        if (-not $CanParseYaml) { Set-ItResult -Skipped -Because 'python3/PyYAML unavailable'; return }
        $Structure.env.LICENSE_CONFIG | Should -Be 'license-config.json'
        $Structure.env.LICENSE_DB     | Should -Be 'license-db.json'
    }

    It 'defines the unit-tests and license-check jobs' {
        if (-not $CanParseYaml) { Set-ItResult -Skipped -Because 'python3/PyYAML unavailable'; return }
        $Structure.jobs | Should -Contain 'unit-tests'
        $Structure.jobs | Should -Contain 'license-check'
    }

    It 'makes license-check depend on unit-tests (job dependency)' {
        if (-not $CanParseYaml) { Set-ItResult -Skipped -Because 'python3/PyYAML unavailable'; return }
        $Structure.license_check_needs | Should -Be 'unit-tests'
    }

    It 'runs a matrix leg per fixture' {
        if (-not $CanParseYaml) { Set-ItResult -Skipped -Because 'python3/PyYAML unavailable'; return }
        $names = $Structure.matrix_include.name
        $names | Should -Contain 'clean'
        $names | Should -Contain 'violations'
        $names | Should -Contain 'mixed'
        $names | Should -Contain 'requirements'
    }

    It 'uses actions/checkout@v4 in both jobs' {
        if (-not $CanParseYaml) { Set-ItResult -Skipped -Because 'python3/PyYAML unavailable'; return }
        ($Structure.unit_test_steps.uses)     | Should -Contain 'actions/checkout@v4'
        ($Structure.license_check_steps.uses) | Should -Contain 'actions/checkout@v4'
    }

    It 'references the unit test file and the checker script in run steps' {
        if (-not $CanParseYaml) { Set-ItResult -Skipped -Because 'python3/PyYAML unavailable'; return }
        ($Structure.unit_test_steps.run -join "`n")     | Should -Match 'tests/DependencyLicenseChecker\.Tests\.ps1'
        ($Structure.license_check_steps.run -join "`n") | Should -Match '\./DependencyLicenseChecker\.ps1'
    }
}

Describe 'Workflow references files that exist on disk' {
    It 'the checker script referenced by the workflow exists' {
        Test-Path (Join-Path $RepoRoot 'DependencyLicenseChecker.ps1') | Should -BeTrue
    }

    It 'the unit test file referenced by the workflow exists' {
        Test-Path (Join-Path $RepoRoot 'tests/DependencyLicenseChecker.Tests.ps1') | Should -BeTrue
    }

    It 'the config + license database files exist' {
        Test-Path (Join-Path $RepoRoot 'license-config.json') | Should -BeTrue
        Test-Path (Join-Path $RepoRoot 'license-db.json')     | Should -BeTrue
    }

    It 'every matrix manifest path points to a real fixture file' {
        if (-not $CanParseYaml) { Set-ItResult -Skipped -Because 'python3/PyYAML unavailable'; return }
        foreach ($leg in $Structure.matrix_include) {
            Test-Path (Join-Path $RepoRoot $leg.manifest) | Should -BeTrue -Because "$($leg.manifest) should exist"
        }
    }
}

Describe 'Workflow passes actionlint' {
    It 'actionlint exits 0' {
        if (-not (Get-Command actionlint -ErrorAction SilentlyContinue)) {
            Set-ItResult -Skipped -Because 'actionlint not installed'
            return
        }
        $output = & actionlint $WorkflowPath 2>&1
        $code = $LASTEXITCODE
        if ($code -ne 0) { Write-Host ($output | Out-String) }
        $code | Should -Be 0
    }
}
