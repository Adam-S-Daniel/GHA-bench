<#
    MatrixGenerator.psm1

    Generates a GitHub Actions build matrix from a configuration describing
    OS options, language versions, and arbitrary feature-flag dimensions.
    Supports include/exclude rules, max-parallel, fail-fast, and a maximum
    matrix size guard.
#>

$script:ReservedKeys = @('include', 'exclude', 'max_parallel', 'fail_fast', 'max_matrix_size')

# GitHub Actions rejects any generated matrix with more than 256 combinations.
$script:GitHubMaxMatrixSize = 256

function New-EnvironmentMatrix {
    <#
        .SYNOPSIS
        Builds a GitHub Actions strategy.matrix payload from a config hashtable.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config
    )

    # Separate dimension keys (arrays of possible values) from reserved control keys.
    $dimensionKeys = @($Config.Keys | Where-Object { $script:ReservedKeys -notcontains $_ })

    if ($dimensionKeys.Count -eq 0) {
        throw "Invalid matrix configuration: at least one dimension (e.g. 'os', 'language_version') is required."
    }

    foreach ($key in $dimensionKeys) {
        $value = $Config[$key]
        if ($null -eq $value -or -not ($value -is [System.Collections.IEnumerable]) -or ($value -is [string]) -or ($value -is [hashtable])) {
            throw "Invalid matrix configuration: dimension '$key' must be an array of values."
        }
    }

    # Build the cartesian product of all dimensions.
    $combinations = @(@{})
    foreach ($key in $dimensionKeys) {
        $newCombinations = [System.Collections.Generic.List[object]]::new()
        foreach ($combo in $combinations) {
            foreach ($value in $Config[$key]) {
                $newCombo = $combo.Clone()
                $newCombo[$key] = $value
                $newCombinations.Add($newCombo)
            }
        }
        $combinations = $newCombinations
    }

    # Apply exclude rules: drop any combination that matches every key/value
    # pair in an exclude entry (a subset match, same as GitHub Actions).
    if ($Config.ContainsKey('exclude')) {
        foreach ($excludeEntry in $Config['exclude']) {
            $combinations = @($combinations | Where-Object {
                $combo = $_
                -not (Test-EntryMatchesCombo -Entry $excludeEntry -Combo $combo)
            })
        }
    }

    # Apply include rules: extend combinations whose shared keys match the
    # include entry; otherwise add the entry as a brand-new combination.
    if ($Config.ContainsKey('include')) {
        foreach ($includeEntry in $Config['include']) {
            $matchingKeys = @($includeEntry.Keys | Where-Object { $dimensionKeys -contains $_ })
            $matched = @($combinations | Where-Object {
                Test-EntryMatchesCombo -Entry $includeEntry -Combo $_ -OnlyKeys $matchingKeys
            })

            if ($matched.Count -gt 0) {
                foreach ($combo in $matched) {
                    foreach ($key in $includeEntry.Keys) {
                        $combo[$key] = $includeEntry[$key]
                    }
                }
            }
            else {
                $combinations = @($combinations) + @($includeEntry.Clone())
            }
        }
    }

    # Enforce the maximum matrix size: a caller-supplied limit if given,
    # otherwise GitHub Actions' own hard cap of 256 combinations.
    $maxSize = if ($Config.ContainsKey('max_matrix_size')) { [int]$Config['max_matrix_size'] } else { $script:GitHubMaxMatrixSize }
    if ($combinations.Count -gt $maxSize) {
        throw "Generated matrix size ($($combinations.Count)) exceeds the maximum allowed ($maxSize)."
    }

    $result = [ordered]@{
        matrix = @{
            include = $combinations
        }
    }

    if ($Config.ContainsKey('max_parallel')) {
        $maxParallel = [int]$Config['max_parallel']
        if ($maxParallel -lt 1) {
            throw "Invalid matrix configuration: max_parallel must be at least 1."
        }
        $result['max-parallel'] = $maxParallel
    }

    $result['fail-fast'] = if ($Config.ContainsKey('fail_fast')) { [bool]$Config['fail_fast'] } else { $true }

    return $result
}

function Test-EntryMatchesCombo {
    <#
        .SYNOPSIS
        Checks whether an include/exclude entry's key/value pairs are all
        present and equal on a given matrix combination.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Entry,

        [Parameter(Mandatory = $true)]
        [hashtable]$Combo,

        [string[]]$OnlyKeys
    )

    $keysToCheck = if ($PSBoundParameters.ContainsKey('OnlyKeys')) { $OnlyKeys } else { @($Entry.Keys) }

    if ($keysToCheck.Count -eq 0) {
        return $false
    }

    foreach ($key in $keysToCheck) {
        if (-not $Combo.ContainsKey($key)) {
            return $false
        }
        if ($Combo[$key] -ne $Entry[$key]) {
            return $false
        }
    }

    return $true
}

Export-ModuleMember -Function New-EnvironmentMatrix
