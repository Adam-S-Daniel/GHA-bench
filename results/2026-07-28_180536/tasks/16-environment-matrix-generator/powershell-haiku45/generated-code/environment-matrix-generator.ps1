#!/usr/bin/env pwsh
# Environment Matrix Generator for GitHub Actions
# Generates a build matrix (JSON) suitable for GitHub Actions strategy.matrix
#
# Approach:
# 1. Parse configuration with OS options, language versions, and feature flags
# 2. Generate cartesian product of all options
# 3. Apply include/exclude rules
# 4. Validate matrix size doesn't exceed limits
# 5. Return JSON-compatible object with include array and strategy options

param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath,

    [Parameter(Mandatory = $false)]
    [pscustomobject]$Config
)

function New-EnvironmentMatrix {
    <#
    .SYNOPSIS
    Generates a GitHub Actions matrix from a configuration object.

    .PARAMETER Config
    Configuration object with operatingSystems, languageVersions, features, include, exclude, maxSize, maxParallel, failFast

    .RETURNS
    PSCustomObject with include array and strategy options suitable for GitHub Actions
    #>

    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [pscustomobject]$Config
    )

    # Validate input
    if ($null -eq $Config) {
        throw "Config is required but was null. Pass a valid configuration object."
    }

    if ($null -eq $Config.operatingSystems) {
        throw "operatingSystems is required in config"
    }

    $osCount = @($Config.operatingSystems).Count
    if ($osCount -eq 0) {
        throw "operatingSystems is required and cannot be empty - must contain at least one OS"
    }

    # Initialize matrix with empty include array
    $matrixEntries = [System.Collections.ArrayList]@()

    # Get configuration values with defaults
    $oses = $Config.operatingSystems | Where-Object { $_ }
    $versions = if ($Config.languageVersions) { @($Config.languageVersions) } else { @() }
    $features = if ($Config.features) { @($Config.features) } else { @() }

    # If no versions and no features, just use OS
    if ($versions.Count -eq 0 -and $features.Count -eq 0) {
        foreach ($os in $oses) {
            $entry = @{ os = $os }
            $matrixEntries.Add([pscustomobject]$entry) | Out-Null
        }
    }
    # If features but no versions, create feature combinations
    elseif ($features.Count -gt 0 -and $versions.Count -eq 0) {
        # Generate all combinations of features (power set)
        $featureCombinations = Get-FeatureCombinations -Features $features

        foreach ($os in $oses) {
            foreach ($combo in $featureCombinations) {
                $entry = @{ os = $os; features = $combo }
                $matrixEntries.Add([pscustomobject]$entry) | Out-Null
            }
        }
    }
    # If versions but no features
    elseif ($versions.Count -gt 0 -and $features.Count -eq 0) {
        foreach ($os in $oses) {
            foreach ($version in $versions) {
                $entry = @{ os = $os; languageVersion = $version }
                $matrixEntries.Add([pscustomobject]$entry) | Out-Null
            }
        }
    }
    # If both versions and features
    else {
        $featureCombinations = Get-FeatureCombinations -Features $features

        foreach ($os in $oses) {
            foreach ($version in $versions) {
                foreach ($combo in $featureCombinations) {
                    $entry = @{ os = $os; languageVersion = $version; features = $combo }
                    $matrixEntries.Add([pscustomobject]$entry) | Out-Null
                }
            }
        }
    }

    # Apply exclude rules if provided
    if ($Config.exclude) {
        foreach ($excludeRule in $Config.exclude) {
            # Ensure exclude rule is a PSCustomObject for consistent property access
            if ($excludeRule -is [hashtable]) {
                $excludeRule = [pscustomobject]$excludeRule
            }
            $filtered = Apply-ExcludeRule -Entries $matrixEntries -ExcludeRule $excludeRule
            $matrixEntries = [System.Collections.ArrayList]$filtered
        }
    }

    # Add include rules if provided
    if ($Config.include) {
        foreach ($includeRule in $Config.include) {
            $matrixEntries.Add([pscustomobject]$includeRule) | Out-Null
        }
    }

    # Validate matrix size
    $maxSize = if ($Config.maxSize) { $Config.maxSize } else { 256 }
    if ($matrixEntries.Count -gt $maxSize) {
        throw "Matrix size ($($matrixEntries.Count)) exceeds maximum allowed ($maxSize)"
    }

    # Build result object
    $result = @{
        include = $matrixEntries
    }

    # Add strategy options
    if ($Config.maxParallel) {
        $result['maxParallel'] = $Config.maxParallel
    }

    if ($null -ne $Config.failFast) {
        $result['failFast'] = $Config.failFast
    }

    return [pscustomobject]$result
}

