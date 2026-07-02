# Structural tests for the GitHub Actions workflow itself: valid YAML,
# expected triggers/jobs/steps, correct references to project files, and a
# clean actionlint run. These are static checks on the workflow file and are
# separate from the act-based pipeline execution tests in scripts/run-act-tests.sh.

BeforeAll {
    $script:workflowPath = "$PSScriptRoot/.github/workflows/pr-label-assigner.yml"
    $script:workflowText = Get-Content -Path $workflowPath -Raw

    # pwsh has no built-in YAML parser; use `yq`/python if available, else a
    # minimal check via ConvertFrom-Yaml if the powershell-yaml module is
    # present. Fall back to actionlint (which already validates YAML syntax)
    # plus targeted regex/text assertions for structure, which keeps this
    # test free of extra dependencies.
}

Describe "pr-label-assigner.yml structure" {
    It "exists at the expected workflow path" {
        Test-Path -Path $workflowPath -PathType Leaf | Should -BeTrue
    }

    It "is parseable YAML (no tabs, consistent structure) via python3 yaml" {
        $pyCheck = python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" $workflowPath 2>&1
        $LASTEXITCODE | Should -Be 0 -Because "python3's yaml.safe_load should parse the file without error: $pyCheck"
    }

    It "declares push, pull_request, and workflow_dispatch triggers" {
        $doc = python3 -c "import yaml,json,sys; print(json.dumps(yaml.safe_load(open(sys.argv[1]))))" $workflowPath | ConvertFrom-Json
        # PyYAML's 1.1 resolver parses the bareword key 'on' as boolean True,
        # which json.dumps then renders as the string key "true".
        $onKey = if ($doc.PSObject.Properties['on']) { 'on' } else { 'true' }
        $triggers = $doc.$onKey
        $triggers.PSObject.Properties.Name | Should -Contain 'push'
        $triggers.PSObject.Properties.Name | Should -Contain 'pull_request'
        $triggers.PSObject.Properties.Name | Should -Contain 'workflow_dispatch'
    }

    It "defines a 'test' job and an 'assign-labels' job that depends on 'test'" {
        $doc = python3 -c "import yaml,json,sys; print(json.dumps(yaml.safe_load(open(sys.argv[1]))))" $workflowPath | ConvertFrom-Json
        $doc.jobs.PSObject.Properties.Name | Should -Contain 'test'
        $doc.jobs.PSObject.Properties.Name | Should -Contain 'assign-labels'
        $doc.jobs.'assign-labels'.needs | Should -Be 'test'
    }

    It "checks out the repo and runs the Pester test suite in the 'test' job" {
        $doc = python3 -c "import yaml,json,sys; print(json.dumps(yaml.safe_load(open(sys.argv[1]))))" $workflowPath | ConvertFrom-Json
        $steps = $doc.jobs.test.steps
        ($steps | Where-Object { $_.uses -like 'actions/checkout@*' }) | Should -Not -BeNullOrEmpty
        ($steps | Where-Object { $_.run -match 'Invoke-Pester' }) | Should -Not -BeNullOrEmpty
    }

    It "references PrLabelAssigner.ps1 in the 'assign-labels' job, and that file exists" {
        $doc = python3 -c "import yaml,json,sys; print(json.dumps(yaml.safe_load(open(sys.argv[1]))))" $workflowPath | ConvertFrom-Json
        $steps = $doc.jobs.'assign-labels'.steps
        ($steps | Where-Object { $_.run -match '\./PrLabelAssigner\.ps1' }) | Should -Not -BeNullOrEmpty
        Test-Path -Path "$PSScriptRoot/PrLabelAssigner.ps1" -PathType Leaf | Should -BeTrue
    }

    It "references rules.json and fixtures/changed-files.json, and both exist" {
        Test-Path -Path "$PSScriptRoot/rules.json" -PathType Leaf | Should -BeTrue
        Test-Path -Path "$PSScriptRoot/fixtures/changed-files.json" -PathType Leaf | Should -BeTrue
        $workflowText | Should -Match "rules_path"
        $workflowText | Should -Match "changed_files_path"
    }

    It "declares contents:read and pull-requests:write permissions" {
        $doc = python3 -c "import yaml,json,sys; print(json.dumps(yaml.safe_load(open(sys.argv[1]))))" $workflowPath | ConvertFrom-Json
        $doc.permissions.contents | Should -Be 'read'
        $doc.permissions.'pull-requests' | Should -Be 'write'
    }

    It "passes actionlint with exit code 0" {
        $actionlintOutput = & actionlint $workflowPath 2>&1
        $LASTEXITCODE | Should -Be 0 -Because "actionlint output: $actionlintOutput"
    }
}
