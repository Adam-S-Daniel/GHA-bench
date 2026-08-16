# Build-Matrix.ps1 - GitHub Actions build matrix generator
# Generates a build matrix JSON from OS, language versions, and feature flags

# Helper function to convert PSCustomObject to hashtable recursively
function ConvertTo-Hashtable {
    param($Object)

    if ($Object -is [hashtable]) {
        return $Object
    }

    if ($Object -is [PSCustomObject]) {
        $hashtable = @{}
        foreach ($prop in $Object.PSObject.Properties) {
            $value = $prop.Value
            if ($value -is [PSCustomObject]) {
                $hashtable[$prop.Name] = ConvertTo-Hashtable $value
            } elseif ($value -is [object[]] -and $value.Count -gt 0 -and $value[0] -is [PSCustomObject]) {
                $hashtable[$prop.Name] = @($value | ForEach-Object { ConvertTo-Hashtable $_ })
            } else {
                $hashtable[$prop.Name] = $value
            }
        }
        return $hashtable
    }

    return $Object
}

function Build-Matrix {
    <#
    .SYNOPSIS
    Generates a GitHub Actions build matrix from configuration.

    .DESCRIPTION
    Takes OS options, language versions, and feature flags to create a build matrix
    suitable for GitHub Actions strategy.matrix. Supports include/exclude rules.

    .PARAMETER Config
    Hashtable or PSCustomObject with keys: os, languages, features, include, exclude, maxParallel, failFast
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        $Config
    )

    # Convert PSCustomObject to hashtable if needed
    if ($Config -is [PSCustomObject]) {
        $Config = ConvertTo-Hashtable $Config
    }

    # Initialize matrix structure
    $matrix = @{
        include = @()
        exclude = @()
    }

    # Generate base combinations from os, language versions, and features
    if ($Config.os -and $Config.os.Count -gt 0) {
        $combinations = @()

        # Generate all OS-based entries
        foreach ($osName in $Config.os) {
            $combinations += @{ os = $osName }
        }

        # Cross-product with language versions if specified
        if ($Config.languages -and $Config.languages.Count -gt 0) {
            $newCombinations = @()
            foreach ($combination in $combinations) {
                foreach ($langName in $Config.languages.Keys) {
                    foreach ($version in $Config.languages[$langName]) {
                        $newCombo = $combination.Clone()
                        $newCombo["$langName-version"] = $version
                        $newCombinations += $newCombo
                    }
                }
            }
            $combinations = $newCombinations
        }

        # Cross-product with feature flags if specified
        if ($Config.features -and $Config.features.Count -gt 0) {
            $newCombinations = @()
            foreach ($combination in $combinations) {
                foreach ($feature in $Config.features) {
                    $newCombo = $combination.Clone()
                    $newCombo['feature'] = $feature
                    $newCombinations += $newCombo
                }
            }
            $combinations = $newCombinations
        }

        $matrix.include = $combinations
    }

    # Add include entries
    if ($Config.include -and $Config.include.Count -gt 0) {
        $matrix.include += $Config.include
    }

    # Add exclude entries
    if ($Config.exclude -and $Config.exclude.Count -gt 0) {
        $matrix.exclude = $Config.exclude
    }

    # Add max-parallel if specified
    if ($Config.maxParallel -and $Config.maxParallel -gt 0) {
        $matrix.'max-parallel' = $Config.maxParallel
    }

    # Add fail-fast if specified
    if ($Config.failFast) {
        $matrix.'fail-fast' = $Config.failFast
    }

    # Validate matrix size if maxSize is specified
    if ($Config.maxSize -and $matrix.include.Count -gt $Config.maxSize) {
        throw "Matrix size ($($matrix.include.Count)) exceeds maximum allowed size ($($Config.maxSize))"
    }

    return $matrix
}