function Get-FeatureCombinations {
    <#
    .SYNOPSIS
    Generates all possible combinations of features (power set)

    .PARAMETER Features
    Array of feature names

    .RETURNS
    Array of arrays, each representing a combination of features
    #>

    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Features
    )

    $combinations = [System.Collections.ArrayList]@()

    # Generate all combinations using bit manipulation (0 to 2^n - 1)
    $numCombinations = [Math]::Pow(2, $Features.Count)

    for ($i = 0; $i -lt $numCombinations; $i++) {
        $combo = [System.Collections.ArrayList]@()

        for ($j = 0; $j -lt $Features.Count; $j++) {
            if (($i -band (1 -shl $j)) -gt 0) {
                $combo.Add($Features[$j]) | Out-Null
            }
        }

        # Add this combination (even if empty)
        if ($combo.Count -gt 0) {
            $combinations.Add($combo.ToArray()) | Out-Null
        } else {
            # For empty combination, add as single-element array to represent "no features"
            $combinations.Add(@()) | Out-Null
        }
    }

    return $combinations.ToArray()
}

function Apply-ExcludeRule {
    <#
    .SYNOPSIS
    Removes entries from matrix that match the exclude rule

    .PARAMETER Entries
    Current matrix entries

    .PARAMETER ExcludeRule
    Rule object with properties to match

    .RETURNS
    Filtered entries array
    #>

    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.ArrayList]$Entries,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$ExcludeRule
    )

    $filtered = [System.Collections.ArrayList]@()

    foreach ($entry in $Entries) {
        $matches = $true

        # Check if all properties in exclude rule match this entry
        foreach ($property in $ExcludeRule.PSObject.Properties) {
            $propName = $property.Name
            $propValue = $property.Value

            # Get property value from entry using dot notation
            $entryValue = $entry.$propName

            if ($null -eq $entryValue) {
                $matches = $false
                break
            }

            # Compare values (handle both direct values and arrays)
            if ($entryValue -ne $propValue) {
                $matches = $false
                break
            }
        }

        # Keep entries that don't match the exclude rule
        if (-not $matches) {
            $filtered.Add($entry) | Out-Null
        }
    }

    return $filtered
}

# If script is run standalone (not dot-sourced), process command line arguments
# Check if ConfigPath is provided, which indicates standalone execution
if ($PSBoundParameters.ContainsKey('ConfigPath') -or (-not [string]::IsNullOrEmpty($ConfigPath))) {
    try {
        if ($ConfigPath) {
            # Load configuration from JSON file
            if (-not (Test-Path $ConfigPath)) {
                throw "Config file not found: $ConfigPath"
            }

            $configJson = Get-Content -Path $ConfigPath -Raw
            $Config = $configJson | ConvertFrom-Json -AsHashtable
        }

        if (-not $Config) {
            throw "No configuration provided. Use -ConfigPath or pass config via pipeline"
        }

        # Generate matrix
        $matrix = New-EnvironmentMatrix -Config $Config

        # Output as JSON
        $matrix | ConvertTo-Json -Depth 10
    }
    catch {
        Write-Error "Error generating matrix: $_"
        exit 1
    }
}
