#
# MatrixGenerator.psm1
#
# Generates a GitHub Actions `strategy.matrix` from a declarative configuration.
#
# The configuration mirrors a real GitHub `strategy` block so it is intuitive:
#
#   {
#     "matrix": {
#       "os":   ["ubuntu-latest", "windows-latest"],   # dimension
#       "node": ["18", "20"],                            # dimension
#       "include": [ { ... } ],                          # optional add rules
#       "exclude": [ { ... } ]                           # optional remove rules
#     },
#     "max-parallel": 4,        # optional, passed through to strategy.max-parallel
#     "fail-fast": false,       # optional, defaults to true (GitHub default)
#     "max-size": 256           # optional guard rail; generation fails if exceeded
#   }
#
# The resolved output is shaped for direct consumption via `fromJson`:
#
#   {
#     "matrix": { "include": [ { ...combination... }, ... ] },
#     "size": <int>,
#     "max-parallel": <int|null>,
#     "fail-fast": <bool>
#   }
#
# Using `{ "include": [...] }` as the matrix is the canonical "dynamic matrix"
# idiom: each fully-resolved combination becomes one matrix job.
#

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# Input adapters: accept either a PSCustomObject (the JSON shape) or an
# IDictionary (handy for programmatic callers / tests) and read them uniformly.
# ---------------------------------------------------------------------------

function Get-ObjectKey {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $InputObject)

    if ($null -eq $InputObject) { return @() }
    if ($InputObject -is [System.Collections.IDictionary]) {
        return @($InputObject.Keys)
    }
    # Enumerate properties explicitly rather than via `.PSObject.Properties.Name`
    # so an empty object is strict-mode safe (no member-enumeration on an empty
    # collection).
    $names = [System.Collections.Generic.List[string]]::new()
    foreach ($prop in $InputObject.PSObject.Properties) { $names.Add($prop.Name) }
    return @($names.ToArray())
}

function Get-ObjectValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $InputObject,
        [Parameter(Mandatory)] [string] $Key
    )

    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Key)) { return $InputObject[$Key] }
        return $null
    }
    $prop = $InputObject.PSObject.Properties[$Key]
    if ($prop) { return $prop.Value }
    return $null
}

function Test-ObjectHasKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $InputObject,
        [Parameter(Mandatory)] [string] $Key
    )
    return (@(Get-ObjectKey $InputObject) -contains $Key)
}

# ---------------------------------------------------------------------------
# Dimension discovery + cartesian expansion
# ---------------------------------------------------------------------------

# Dimension keys are every key of the matrix object EXCEPT the reserved
# include/exclude rule lists.
function Get-MatrixDimensionName {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Matrix)

    $reserved = @('include', 'exclude')
    return @(Get-ObjectKey $Matrix | Where-Object { $reserved -notcontains $_ })
}

# Expand the cartesian product of all dimensions.
# The FIRST declared dimension varies slowest, matching GitHub Actions ordering.
# With zero dimensions we return an empty list (NOT a single empty combo) so that
# an include-only matrix yields exactly its include entries.
function Expand-MatrixCombination {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Matrix,
        [string[]] $DimensionName = @()
    )

    if ($DimensionName.Count -eq 0) { return @() }

    # Seed with one empty ordered combo, then fold each dimension in.
    $combos = @([ordered]@{})
    foreach ($name in $DimensionName) {
        $values = @(Get-ObjectValue $Matrix $name)
        if ($values.Count -eq 0) {
            # A dimension with no values collapses the whole product to empty,
            # exactly like an empty array would in GitHub Actions.
            return @()
        }
        $next = [System.Collections.Generic.List[object]]::new()
        foreach ($combo in $combos) {
            foreach ($value in $values) {
                $clone = [ordered]@{}
                foreach ($k in $combo.Keys) { $clone[$k] = $combo[$k] }
                $clone[$name] = $value
                $next.Add($clone)
            }
        }
        $combos = $next.ToArray()
    }
    return @($combos)
}

# ---------------------------------------------------------------------------
# exclude / include rule resolution (GitHub Actions semantics)
# ---------------------------------------------------------------------------

# A combination is excluded when EVERY key:value pair of an exclude rule matches
# it (a partial match is enough to exclude — extra combo keys are ignored).
function Remove-ExcludedCombination {
    [CmdletBinding()]
    param(
        $Combination = @(),
        $ExcludeRule
    )

    $Combination = @($Combination)
    if ($null -eq $ExcludeRule) { return @($Combination) }

    $kept = [System.Collections.Generic.List[object]]::new()
    foreach ($combo in $Combination) {
        $excluded = $false
        foreach ($rule in @($ExcludeRule)) {
            $matchesAll = $true
            foreach ($key in Get-ObjectKey $rule) {
                $ruleVal = Get-ObjectValue $rule $key
                if (-not $combo.Contains($key) -or "$($combo[$key])" -ne "$ruleVal") {
                    $matchesAll = $false
                    break
                }
            }
            if ($matchesAll) { $excluded = $true; break }
        }
        if (-not $excluded) { $kept.Add($combo) }
    }
    return @($kept.ToArray())
}

