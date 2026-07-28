$workflowPath = ".github/workflows/semantic-version-bumper.yml"

if (-not (Test-Path $workflowPath)) {
    Write-Error "Workflow file not found: $workflowPath"
    exit 1
}

$yaml = Get-Content $workflowPath -Raw
Write-Host "✓ Workflow file exists"

# Check for required triggers
if ($yaml -match "on:") {
    Write-Host "✓ Has trigger events"
}

# Check for jobs
if ($yaml -match "jobs:") {
    Write-Host "✓ Has jobs section"
}

# Check for specific jobs
$expectedJobs = @("test", "test-version-bumping", "test-changelog-generation", "test-mock-fixtures", "test-breaking-changes")
foreach ($job in $expectedJobs) {
    if ($yaml -match "^\s+$job`:") {
        Write-Host "✓ Has job: $job"
    } else {
        Write-Host "✗ Missing job: $job"
    }
}

# Check for pwsh shell
if ($yaml -match "shell: pwsh") {
    Write-Host "✓ Uses 'shell: pwsh' for correct cross-platform execution"
}

# Check for actions/checkout@v4
if ($yaml -match "uses: actions/checkout@v4") {
    Write-Host "✓ Uses actions/checkout@v4"
}

# Verify script files exist
$scriptFiles = @("SemanticVersionBumper.ps1", "SemanticVersionBumper.Tests.ps1")
foreach ($file in $scriptFiles) {
    if (Test-Path $file) {
        Write-Host "✓ Script file exists: $file"
    } else {
        Write-Host "✗ Missing script: $file"
    }
}

Write-Host ""
Write-Host "Workflow structure validation complete!"
