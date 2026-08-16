function New-GitHubActionsMatrix {
    <#
    .SYNOPSIS
    Generates a GitHub Actions build matrix from a configuration object.

    .DESCRIPTION
    Creates a strategy.matrix configuration suitable for GitHub Actions workflows.
    Supports multi-dimensional matrix generation, include/exclude rules, and validation.

    .PARAMETER Config
    Hashtable containing matrix configuration.
    Required keys: 'os' (array of OS names)
    Optional keys: dimension arrays, 'include', 'exclude', 'max_parallel', 'fail_fast', 'max_matrix_size'

    .EXAMPLE
    $config = @{
        os = @("ubuntu-latest", "windows-latest")
        node_version = @("18.x", "20.x")
    }
    New-GitHubActionsMatrix -Config $config
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config
    )

    # Validate required configuration
    if (-not $Config.ContainsKey('os')) {
        throw "Configuration must contain 'os' array."
    }

    if ($null -eq $Config.os -or $Config.os.Count -eq 0) {
        throw "OS configuration cannot be empty."
    }

    # Extract matrix dimensions and configuration
    $dimensions = @()
    $maxMatrixSize = if ($Config.ContainsKey('max_matrix_size')) { $Config.max_matrix_size } else { [int]::MaxValue }
    $maxParallel = $Config.max_parallel
    $failFast = if ($Config.ContainsKey('fail_fast')) { $Config.fail_fast } else { $null }
    $excludeRules = if ($Config.ContainsKey('exclude')) { $Config.exclude } else { @() }
    $includeRules = if ($Config.ContainsKey('include')) { $Config.include } else { @() }

    # Collect all dimension arrays
    foreach ($key in $Config.Keys) {
        if ($key -notIn @('exclude', 'include', 'max_parallel', 'fail_fast', 'max_matrix_size')) {
            if ($Config[$key] -is [array]) {
                $dimensions += @{
                    Name   = $key
                    Values = $Config[$key]
                }
            }
        }
    }

    # Generate cartesian product of all dimensions
    $include = @()
    if ($dimensions.Count -gt 0) {
        $combinations = @(Get-CartesianProduct -Dimensions $dimensions)
        foreach ($combo in $combinations) {
            # Check if this combination should be excluded
            if (-not (Test-ExcludeRule -Combination $combo -ExcludeRules $excludeRules)) {
                $include += $combo
            }
        }
    }

    # Validate matrix size
    if ($include.Count -gt $maxMatrixSize) {
        throw "Matrix size ($($include.Count)) exceeds maximum allowed size ($maxMatrixSize)."
    }

    # Add include rules (convert hashtables to PSCustomObjects)
    foreach ($rule in $includeRules) {
        if ($rule -is [hashtable]) {
            $obj = [PSCustomObject]$rule
            $include += $obj
        }
        else {
            $include += $rule
        }
    }

    # Build the matrix object
    $matrix = @{
        include = $include
    }

    # Add optional configurations
    if ($null -ne $maxParallel) {
        $matrix."max-parallel" = $maxParallel
    }

    if ($null -ne $failFast) {
        $matrix."fail-fast" = $failFast
    }

    return $matrix
}

function Get-CartesianProduct {
    <#
    .SYNOPSIS
    Generates the cartesian product of multiple dimension arrays.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Dimensions
    )

    if ($Dimensions.Count -eq 0) {
        return
    }

    if ($Dimensions.Count -eq 1) {
        # Base case: single dimension
        $dim = $Dimensions[0]
        foreach ($value in $dim.Values) {
            [PSCustomObject]@{
                $dim.Name = $value
            }
        }
        return
    }

    # Recursive case: combine first dimension with cartesian product of rest
    $firstDim = $Dimensions[0]
    $restDims = $Dimensions[1..($Dimensions.Count - 1)]
    $restProducts = @(Get-CartesianProduct -Dimensions $restDims)

    foreach ($value in $firstDim.Values) {
        if ($restProducts.Count -eq 0) {
            [PSCustomObject]@{
                $firstDim.Name = $value
            }
        }
        else {
            foreach ($restProduct in $restProducts) {
                $obj = $restProduct | Select-Object *
                $obj | Add-Member -NotePropertyName $firstDim.Name -NotePropertyValue $value
                $obj
            }
        }
    }
}

function Test-ExcludeRule {
    <#
    .SYNOPSIS
    Tests if a combination matches any exclude rule.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Combination,

        [Parameter(Mandatory = $false)]
        [array]$ExcludeRules = @()
    )

    if ($ExcludeRules.Count -eq 0) {
        return $false
    }

    foreach ($rule in $ExcludeRules) {
        $matches = $true

        foreach ($key in $rule.Keys) {
            $combValue = $Combination.PSObject.Properties[$key].Value
            if ($combValue -ne $rule[$key]) {
                $matches = $false
                break
            }
        }

        if ($matches) {
            return $true
        }
    }

    return $false
}
