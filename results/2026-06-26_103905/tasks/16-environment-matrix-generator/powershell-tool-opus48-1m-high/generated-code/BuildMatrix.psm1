# BuildMatrix.psm1
#
# A PowerShell module that turns a strategy-style configuration (OS options,
# language versions, feature flags, plus include/exclude rules) into a fully
# resolved GitHub Actions build matrix and emits it as JSON suitable for
# `strategy.matrix` (consumed via `${{ fromJSON(...) }}`).
#
# The module is intentionally split into small, independently testable
# functions so each could be developed with a red/green TDD cycle.

Set-StrictMode -Version Latest

function Expand-MatrixAxes {
    <#
    .SYNOPSIS
        Expand a set of named axes into the cartesian product of their values.

    .DESCRIPTION
        Given an ordered map of axis-name -> array-of-values, produce one
        ordered hashtable per combination. The first axis varies slowest and
        the last axis varies fastest (standard "odometer" ordering), which
        keeps output deterministic and easy to assert against in tests.

    .PARAMETER Axes
        An [ordered] hashtable. Each key is an axis name; each value is an
        array of the values for that axis.

    .OUTPUTS
        System.Collections.Specialized.OrderedDictionary[] - one entry per
        combination. Returns an empty array when there are no axes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Axes
    )

    # No axes -> no combinations. (An empty matrix is a valid, if useless,
    # input; the caller is responsible for deciding whether that's an error.)
    if ($Axes.Keys.Count -eq 0) {
        return @()
    }

    $axisNames = @($Axes.Keys)

    # Seed the accumulator with a single empty combination, then fold each axis
    # in turn. Folding in axis order with the new axis appended on the inside
    # of the loop yields first-axis-slowest ordering.
    $combinations = @([ordered]@{})

    foreach ($name in $axisNames) {
        $values = @($Axes[$name])
        $next = [System.Collections.ArrayList]::new()

        foreach ($combo in $combinations) {
            foreach ($value in $values) {
                # Clone the partial combination and extend it with this axis.
                $new = [ordered]@{}
                foreach ($k in $combo.Keys) { $new[$k] = $combo[$k] }
                $new[$name] = $value
                [void]$next.Add($new)
            }
        }

        $combinations = $next.ToArray()
    }

    return $combinations
}

function Test-CombinationMatchesRule {
    <#
    .SYNOPSIS
        Return $true when a combination matches every key/value pair in a rule.

    .DESCRIPTION
        A "rule" (used by both exclude and include) is a partial spec: only the
        keys present in the rule are compared. A combination matches when, for
        every key in the rule, the combination contains that key with an equal
        value. Keys present in the combination but absent from the rule are
        ignored. Booleans and strings are compared by value.

    .PARAMETER Combination
        The combination (ordered hashtable) to test.

    .PARAMETER Rule
        The partial spec to match against.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Combination,
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Rule
    )

    foreach ($key in $Rule.Keys) {
        if (-not $Combination.Contains($key)) { return $false }
        # -ne does value comparison that works for strings, ints and booleans.
        if ($Combination[$key] -ne $Rule[$key]) { return $false }
    }
    return $true
}

function Remove-ExcludedCombinations {
    <#
    .SYNOPSIS
        Drop combinations matching any exclude rule.

    .DESCRIPTION
        Mirrors GitHub Actions `matrix.exclude`: a combination is removed if it
        matches any exclude entry. Each exclude entry is a partial spec, so an
        entry with fewer keys removes a whole slice of the matrix.

    .PARAMETER Combinations
        The expanded combinations to filter.

    .PARAMETER Exclude
        An array of exclude rules (ordered hashtables). May be empty/null.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Combinations,
        [AllowNull()] [object[]] $Exclude
    )

    if (-not $Exclude -or $Exclude.Count -eq 0) {
        return $Combinations
    }

    $kept = [System.Collections.ArrayList]::new()
    foreach ($combo in $Combinations) {
        $excluded = $false
        foreach ($rule in $Exclude) {
            if (Test-CombinationMatchesRule -Combination $combo -Rule $rule) {
                $excluded = $true
                break
            }
        }
        if (-not $excluded) { [void]$kept.Add($combo) }
    }

    return $kept.ToArray()
}

