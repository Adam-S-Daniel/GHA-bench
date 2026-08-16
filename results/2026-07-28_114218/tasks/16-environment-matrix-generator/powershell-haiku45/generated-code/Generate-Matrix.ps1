# Wrapper script to generate GitHub Actions matrix from configuration file
# Usage: ./Generate-Matrix.ps1 -ConfigFile matrix-config.json

param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigFile = "matrix-config.json",

    [Parameter(Mandatory = $false)]
    [string]$OutputFile = $null
)

# Import the matrix generator function
. $PSScriptRoot/Invoke-MatrixGenerator.ps1

try {
    # Check if config file exists
    if (-not (Test-Path $ConfigFile)) {
        Write-Error "Configuration file not found: $ConfigFile"
        exit 1
    }

    # Read and parse JSON configuration
    $configJson = Get-Content $ConfigFile -Raw
    $configuration = $configJson | ConvertFrom-Json -AsHashtable

    # Generate the matrix
    $matrixJson = Invoke-MatrixGenerator -Configuration $configuration

    # Output result
    if ($OutputFile) {
        $matrixJson | Out-File -FilePath $OutputFile -Encoding UTF8
        Write-Output "Matrix generated successfully and saved to: $OutputFile"
        Write-Output $matrixJson
    } else {
        Write-Output $matrixJson
    }

    exit 0
} catch {
    Write-Error "Error generating matrix: $_"
    exit 1
}