# Apply include rules using GitHub's documented algorithm:
#   * For each include rule, try to merge it into every ORIGINAL matrix combo.
#     A merge is allowed only when the rule does not overwrite an ORIGINAL matrix
#     value (i.e. for every rule key that is also a dimension, the values match).
#   * Merging adds/overwrites NON-original keys (e.g. keys added by an earlier
#     include rule may be overwritten).
#   * A rule that merges into no combo becomes a brand-new standalone combo.
#     Standalone combos are NOT eligible for later include merges.
function Add-IncludedCombination {
    [CmdletBinding()]
    param(
        $Combination = @(),
        $IncludeRule,
        [string[]] $DimensionName = @()
    )

    $Combination = @($Combination)

    # Work on mutable copies so we can merge in place.
    $base = [System.Collections.Generic.List[object]]::new()
    foreach ($combo in $Combination) {
        $copy = [ordered]@{}
        foreach ($k in $combo.Keys) { $copy[$k] = $combo[$k] }
        $base.Add($copy)
    }

    if ($null -eq $IncludeRule) { return @($base.ToArray()) }

    $appended = [System.Collections.Generic.List[object]]::new()
    foreach ($rule in @($IncludeRule)) {
        $ruleKeys = Get-ObjectKey $rule
        $mergedAny = $false

        foreach ($combo in $base) {
            # Compatible if no rule key that is a dimension would overwrite the
            # combo's original (dimension) value.
            $compatible = $true
            foreach ($key in $ruleKeys) {
                if ($DimensionName -contains $key) {
                    $ruleVal = Get-ObjectValue $rule $key
                    if ("$($combo[$key])" -ne "$ruleVal") { $compatible = $false; break }
                }
            }
            if ($compatible) {
                foreach ($key in $ruleKeys) {
                    $combo[$key] = Get-ObjectValue $rule $key
                }
                $mergedAny = $true
            }
        }

        if (-not $mergedAny) {
            $new = [ordered]@{}
            foreach ($key in $ruleKeys) { $new[$key] = Get-ObjectValue $rule $key }
            $appended.Add($new)
        }
    }

    $result = [System.Collections.Generic.List[object]]::new()
    foreach ($c in $base) { $result.Add($c) }
    foreach ($c in $appended) { $result.Add($c) }
    return @($result.ToArray())
}

# ---------------------------------------------------------------------------
# Public entry point
# ---------------------------------------------------------------------------

function New-BuildMatrix {
    <#
    .SYNOPSIS
        Resolve a declarative matrix configuration into a GitHub Actions matrix.
    .PARAMETER Config
        A PSCustomObject (typically from ConvertFrom-Json) or IDictionary holding
        `matrix`, and optionally `max-parallel`, `fail-fast`, and `max-size`.
    .OUTPUTS
        An ordered hashtable: matrix(.include), size, max-parallel, fail-fast.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Config)

    if ($null -eq $Config) {
        throw 'Configuration is null. Provide a config object with a "matrix" section.'
    }

    $matrix = Get-ObjectValue $Config 'matrix'
    if ($null -eq $matrix) {
        throw 'Configuration is missing the required "matrix" section.'
    }

    $hasInclude = Test-ObjectHasKey $matrix 'include'
    # @(...) keeps this an array even when a single dimension would otherwise be
    # unwrapped to a bare string by PowerShell's output pipeline.
    $dimensionNames = @(Get-MatrixDimensionName $matrix)

    if ($dimensionNames.Count -eq 0 -and -not $hasInclude) {
        throw 'The "matrix" section must define at least one dimension or an "include" list.'
    }

    # 1. cartesian product of the declared dimensions
    $combos = @(Expand-MatrixCombination -Matrix $matrix -DimensionName $dimensionNames)

    # 2. apply exclude rules
    $excludeRule = if (Test-ObjectHasKey $matrix 'exclude') { Get-ObjectValue $matrix 'exclude' } else { $null }
    $combos = @(Remove-ExcludedCombination -Combination $combos -ExcludeRule $excludeRule)

    # 3. apply include rules
    $includeRule = if ($hasInclude) { Get-ObjectValue $matrix 'include' } else { $null }
    $combos = @(Add-IncludedCombination -Combination $combos -IncludeRule $includeRule -DimensionName $dimensionNames)

    $size = $combos.Count

    # 4. validate against the optional maximum size guard rail
    if (Test-ObjectHasKey $Config 'max-size') {
        $maxSize = [int](Get-ObjectValue $Config 'max-size')
        if ($size -gt $maxSize) {
            throw "Generated matrix has $size combinations, which exceeds the configured max-size of $maxSize. Reduce dimensions/values or raise max-size."
        }
    }

    if ($size -eq 0) {
        throw 'The resolved matrix is empty. Check your dimensions and exclude rules.'
    }

    # 5. resolve strategy knobs
    $maxParallel = $null
    if (Test-ObjectHasKey $Config 'max-parallel') {
        $maxParallel = [int](Get-ObjectValue $Config 'max-parallel')
        if ($maxParallel -lt 1) {
            throw "max-parallel must be a positive integer, got '$maxParallel'."
        }
    }

    $failFast = $true  # GitHub Actions default
    if (Test-ObjectHasKey $Config 'fail-fast') {
        $failFast = [bool](Get-ObjectValue $Config 'fail-fast')
    }

    return [ordered]@{
        matrix        = [ordered]@{ include = @($combos) }
        size          = $size
        'max-parallel' = $maxParallel
        'fail-fast'   = $failFast
    }
}

# Serialize a resolved matrix to compact JSON suitable for fromJson().
function ConvertTo-MatrixJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)] $Matrix,
        [int] $Depth = 12,
        [switch] $Compress
    )
    process {
        # ConvertTo-Json renders a single-element array as a bare object; force a
        # JSON array for matrix.include so fromJson() always sees a list.
        return ($Matrix | ConvertTo-Json -Depth $Depth -Compress:$Compress)
    }
}

Export-ModuleMember -Function `
    New-BuildMatrix, ConvertTo-MatrixJson, `
    Get-MatrixDimensionName, Expand-MatrixCombination, `
    Remove-ExcludedCombination, Add-IncludedCombination, `
    Get-ObjectKey, Get-ObjectValue, Test-ObjectHasKey
