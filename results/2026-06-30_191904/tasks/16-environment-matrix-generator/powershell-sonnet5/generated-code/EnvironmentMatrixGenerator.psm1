# EnvironmentMatrixGenerator.psm1
#
# Generates a GitHub Actions `strategy` object (fail-fast / max-parallel / matrix)
# from a JSON configuration describing build dimensions (os, language version,
# feature flags, ...), include/exclude rules, and matrix-size limits.
#
# Design: rather than emitting the dimension keys + separate include/exclude
# arrays (and relying on the caller/GitHub to re-expand them), this module
# fully expands the cartesian product itself, applies exclude/include rules
# using the same semantics GitHub Actions documents for its own matrix
# expansion, and emits the final job list as `matrix.include`. That keeps the
# output directly usable as `strategy: ${{ fromJson(...) }}` while making the
# expansion logic (the part actually worth testing) explicit and inspectable.

# Safety ceiling for the *raw* cartesian product (before exclude/include are
# applied). This guards against pathological configs (e.g. many dimensions
# with many values) blowing up memory before we ever get to the user-facing
# `max-size` validation.
$script:MaxRawCombinations = 100000

function Get-MatrixCombination {
    <#
    .SYNOPSIS
        Computes the cartesian product of a set of named dimensions.
    .DESCRIPTION
        Given a PSCustomObject where each property is a dimension name mapped
        to an array of values (e.g. { os: [...], node: [...] }), returns an
        array of PSCustomObjects, one per combination. Dimensions are varied
        with the first-declared dimension changing slowest and the
        last-declared dimension changing fastest (matches the intuitive
        reading of nested loops in declaration order).
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [psobject]$Dimensions
    )

    $properties = @($Dimensions.PSObject.Properties | Where-Object { $_.MemberType -eq 'NoteProperty' })
    if ($properties.Count -eq 0) {
        throw "Matrix must define at least one dimension (e.g. 'os', 'version')."
    }

    # Validate every dimension up front and compute the raw product size
    # before allocating anything, so pathological configs fail fast.
    $rawSize = 1
    foreach ($prop in $properties) {
        $values = @($prop.Value)
        if ($values.Count -eq 0) {
            throw "Dimension '$($prop.Name)' must contain at least one value."
        }
        $rawSize *= $values.Count
    }
    if ($rawSize -gt $script:MaxRawCombinations) {
        throw "The matrix dimensions would generate $rawSize combinations before filtering, exceeding the safety ceiling of $($script:MaxRawCombinations). Reduce the number of dimensions or values."
    }

    $combinations = [object[]]@([pscustomobject]@{})
    foreach ($prop in $properties) {
        $values = @($prop.Value)
        $next = [System.Collections.Generic.List[object]]::new()
        foreach ($combo in $combinations) {
            foreach ($value in $values) {
                $clone = [ordered]@{}
                foreach ($p in $combo.PSObject.Properties) { $clone[$p.Name] = $p.Value }
                $clone[$prop.Name] = $value
                $next.Add([pscustomobject]$clone)
            }
        }
        $combinations = $next.ToArray()
    }

    return , $combinations
}

function Test-ExcludeMatch {
    <#
    .SYNOPSIS
        Tests whether a single combination matches a single exclude rule.
    .DESCRIPTION
        An exclude rule matches a combination when every key/value pair in
        the rule equals the combination's value for that key (a partial-key
        subset match, mirroring GitHub Actions' own exclude semantics: you
        don't have to specify every dimension to exclude a group of jobs).
        Values are compared as strings so that JSON numbers/strings from the
        combination and the rule compare equal regardless of exact .NET type.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [psobject]$Combination,

        [Parameter(Mandatory)]
        [psobject]$ExcludeRule,

        [Parameter(Mandatory)]
        [string[]]$DimensionKeys
    )

    foreach ($prop in $ExcludeRule.PSObject.Properties) {
        if ($DimensionKeys -notcontains $prop.Name) {
            throw "Exclude rule references unknown dimension '$($prop.Name)'. Valid dimensions: $($DimensionKeys -join ', ')"
        }
        if ("$($Combination.$($prop.Name))" -ne "$($prop.Value)") {
            return $false
        }
    }
    return $true
}

function Remove-ExcludedCombination {
    <#
    .SYNOPSIS
        Filters out any combination matched by at least one exclude rule.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Combination,

        [AllowEmptyCollection()]
        [object[]]$ExcludeRule = @(),

        [Parameter(Mandatory)]
        [string[]]$DimensionKeys
    )

    if (-not $ExcludeRule -or $ExcludeRule.Count -eq 0) {
        return , @($Combination)
    }

    $kept = foreach ($combo in $Combination) {
        $matched = $false
        foreach ($rule in $ExcludeRule) {
            if (Test-ExcludeMatch -Combination $combo -ExcludeRule $rule -DimensionKeys $DimensionKeys) {
                $matched = $true
                break
            }
        }
        if (-not $matched) { $combo }
    }

    return , @($kept)
}

