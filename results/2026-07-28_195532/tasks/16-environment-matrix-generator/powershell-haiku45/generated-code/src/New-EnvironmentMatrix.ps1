function New-EnvironmentMatrix {
    <#
    .SYNOPSIS
    Generates a GitHub Actions build matrix from OS options, language versions, and feature flags.

    .DESCRIPTION
    Creates a matrix suitable for GitHub Actions strategy.matrix with support for:
    - Base combinations of OS, language versions, and feature flags
    - Include rules to add specific combinations
    - Exclude rules to remove specific combinations
    - Max parallel limit enforcement
    - Fail-fast policy configuration
    - Matrix size validation

    .PARAMETER Config
    Hashtable with configuration containing:
    - os: array of OS options
    - language: array of language versions
    - features: optional array of feature flags
    - include: optional array of hashtables for extra combinations
    - exclude: optional array of hashtables for combinations to remove
    - maxParallel: optional integer for max concurrent jobs
    - failFast: optional boolean for fail-fast policy
    - maxSize: optional integer for maximum matrix size (default 256)

    .PARAMETER AsJson
    Return the matrix as a JSON string instead of a hashtable.

    .EXAMPLE
    $config = @{
        os = @("ubuntu-latest", "windows-latest")
        language = @("3.10", "3.11")
        maxParallel = 4
        failFast = $true
    }
    $matrix = New-EnvironmentMatrix -Config $config -AsJson
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config,

        [Parameter(Mandatory = $false)]
        [switch]$AsJson
    )

    # Validate configuration has at least os or language
    if (-not $Config.os -and -not $Config.language) {
        throw "Configuration must contain at least 'os' or 'language' array"
    }

    # Initialize matrix structure
    $matrix = @{
        include = @()
    }

    # Get dimensions with defaults
    $osValues = @($Config.os) | Where-Object { $_ }
    $languageValues = @($Config.language) | Where-Object { $_ }
    $features = @($Config.features) | Where-Object { $_ }

    # Generate base combinations (Cartesian product)
    if ($osValues.Count -gt 0 -and $languageValues.Count -gt 0) {
        foreach ($os in $osValues) {
            foreach ($lang in $languageValues) {
                $combo = @{
                    os       = $os
                    language = $lang
                }
                if ($features.Count -gt 0) {
                    $combo.features = $features -join ','
                }
                $matrix.include += $combo
            }
        }
    } elseif ($osValues.Count -gt 0) {
        # Only OS, no language
        foreach ($os in $osValues) {
            $combo = @{ os = $os }
            if ($features.Count -gt 0) {
                $combo.features = $features -join ','
            }
            $matrix.include += $combo
        }
    } else {
        # Only language, no OS
        foreach ($lang in $languageValues) {
            $combo = @{ language = $lang }
            if ($features.Count -gt 0) {
                $combo.features = $features -join ','
            }
            $matrix.include += $combo
        }
    }

    # Add explicit include combinations
    if ($Config.include) {
        foreach ($includeCombo in $Config.include) {
            $newCombo = @{}
            foreach ($key in $includeCombo.Keys) {
                $newCombo[$key] = $includeCombo[$key]
            }
            if ($features.Count -gt 0 -and -not $newCombo.features) {
                $newCombo.features = $features -join ','
            }
            $matrix.include += $newCombo
        }
    }

    # Remove excluded combinations
    if ($Config.exclude) {
        foreach ($excludeCombo in $Config.exclude) {
            $matrix.include = $matrix.include | Where-Object {
                $item = $_
                $matches = $true
                foreach ($key in $excludeCombo.Keys) {
                    if ($item[$key] -ne $excludeCombo[$key]) {
                        $matches = $false
                        break
                    }
                }
                -not $matches
            }
        }
    }

    # Validate matrix size
    $maxSize = if ($Config.maxSize) { $Config.maxSize } else { 256 }
    if ($matrix.include.Count -gt $maxSize) {
        throw "Matrix size ($($matrix.include.Count)) exceeds maximum allowed ($maxSize)"
    }

    # Add optional settings
    if ($null -ne $Config.maxParallel) {
        $matrix.'max-parallel' = $Config.maxParallel
    }

    if ($null -ne $Config.failFast) {
        $matrix.'fail-fast' = $Config.failFast
    }

    # Return as JSON or hashtable
    if ($AsJson) {
        return $matrix | ConvertTo-Json -Depth 10
    }
    return $matrix
}
