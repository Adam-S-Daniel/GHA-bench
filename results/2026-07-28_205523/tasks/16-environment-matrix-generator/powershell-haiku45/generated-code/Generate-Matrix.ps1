# Generate-Matrix.ps1
# Wrapper script for GitHub Actions that reads config and outputs matrix as JSON
# Usage: pwsh Generate-Matrix.ps1 -ConfigPath config.json -OutputVariable MATRIX

param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = "matrix-config.json",

    [Parameter(Mandatory = $false)]
    [string]$OutputVariable = "MATRIX"
)

# Import the matrix generator function
. $PSScriptRoot/New-GitHubActionsMatrix.ps1

# Read configuration from JSON file
if (-not (Test-Path $ConfigPath)) {
    Write-Error "Configuration file not found: $ConfigPath"
    exit 1
}

try {
    $configJson = Get-Content -Path $ConfigPath -Raw
    $config = $configJson | ConvertFrom-Json -AsHashtable
}
catch {
    Write-Error "Failed to parse configuration JSON: $_"
    exit 1
}

try {
    # Generate the matrix
    $matrix = New-GitHubActionsMatrix -Config $config

    # Convert to JSON and output
    $matrixJson = $matrix | ConvertTo-Json -Depth 10

    # Output for GitHub Actions (write to STDOUT and also set output variable)
    Write-Host $matrixJson
    Write-Host "::set-output name=$OutputVariable::$matrixJson"

    # For GitHub Actions environment, also write to $GITHUB_OUTPUT if it exists
    if ($env:GITHUB_OUTPUT) {
        Add-Content -Path $env:GITHUB_OUTPUT -Value "$OutputVariable=$matrixJson"
    }

    exit 0
}
catch {
    Write-Error "Failed to generate matrix: $_"
    exit 1
}
