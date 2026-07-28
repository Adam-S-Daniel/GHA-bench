# Simple test runner that sources functions and runs tests
param(
    [switch]$Verbose
)

# Import the implementation functions
. "$PSScriptRoot/Semantic-Version-Bumper.ps1"

# Setup test directory
$testDir = "$PSScriptRoot/test-fixtures"
if (Test-Path $testDir) { Remove-Item $testDir -Recurse -Force }
$null = New-Item -ItemType Directory -Path $testDir

# Run Pester
$pesterConfig = New-PesterConfiguration
$pesterConfig.Run.Path = "$PSScriptRoot/Semantic-Version-Bumper.Tests.ps1"
$pesterConfig.Run.PassThru = $true
if ($Verbose) { $pesterConfig.Output.Verbosity = 'Detailed' }

Invoke-Pester -Configuration $pesterConfig
