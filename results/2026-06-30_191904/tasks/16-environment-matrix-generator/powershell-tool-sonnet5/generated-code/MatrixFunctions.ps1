<#
    Core logic for the GitHub Actions environment matrix generator.

    This file only defines functions -- dot-sourcing it has no side effects,
    which keeps it safe to load from both the CLI script and the Pester
    test suite. All GitHub Actions -related semantics implemented here
    (cartesian expansion, include/exclude merging, fail-fast/max-parallel
    passthrough) intentionally mirror the real strategy.matrix behavior
    documented for GitHub Actions.
#>

# Normalizes a value (string, number, boolean, $null) to a string so that
# exclude/include rule matching works the same regardless of whether a JSON
# author wrote a bare number or a quoted string for something like a version.
function ConvertTo-ComparableString {
    param(
        [Parameter()]
        $Value
    )
    if ($null -eq $Value) { return '' }
    return [string]$Value
}

# Returns the property names of a PSCustomObject as a real (possibly empty)
# list. Deliberately avoids the `$obj.PSObject.Properties.Name` shorthand:
# when an object has zero properties, PowerShell's member-enumeration
# returns $null instead of an empty collection, and wrapping that $null in
# `@()` produces a *one-element* array containing $null rather than an
# empty array -- silently defeating any `-eq 0` emptiness check downstream.
function Get-PropertyNames {
    param(
        [Parameter()]
        $InputObject
    )

    $names = [System.Collections.Generic.List[string]]::new()
    if ($null -ne $InputObject) {
        foreach ($property in $InputObject.PSObject.Properties) {
            $names.Add($property.Name)
        }
    }
    return , $names
}

# Builds the cartesian product of a set of named matrix dimensions.
# $Dimensions is an ordered dictionary: dimension name -> array of values.
# Returns a list of ordered hashtables (one per combination), each preserving
# the dimension key order so JSON output is deterministic.
function Get-MatrixCombinations {
    param(
        [Parameter(Mandatory)]
        [System.Collections.Specialized.OrderedDictionary]$Dimensions
    )

    $combinations = [System.Collections.Generic.List[object]]::new()
    $combinations.Add([ordered]@{})

    foreach ($key in $Dimensions.Keys) {
        $values = @($Dimensions[$key])
        $next = [System.Collections.Generic.List[object]]::new()

        foreach ($combo in $combinations) {
            foreach ($value in $values) {
                $newCombo = [ordered]@{}
                foreach ($existingKey in $combo.Keys) {
                    $newCombo[$existingKey] = $combo[$existingKey]
                }
                $newCombo[$key] = $value
                $next.Add($newCombo)
            }
        }

        $combinations = $next
    }

    # Comma-prefix prevents PowerShell from unrolling the list on return,
    # which would otherwise collapse a single-item result to a scalar.
    return , $combinations
}

# An exclude rule matches a combination when every key named in the rule
# has an equal value in the combination. Keys the rule does not mention are
# ignored (wildcarded), matching GitHub Actions' documented exclude behavior.
function Test-ExcludeMatch {
    param(
        [Parameter(Mandatory)] $Combination,
        [Parameter(Mandatory)] $ExcludeRule
    )

    foreach ($key in (Get-PropertyNames $ExcludeRule)) {
        if (-not $Combination.Contains($key)) { return $false }
        $comboValue = ConvertTo-ComparableString $Combination[$key]
        $ruleValue = ConvertTo-ComparableString $ExcludeRule.$key
        if ($comboValue -ne $ruleValue) { return $false }
    }
    return $true
}

# Removes every combination matched by at least one exclude rule.
function Remove-ExcludedCombinations {
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] $Combinations,
        [AllowEmptyCollection()] $ExcludeRules = @()
    )

    $rules = @($ExcludeRules)
    $result = [System.Collections.Generic.List[object]]::new()

    foreach ($combo in $Combinations) {
        $excluded = $false
        foreach ($rule in $rules) {
            if (Test-ExcludeMatch -Combination $combo -ExcludeRule $rule) {
                $excluded = $true
                break
            }
        }
        if (-not $excluded) { $result.Add($combo) }
    }

    return , $result
}

# An include rule "matches" an existing combination when every one of the
# rule's properties that IS a declared matrix dimension key has an equal
# value in that combination. Properties the rule does not mention are
# wildcarded. A rule with no dimension-key overlap never matches anything.
function Test-IncludeDimensionMatch {
    param(
        [Parameter(Mandatory)] $Combination,
        [Parameter(Mandatory)] $IncludeRule,
        [Parameter(Mandatory)] [string[]]$DimensionKeys
    )

    $ruleKeys = [System.Collections.Generic.List[string]]::new()
    foreach ($propName in (Get-PropertyNames $IncludeRule)) {
        if ($DimensionKeys -contains $propName) { $ruleKeys.Add($propName) }
    }
    if ($ruleKeys.Count -eq 0) { return $false }

    foreach ($key in $ruleKeys) {
        $comboValue = ConvertTo-ComparableString $Combination[$key]
        $ruleValue = ConvertTo-ComparableString $IncludeRule.$key
        if ($comboValue -ne $ruleValue) { return $false }
    }
    return $true
}

