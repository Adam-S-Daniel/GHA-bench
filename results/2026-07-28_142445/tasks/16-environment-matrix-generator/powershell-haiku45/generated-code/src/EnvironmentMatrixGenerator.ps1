# Environment Matrix Generator for GitHub Actions
# Generates a build matrix from OS options, language versions, and feature flags

function New-EnvironmentMatrix {
    <#
    .SYNOPSIS
    Generates a GitHub Actions build matrix from configuration.

    .DESCRIPTION
    Creates a JSON-compatible build matrix (strategy.matrix) for GitHub Actions.
    Supports cartesian product generation, include/exclude rules, and size validation.

    .PARAMETER Configuration
    Hashtable with matrix dimensions as keys (arrays as values).
    Special keys: 'include' and 'exclude' for strategy rules.

    .PARAMETER MaxMatrixSize
    Maximum allowed combinations in the matrix. Default: 256.

    .PARAMETER MaxParallel
    Maximum parallel jobs. If provided, included in output.

    .PARAMETER FailFast
    Whether to fail all jobs if any job fails. Default: $false.

    .EXAMPLE
    $config = @{
        os = @("ubuntu-latest", "windows-latest")
        version = @("18", "20")
    }
    New-EnvironmentMatrix -Configuration $config

    .OUTPUTS
    PSCustomObject with 'include' array and optional 'max-parallel', 'fail-fast', and metadata.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Configuration,

        [int]$MaxMatrixSize = 256,

        [int]$MaxParallel = 0,

        [switch]$FailFast
    )

    # Validate configuration
    if ($Configuration.Count -eq 0) {
        return @{
            valid = $false
            error = "Configuration is empty"
            include = @()
        }
    }

    # Extract matrix dimensions and rules
    $dimensions = @{}
    $includeRules = @()
    $excludeRules = @()

    foreach ($key in $Configuration.Keys) {
        if ($key -eq 'include') {
            $includeRules = $Configuration[$key]
        }
        elseif ($key -eq 'exclude') {
            $excludeRules = $Configuration[$key]
        }
        else {
            $dimensions[$key] = $Configuration[$key]
        }
    }

    # Check for empty dimensions
    if ($dimensions.Count -eq 0) {
        return @{
            valid = $false
            error = "No matrix dimensions found (empty configuration after removing include/exclude)"
            include = @()
        }
    }

    # Generate cartesian product
    $matrixCombinations = Get-CartesianProduct -Dimensions $dimensions

    # Validate size
    if ($matrixCombinations.Count -gt $MaxMatrixSize) {
        return @{
            valid = $false
            error = "Matrix size ($($matrixCombinations.Count)) exceeds maximum ($MaxMatrixSize)"
            include = @()
        }
    }

    # Apply exclude rules
    $filtered = @()
    foreach ($combination in $matrixCombinations) {
        $excluded = $false
        foreach ($excludeRule in $excludeRules) {
            if (Test-CombinationMatches -Combination $combination -Rule $excludeRule) {
                $excluded = $true
                break
            }
        }
        if (-not $excluded) {
            $filtered += $combination
        }
    }

    # Add include rules
    $final = $filtered + $includeRules

    # Build result
    $result = @{
        include = $final
        valid   = $true
    }

    if ($MaxParallel -gt 0) {
        $result.'max-parallel' = $MaxParallel
    }

    if ($FailFast) {
        $result.'fail-fast' = $true
    }

    return $result
}

function Get-CartesianProduct {
    <#
    .SYNOPSIS
    Generates cartesian product of all dimension values.

    .PARAMETER Dimensions
    Hashtable where each value is an array of options for that dimension.
    #>

    param(
        [hashtable]$Dimensions
    )

    $keys = @($Dimensions.Keys)
    if ($keys.Count -eq 0) {
        return @()
    }

    # Start with the first dimension
    $results = @()
    $firstKey = $keys[0]
    foreach ($value in $Dimensions[$firstKey]) {
        $results += @{ $firstKey = $value }
    }

    # Add remaining dimensions
    for ($i = 1; $i -lt $keys.Count; $i++) {
        $key = $keys[$i]
        $newResults = @()
        foreach ($existing in $results) {
            foreach ($value in $Dimensions[$key]) {
                $newCombination = $existing.Clone()
                $newCombination[$key] = $value
                $newResults += $newCombination
            }
        }
        $results = $newResults
    }

    return $results
}

function Test-CombinationMatches {
    <#
    .SYNOPSIS
    Tests if a combination matches a rule (all specified properties match).

    .PARAMETER Combination
    The combination to test.

    .PARAMETER Rule
    The rule (partial match) to check against.
    #>

    param(
        [hashtable]$Combination,
        [hashtable]$Rule
    )

    foreach ($key in $Rule.Keys) {
        if ($Combination[$key] -ne $Rule[$key]) {
            return $false
        }
    }

    return $true
}

