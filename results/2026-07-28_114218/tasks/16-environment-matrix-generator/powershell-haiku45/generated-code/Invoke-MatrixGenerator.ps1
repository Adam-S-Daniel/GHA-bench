# Environment Matrix Generator for GitHub Actions
# Generates a build matrix JSON from configuration with support for include/exclude rules

function Invoke-MatrixGenerator {
    <#
    .SYNOPSIS
    Generates a GitHub Actions strategy matrix from configuration.

    .DESCRIPTION
    Takes OS options, language versions, and feature flags, then generates a build matrix
    as JSON suitable for GitHub Actions strategy.matrix.

    .PARAMETER Configuration
    Hashtable containing:
      - os: array of operating systems
      - version: array of version strings
      - features: array of feature flags (optional)
      - include: array of include rules (optional)
      - exclude: array of exclude rules (optional)
      - maxParallel: max concurrent jobs (optional)
      - failFast: whether to fail fast (optional)
      - maxSize: maximum matrix combinations (default 256)

    .EXAMPLE
    $config = @{
        os = @("ubuntu", "windows")
        version = @("1.0", "2.0")
    }
    Invoke-MatrixGenerator -Configuration $config
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Configuration
    )

    # Initialize result matrix
    $matrix = @{
        include = @()
    }

    # Get configuration values with defaults
    $osOptions = $Configuration["os"] ?? @()
    $versionOptions = $Configuration["version"] ?? @()
    $featureOptions = $Configuration["features"] ?? @()
    $includeRules = $Configuration["include"] ?? @()
    $excludeRules = $Configuration["exclude"] ?? @()
    $maxParallel = $Configuration["maxParallel"] ?? $null
    $failFast = $Configuration["failFast"] ?? $false
    $maxSize = $Configuration["maxSize"] ?? 256

    # Generate base matrix combinations
    if ($osOptions.Count -gt 0 -and $versionOptions.Count -gt 0) {
        # Both OS and version specified
        foreach ($os in $osOptions) {
            foreach ($version in $versionOptions) {
                if ($featureOptions.Count -gt 0) {
                    foreach ($feature in $featureOptions) {
                        $combination = @{
                            os      = $os
                            version = $version
                            feature = $feature
                        }
                        $matrix.include += $combination
                    }
                } else {
                    $combination = @{
                        os      = $os
                        version = $version
                    }
                    $matrix.include += $combination
                }
            }
        }
    } elseif ($osOptions.Count -gt 0) {
        # Only OS specified
        foreach ($os in $osOptions) {
            if ($featureOptions.Count -gt 0) {
                foreach ($feature in $featureOptions) {
                    $combination = @{
                        os      = $os
                        feature = $feature
                    }
                    $matrix.include += $combination
                }
            } else {
                $combination = @{
                    os = $os
                }
                $matrix.include += $combination
            }
        }
    } elseif ($versionOptions.Count -gt 0) {
        # Only version specified
        foreach ($version in $versionOptions) {
            if ($featureOptions.Count -gt 0) {
                foreach ($feature in $featureOptions) {
                    $combination = @{
                        version = $version
                        feature = $feature
                    }
                    $matrix.include += $combination
                }
            } else {
                $combination = @{
                    version = $version
                }
                $matrix.include += $combination
            }
        }
    } elseif ($featureOptions.Count -gt 0) {
        # Only features specified
        foreach ($feature in $featureOptions) {
            $combination = @{
                feature = $feature
            }
            $matrix.include += $combination
        }
    }

    # Apply include rules
    foreach ($rule in $includeRules) {
        $matrix.include += $rule
    }

    # Apply exclude rules
    if ($excludeRules.Count -gt 0) {
        $matrix.exclude = @()
        foreach ($rule in $excludeRules) {
            $matrix.exclude += $rule
        }
    }

    # Add optional configuration
    if ($maxParallel) {
        $matrix["max-parallel"] = $maxParallel
    }

    if ($failFast) {
        $matrix["fail-fast"] = $failFast
    }

    # Validate matrix size
    if ($matrix.include.Count -gt $maxSize) {
        throw "Matrix size ($($matrix.include.Count)) exceeds maximum allowed ($maxSize)"
    }

    # Convert to JSON and return
    return $matrix | ConvertTo-Json -Depth 10
}