# Applies GitHub Actions' include semantics:
#   - if an include rule matches one or more existing combinations (on the
#     dimension keys it specifies), its extra properties are merged into
#     every one of those combinations;
#   - otherwise the rule is appended as a brand-new combination, using
#     exactly the properties it specifies.
function Merge-IncludeRules {
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] $Combinations,
        [AllowEmptyCollection()] $IncludeRules = @(),
        [Parameter(Mandatory)] [string[]]$DimensionKeys
    )

    $result = [System.Collections.Generic.List[object]]::new()
    foreach ($combo in $Combinations) { $result.Add($combo) }

    foreach ($rule in @($IncludeRules)) {
        $matched = $false

        for ($i = 0; $i -lt $result.Count; $i++) {
            if (Test-IncludeDimensionMatch -Combination $result[$i] -IncludeRule $rule -DimensionKeys $DimensionKeys) {
                $matched = $true
                foreach ($propName in (Get-PropertyNames $rule)) {
                    $result[$i][$propName] = $rule.$propName
                }
            }
        }

        if (-not $matched) {
            $newCombo = [ordered]@{}
            foreach ($propName in (Get-PropertyNames $rule)) {
                $newCombo[$propName] = $rule.$propName
            }
            $result.Add($newCombo)
        }
    }

    return , $result
}

# Orchestrates the full pipeline: validate config, expand the cartesian
# matrix, apply exclude/include rules, validate the resulting size, and
# assemble the strategy.matrix-shaped output object.
function New-BuildMatrix {
    param(
        [Parameter(Mandatory)] $Config,
        [Nullable[int]]$MaxMatrixSizeOverride
    )

    if ($null -eq $Config -or -not ($Config.PSObject.Properties.Name -contains 'matrix') -or $null -eq $Config.matrix) {
        throw "Configuration must include a non-empty 'matrix' object defining at least one dimension."
    }

    $dimensionNames = Get-PropertyNames $Config.matrix
    if ($dimensionNames.Count -eq 0) {
        throw "Configuration must include a non-empty 'matrix' object defining at least one dimension."
    }

    $dimensions = [ordered]@{}
    foreach ($name in $dimensionNames) {
        $values = @($Config.matrix.$name)
        if ($values.Count -eq 0) {
            throw "Matrix dimension '$name' must contain at least one value."
        }
        $dimensions[$name] = $values
    }

    $combinations = Get-MatrixCombinations -Dimensions $dimensions

    $excludeRules = @()
    if ($Config.PSObject.Properties.Name -contains 'exclude' -and $Config.exclude) {
        $excludeRules = @($Config.exclude)
    }
    $combinations = Remove-ExcludedCombinations -Combinations $combinations -ExcludeRules $excludeRules

    $includeRules = @()
    if ($Config.PSObject.Properties.Name -contains 'include' -and $Config.include) {
        $includeRules = @($Config.include)
    }
    $combinations = Merge-IncludeRules -Combinations $combinations -IncludeRules $includeRules -DimensionKeys $dimensionNames

    # Effective max matrix size, in increasing priority order:
    #   built-in default (256, GitHub Actions' own hard limit)
    #   < $env:MATRIX_MAX_SIZE < -MaxMatrixSizeOverride param < config's maxMatrixSize.
    $effectiveMax = 256
    if ($env:MATRIX_MAX_SIZE) { $effectiveMax = [int]$env:MATRIX_MAX_SIZE }
    if ($null -ne $MaxMatrixSizeOverride) { $effectiveMax = $MaxMatrixSizeOverride }
    if ($Config.PSObject.Properties.Name -contains 'maxMatrixSize' -and $Config.maxMatrixSize) {
        $effectiveMax = [int]$Config.maxMatrixSize
    }

    if ($combinations.Count -gt $effectiveMax) {
        throw "Generated matrix contains $($combinations.Count) combination(s), exceeding the maximum allowed size of $effectiveMax. Reduce matrix dimensions or add exclude rules."
    }

    $failFast = $true
    if ($Config.PSObject.Properties.Name -contains 'failFast' -and $null -ne $Config.failFast) {
        if ($Config.failFast -isnot [bool]) {
            throw "The 'failFast' setting must be a boolean (true or false)."
        }
        $failFast = $Config.failFast
    }

    $strategy = [ordered]@{
        'fail-fast' = $failFast
        'matrix'    = [ordered]@{
            'include' = $combinations
        }
    }

    if ($Config.PSObject.Properties.Name -contains 'maxParallel' -and $null -ne $Config.maxParallel) {
        $maxParallel = 0
        if (-not [int]::TryParse([string]$Config.maxParallel, [ref]$maxParallel) -or $maxParallel -le 0) {
            throw "The 'maxParallel' setting must be a positive integer."
        }
        $strategy['max-parallel'] = $maxParallel
    }

    return [ordered]@{ 'strategy' = $strategy }
}
