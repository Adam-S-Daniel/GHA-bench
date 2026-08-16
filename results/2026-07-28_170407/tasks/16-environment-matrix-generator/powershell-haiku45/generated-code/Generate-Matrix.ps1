# Generate-Matrix.ps1 - Entry point for GitHub Actions workflow
# Reads JSON config from stdin or file, generates build matrix, outputs as JSON

param(
    [Parameter(Mandatory=$false)]
    [string]$ConfigFile,

    [Parameter(Mandatory=$false)]
    [string]$OutputFile
)

# Source the main module
. ./Build-Matrix.ps1

# Read config from file or stdin
if ($ConfigFile -and (Test-Path $ConfigFile)) {
    $configJson = Get-Content $ConfigFile | ConvertFrom-Json
} else {
    # Try to read from stdin
    $configJson = $input | ConvertFrom-Json -ErrorAction SilentlyContinue
    if (-not $configJson) {
        Write-Error "No configuration provided. Either pass --ConfigFile or pipe JSON to stdin."
        exit 1
    }
}

# Convert JSON object to hashtable
$config = @{}
if ($configJson) {
    foreach ($prop in $configJson.PSObject.Properties) {
        if ($prop.Value -is [PSCustomObject]) {
            $config[$prop.Name] = $prop.Value
        } else {
            $config[$prop.Name] = $prop.Value
        }
    }
}

# Generate the matrix
try {
    $matrix = Build-Matrix -Config $config
    $matrixJson = $matrix | ConvertTo-Json -Depth 10

    if ($OutputFile) {
        $matrixJson | Out-File -FilePath $OutputFile -Encoding UTF8
        Write-Output "Matrix saved to $OutputFile"
    } else {
        Write-Output $matrixJson
    }
} catch {
    Write-Error "Failed to generate matrix: $_"
    exit 1
}