function Add-IncludedCombinations {
    <#
    .SYNOPSIS
        Apply GitHub Actions `matrix.include` semantics to a set of combinations.

    .DESCRIPTION
        Faithfully reproduces GitHub's documented include algorithm:

          For each object in the include list, its key/value pairs are added to
          every matrix combination *if* none of the pairs would overwrite an
          original matrix value (a value that came from an axis). When an
          include object can extend at least one combination it is merged into
          all that it matches; values added by earlier include objects MAY be
          overwritten, but axis values never are. If an include object cannot be
          added to any existing combination, it becomes a brand-new combination.

        Whether a pair "overwrites an original matrix value" is decided purely
        by axis-key membership: if an include key is an axis name and its value
        differs from the combination's axis value, the object cannot extend that
        combination.

    .PARAMETER Combinations
        The expanded (and exclude-filtered) combinations.

    .PARAMETER Include
        An array of include objects (ordered hashtables). May be empty/null.

    .PARAMETER AxisNames
        The names of the original matrix axes, used to distinguish axis keys
        (which must not be overwritten) from added keys (which may be).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Combinations,
        [AllowNull()] [object[]] $Include,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $AxisNames
    )

    # Work on mutable clones so we never disturb the caller's objects.
    $result = [System.Collections.ArrayList]::new()
    foreach ($combo in $Combinations) {
        $clone = [ordered]@{}
        foreach ($k in $combo.Keys) { $clone[$k] = $combo[$k] }
        [void]$result.Add($clone)
    }

    if (-not $Include -or $Include.Count -eq 0) {
        return $result.ToArray()
    }

    $axisSet = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]$AxisNames, [System.StringComparer]::OrdinalIgnoreCase)

    foreach ($inc in $Include) {
        $appliedToAny = $false

        foreach ($combo in $result) {
            # The include object can extend this combination unless one of its
            # keys is an axis key whose value disagrees with the combination.
            $canExtend = $true
            foreach ($key in $inc.Keys) {
                if ($axisSet.Contains($key)) {
                    if (-not $combo.Contains($key) -or $combo[$key] -ne $inc[$key]) {
                        $canExtend = $false
                        break
                    }
                }
            }

            if ($canExtend) {
                $appliedToAny = $true
                foreach ($key in $inc.Keys) {
                    # Axis values are guaranteed equal here; added values may be
                    # overwritten by this (later) include object.
                    $combo[$key] = $inc[$key]
                }
            }
        }

        if (-not $appliedToAny) {
            # Could not extend anything -> standalone new combination.
            $new = [ordered]@{}
            foreach ($key in $inc.Keys) { $new[$key] = $inc[$key] }
            [void]$result.Add($new)
        }
    }

    return $result.ToArray()
}

function Assert-MatrixSize {
    <#
    .SYNOPSIS
        Throw if the number of combinations exceeds a maximum.

    .DESCRIPTION
        GitHub Actions itself caps a matrix at 256 jobs; this guard lets a
        configuration impose a stricter ceiling and fail loudly (with a clear
        message) before a CI run is dispatched. The limit is inclusive: a matrix
        whose size equals MaxSize is allowed.

    .PARAMETER Combinations
        The resolved combinations.

    .PARAMETER MaxSize
        The maximum number of combinations permitted (inclusive).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Combinations,
        [Parameter(Mandatory)] [int] $MaxSize
    )

    $size = @($Combinations).Count
    if ($size -gt $MaxSize) {
        throw "Generated matrix has $size combination(s), which exceeds the maximum allowed size of $MaxSize. " +
              'Reduce the number of axis values or add exclude rules.'
    }
}

function ConvertTo-OrderedDict {
    <#
    .SYNOPSIS
        Normalize a PSCustomObject or hashtable into an ordered hashtable.

    .DESCRIPTION
        Configuration may arrive as a hashtable (when built in PowerShell) or as
        a PSCustomObject (when produced by ConvertFrom-Json). Downstream code
        wants a single, predictable shape, so this converts either into an
        [ordered] hashtable, preserving key order. Conversion is shallow: nested
        objects are normalized too, but arrays of scalars are left as-is.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowNull()] $InputObject)

    if ($null -eq $InputObject) { return $null }

    $dict = [ordered]@{}

    if ($InputObject -is [System.Collections.IDictionary]) {
        foreach ($key in $InputObject.Keys) { $dict[[string]$key] = $InputObject[$key] }
    }
    elseif ($InputObject -is [psobject]) {
        foreach ($prop in $InputObject.PSObject.Properties) { $dict[$prop.Name] = $prop.Value }
    }
    else {
        throw "Cannot normalize a value of type [$($InputObject.GetType().FullName)] into a dictionary."
    }

    # Recursively normalize include/exclude entries so callers always see
    # ordered hashtables, never PSCustomObjects.
    foreach ($listKey in @('include', 'exclude')) {
        if ($dict.Contains($listKey) -and $null -ne $dict[$listKey]) {
            $dict[$listKey] = @($dict[$listKey] | ForEach-Object { ConvertTo-OrderedDict -InputObject $_ })
        }
    }

    return $dict
}