function Merge-IncludedCombination {
    <#
    .SYNOPSIS
        Applies include rules to a set of combinations.
    .DESCRIPTION
        For each include rule, the "match keys" are whichever of the rule's
        properties are also matrix dimension keys. If at least one match key
        exists and every match key's value equals the corresponding value on
        one or more existing combinations, all of the rule's properties
        (match keys and any extra keys) are merged into every one of those
        combinations - later rules can overwrite values set by earlier
        rules. Otherwise (no match keys, or no combination satisfies all of
        them) the rule is appended as a brand-new, standalone combination
        made up of just its own properties.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Combination,

        [AllowEmptyCollection()]
        [object[]]$IncludeRule = @(),

        [Parameter(Mandatory)]
        [string[]]$DimensionKeys
    )

    $result = [System.Collections.Generic.List[object]]::new()
    $result.AddRange([object[]]$Combination)

    if (-not $IncludeRule -or $IncludeRule.Count -eq 0) {
        return , @($result.ToArray())
    }

    foreach ($rule in $IncludeRule) {
        $ruleProps = @($rule.PSObject.Properties)
        if ($ruleProps.Count -eq 0) {
            throw "Include rule cannot be empty."
        }

        $matchKeys = @($ruleProps.Name | Where-Object { $DimensionKeys -contains $_ })
        $matchedAny = $false

        if ($matchKeys.Count -gt 0) {
            for ($i = 0; $i -lt $result.Count; $i++) {
                $combo = $result[$i]
                $isMatch = $true
                foreach ($key in $matchKeys) {
                    if ("$($combo.$key)" -ne "$($rule.$key)") { $isMatch = $false; break }
                }
                if ($isMatch) {
                    $matchedAny = $true
                    $clone = [ordered]@{}
                    foreach ($p in $combo.PSObject.Properties) { $clone[$p.Name] = $p.Value }
                    foreach ($p in $ruleProps) { $clone[$p.Name] = $p.Value }
                    $result[$i] = [pscustomobject]$clone
                }
            }
        }

        if (-not $matchedAny) {
            $clone = [ordered]@{}
            foreach ($p in $ruleProps) { $clone[$p.Name] = $p.Value }
            $result.Add([pscustomobject]$clone)
        }
    }

    return , @($result.ToArray())
}

function Assert-MatrixSize {
    <#
    .SYNOPSIS
        Validates the final job count against a maximum matrix size.
    .DESCRIPTION
        Throws a descriptive error if $Count exceeds $MaxSize. Defaults to
        256, the maximum number of jobs GitHub Actions allows in a single
        matrix, so callers get a sensible check even without configuring one.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$Count,

        [int]$MaxSize = 256
    )

    if ($Count -gt $MaxSize) {
        throw "Generated matrix has $Count combinations, which exceeds the configured maximum of $MaxSize. Reduce dimensions/includes or raise 'max-size'."
    }
}

function New-EnvironmentMatrix {
    <#
    .SYNOPSIS
        Builds the full GitHub Actions strategy object from a parsed config.
    .DESCRIPTION
        Config shape:
            {
              "matrix":      { "<dimension>": [values...], ... },   (required)
              "exclude":     [ { "<dimension>": value, ... }, ... ], (optional)
              "include":     [ { "<key>": value, ... }, ... ],       (optional)
              "fail-fast":   bool,                                   (optional, default true)
              "max-parallel":int,                                    (optional, no default)
              "max-size":    int                                     (optional, default 256)
            }
        Returns an ordered object shaped like a GitHub Actions `strategy`:
            { "fail-fast": bool, "max-parallel"?: int, "matrix": { "include": [...] } }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Config
    )

    if (-not $Config.PSObject.Properties['matrix']) {
        throw "Config must contain a 'matrix' object defining at least one dimension."
    }

    $dimensions = $Config.matrix
    $dimensionKeys = @($dimensions.PSObject.Properties | Where-Object { $_.MemberType -eq 'NoteProperty' } | ForEach-Object Name)

    $combinations = Get-MatrixCombination -Dimensions $dimensions

    $excludeRules = @()
    if ($Config.PSObject.Properties['exclude']) { $excludeRules = @($Config.exclude) }
    $combinations = Remove-ExcludedCombination -Combination $combinations -ExcludeRule $excludeRules -DimensionKeys $dimensionKeys

    $includeRules = @()
    if ($Config.PSObject.Properties['include']) { $includeRules = @($Config.include) }
    $combinations = Merge-IncludedCombination -Combination $combinations -IncludeRule $includeRules -DimensionKeys $dimensionKeys

    $maxSize = 256
    if ($Config.PSObject.Properties['max-size']) { $maxSize = [int]$Config.'max-size' }
    Assert-MatrixSize -Count $combinations.Count -MaxSize $maxSize

    $failFast = $true
    if ($Config.PSObject.Properties['fail-fast']) { $failFast = [bool]$Config.'fail-fast' }

    $strategy = [ordered]@{
        'fail-fast' = $failFast
    }
    if ($Config.PSObject.Properties['max-parallel']) {
        $strategy['max-parallel'] = [int]$Config.'max-parallel'
    }
    $strategy['matrix'] = [ordered]@{ 'include' = $combinations }

    return [pscustomobject]$strategy
}

function Get-MatrixConfig {
    <#
    .SYNOPSIS
        Reads and parses a JSON matrix configuration file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Config file not found: $Path"
    }

    $raw = Get-Content -LiteralPath $Path -Raw
    try {
        return $raw | ConvertFrom-Json
    }
    catch {
        throw "Failed to parse JSON config at '$Path': $($_.Exception.Message)"
    }
}

function ConvertTo-MatrixJson {
    <#
    .SYNOPSIS
        Generates the matrix strategy for a config and serializes it to JSON.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Config,

        [int]$Depth = 10,

        [switch]$Compress
    )

    $strategy = New-EnvironmentMatrix -Config $Config
    return $strategy | ConvertTo-Json -Depth $Depth -Compress:$Compress
}

Export-ModuleMember -Function Get-MatrixCombination, Test-ExcludeMatch, Remove-ExcludedCombination, Merge-IncludedCombination, Assert-MatrixSize, New-EnvironmentMatrix, Get-MatrixConfig, ConvertTo-MatrixJson