function New-BuildMatrix {
    <#
    .SYNOPSIS
        Build a fully resolved GitHub Actions strategy from a configuration.

    .DESCRIPTION
        Orchestrates the full pipeline:
          1. Expand the matrix axes into the cartesian product.
          2. Apply exclude rules.
          3. Apply include rules (GitHub semantics).
          4. Validate the resulting size against an optional max-size.
        Returns an [ordered] hashtable shaped like a GitHub Actions `strategy`:
        a `matrix` containing the resolved combinations under `include`, plus
        optional `fail-fast` and `max-parallel` settings.

        The resolved combinations are emitted under `matrix.include` (with no
        top-level axis keys) so the output can be consumed directly as a
        dynamic matrix via `${{ fromJSON(...) }}`: GitHub runs exactly the
        listed combinations with no further cartesian expansion.

    .PARAMETER Config
        A hashtable or PSCustomObject. Recognized keys:
          matrix       - required; axis-name -> values, plus optional
                         include/exclude lists (GitHub-style).
          fail-fast    - optional bool (default $true).
          max-parallel - optional int (omitted from output when absent).
          max-size     - optional int; throws when exceeded.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowNull()] $Config)

    if ($null -eq $Config) {
        throw 'Configuration is required but was null.'
    }

    $cfg = ConvertTo-OrderedDict -InputObject $Config

    if (-not $cfg.Contains('matrix') -or $null -eq $cfg['matrix']) {
        throw "Configuration is missing the required 'matrix' key."
    }

    $matrix = ConvertTo-OrderedDict -InputObject $cfg['matrix']

    # Separate the axis definitions from the reserved include/exclude keys.
    $reserved = @('include', 'exclude')
    $axes = [ordered]@{}
    foreach ($key in $matrix.Keys) {
        if ($reserved -notcontains $key) {
            $axes[$key] = @($matrix[$key])
        }
    }

    if ($axes.Keys.Count -eq 0) {
        throw 'The matrix must define at least one axis (e.g. os, node-version, or a feature flag).'
    }

    $axisNames = @($axes.Keys)

    $exclude = if ($matrix.Contains('exclude')) { @($matrix['exclude']) } else { @() }
    $include = if ($matrix.Contains('include')) { @($matrix['include']) } else { @() }

    # 1-3: expand, exclude, include.
    $combos = Expand-MatrixAxes -Axes $axes
    $combos = Remove-ExcludedCombinations -Combinations $combos -Exclude $exclude
    $combos = Add-IncludedCombinations -Combinations $combos -Include $include -AxisNames $axisNames

    # 4: size validation (only when a limit is configured).
    if ($cfg.Contains('max-size') -and $null -ne $cfg['max-size']) {
        Assert-MatrixSize -Combinations $combos -MaxSize ([int]$cfg['max-size'])
    }

    # Assemble the strategy object. fail-fast defaults to GitHub's own default
    # of true; max-parallel is only emitted when explicitly configured.
    $strategy = [ordered]@{}
    $strategy['fail-fast'] = if ($cfg.Contains('fail-fast') -and $null -ne $cfg['fail-fast']) {
        [bool]$cfg['fail-fast']
    } else {
        $true
    }
    if ($cfg.Contains('max-parallel') -and $null -ne $cfg['max-parallel']) {
        $strategy['max-parallel'] = [int]$cfg['max-parallel']
    }
    $strategy['matrix'] = [ordered]@{ include = @($combos) }

    return $strategy
}

function ConvertTo-StrategyJson {
    <#
    .SYNOPSIS
        Serialize a strategy object to GitHub-Actions-ready JSON.

    .DESCRIPTION
        Wraps ConvertTo-Json with the settings that matter for a matrix:
          * -Depth high enough for matrix.include[].<keys>.
          * -InputObject (not the pipeline) so a single-element include array is
            NOT unrolled into a bare object - GitHub requires an array.
        Booleans are emitted as JSON true/false because the strategy carries
        real [bool] values, not strings.

    .PARAMETER Strategy
        The strategy object produced by New-BuildMatrix.

    .PARAMETER Compress
        Emit compact single-line JSON (useful for a GitHub step output).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Strategy,
        [switch] $Compress
    )

    return ConvertTo-Json -InputObject $Strategy -Depth 20 -Compress:$Compress
}

Export-ModuleMember -Function Expand-MatrixAxes, Remove-ExcludedCombinations, `
    Test-CombinationMatchesRule, Add-IncludedCombinations, Assert-MatrixSize, `
    ConvertTo-OrderedDict, New-BuildMatrix, ConvertTo-StrategyJson
