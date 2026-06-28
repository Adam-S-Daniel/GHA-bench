# MatrixGenerator.psm1
#
# Generates a GitHub Actions strategy.matrix from a declarative configuration.
# Built test-first (see tests/MatrixGenerator.Tests.ps1).

Set-StrictMode -Version Latest

function Get-MatrixCombinations {
    <#
    .SYNOPSIS
        Expands a set of named axes into the full cartesian product.
    .DESCRIPTION
        Given an ordered dictionary of axisName -> array-of-values, returns an
        array of [ordered] hashtables, one per combination. Axis order is
        preserved so output is deterministic (important for reproducible CI).
    .PARAMETER Matrix
        Ordered dictionary / hashtable mapping each axis name to its value list.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Matrix
    )

    # Seed the accumulator with a single empty combination, then fold each axis
    # in turn, multiplying the running set of combinations by that axis' values.
    $combinations = @([ordered]@{})

    foreach ($axis in $Matrix.Keys) {
        $values = @($Matrix[$axis])
        $next = [System.Collections.Generic.List[object]]::new()

        foreach ($combo in $combinations) {
            foreach ($value in $values) {
                # Clone so each branch gets its own independent dictionary.
                $clone = [ordered]@{}
                foreach ($k in $combo.Keys) { $clone[$k] = $combo[$k] }
                $clone[$axis] = $value
                $next.Add($clone)
            }
        }

        $combinations = $next.ToArray()
    }

    return $combinations
}

function Test-CombinationMatchesFilter {
    <#
    .SYNOPSIS
        True when a combination matches every key/value pair of a filter.
    .DESCRIPTION
        A "filter" is a partial assignment (an exclude entry, or the
        original-axis portion of an include entry). The combination matches
        when, for every key in the filter, the combination has that key with an
        equal value. Comparison is done on the string form of the values so
        that JSON-sourced numbers/booleans/strings compare predictably
        (e.g. "18" and 18 are treated as equal, true and "true" as equal).
    .PARAMETER Combination
        The candidate combination (dictionary).
    .PARAMETER Filter
        The partial assignment to test against (dictionary).
    .PARAMETER Keys
        Optional subset of the filter's keys to consider. When omitted, all
        filter keys are used.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Combination,
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Filter,
        [string[]] $Keys
    )

    $keysToCheck = if ($PSBoundParameters.ContainsKey('Keys')) { $Keys } else { @($Filter.Keys) }

    foreach ($key in $keysToCheck) {
        # A missing key on either side means "no match".
        if (-not $Combination.Contains($key)) { return $false }
        if ("$($Combination[$key])" -ne "$($Filter[$key])") { return $false }
    }

    return $true
}

function Remove-ExcludedCombinations {
    <#
    .SYNOPSIS
        Drops combinations that match any GitHub Actions "exclude" entry.
    .DESCRIPTION
        Mirrors GitHub semantics: a combination is removed if it is a partial
        match for *any* exclude entry (i.e. every key in that exclude entry
        matches the combination).
    .PARAMETER Combinations
        The expanded combinations to filter.
    .PARAMETER Exclude
        Array of exclude entries (each a dictionary).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Combinations,
        [AllowNull()] [object[]] $Exclude
    )

    if (-not $Exclude) { return $Combinations }

    $kept = [System.Collections.Generic.List[object]]::new()
    foreach ($combo in $Combinations) {
        $excluded = $false
        foreach ($rule in $Exclude) {
            if (Test-CombinationMatchesFilter -Combination $combo -Filter $rule) {
                $excluded = $true
                break
            }
        }
        if (-not $excluded) { $kept.Add($combo) }
    }

    return $kept.ToArray()
}

function Add-IncludedCombinations {
    <#
    .SYNOPSIS
        Applies GitHub Actions "include" entries to a set of combinations.
    .DESCRIPTION
        Implements GitHub's include algorithm:
          1. For each include entry, attempt to merge it into the existing
             *base* combinations. It merges into a combination when all of the
             include's keys that are original matrix axes already match that
             combination. The merge only writes the include's non-axis keys
             (axis values are never overwritten); non-axis keys may overwrite
             values added by earlier includes.
          2. If an include entry merges into no combination, it is appended as
             a brand-new combination.
        Later include entries never merge into combinations created by earlier
        include entries (only the original base set is a merge target), matching
        GitHub's observed behaviour.
    .PARAMETER Combinations
        The base combinations (after exclude has been applied).
    .PARAMETER Include
        Array of include entries (each a dictionary).
    .PARAMETER OriginalKeys
        The names of the original matrix axes (used to decide which keys may not
        be overwritten / must match for a merge).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Combinations,
        [AllowNull()] [object[]] $Include,
        [AllowNull()] [string[]] $OriginalKeys
    )

    if (-not $Include) { return $Combinations }
    $originalSet = @($OriginalKeys)

    # Work on clones so callers' input is never mutated.
    $result = [System.Collections.Generic.List[object]]::new()
    foreach ($combo in $Combinations) {
        $clone = [ordered]@{}
        foreach ($k in $combo.Keys) { $clone[$k] = $combo[$k] }
        $result.Add($clone)
    }
    # Index of base combinations only; appended (new) combos are not merge targets.
    $mergeTargetCount = $result.Count

    foreach ($entry in $Include) {
        # The axis keys present in this include constrain which base combos it
        # can merge into.
        $axisKeysInEntry = @($entry.Keys | Where-Object { $originalSet -contains $_ })

        $mergedSomewhere = $false
        for ($i = 0; $i -lt $mergeTargetCount; $i++) {
            $combo = $result[$i]

            # Mergeable when every axis key in the include matches this combo.
            $matches = Test-CombinationMatchesFilter -Combination $combo -Filter $entry -Keys $axisKeysInEntry
            if (-not $matches) { continue }

            $mergedSomewhere = $true
            # Add/overwrite only the non-axis keys; axis values stay intact.
            foreach ($key in $entry.Keys) {
                if ($originalSet -contains $key) { continue }
                $combo[$key] = $entry[$key]
            }
        }

        if (-not $mergedSomewhere) {
            # Could not merge anywhere -> becomes its own combination.
            $new = [ordered]@{}
            foreach ($k in $entry.Keys) { $new[$k] = $entry[$k] }
            $result.Add($new)
        }
    }

    return $result.ToArray()
}

function ConvertTo-OrderedDict {
    <#
    .SYNOPSIS
        Recursively normalises arbitrary input into ordered hashtables / arrays.
    .DESCRIPTION
        ConvertFrom-Json yields PSCustomObjects; tests pass [ordered] hashtables.
        Normalising both into a single representation (ordered dictionaries with
        plain arrays) lets the rest of the module ignore where the config came
        from. Strings and scalars pass through untouched.
    #>
    param([AllowNull()] [object] $InputObject)

    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [string]) { return $InputObject }

    if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
        $dict = [ordered]@{}
        foreach ($prop in $InputObject.PSObject.Properties) {
            $dict[$prop.Name] = ConvertTo-OrderedDict $prop.Value
        }
        return $dict
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $dict = [ordered]@{}
        foreach ($key in $InputObject.Keys) {
            $dict[$key] = ConvertTo-OrderedDict $InputObject[$key]
        }
        return $dict
    }

    if ($InputObject -is [System.Collections.IEnumerable]) {
        $list = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $InputObject) { $list.Add((ConvertTo-OrderedDict $item)) }
        return , $list.ToArray()
    }

    return $InputObject
}

function Get-ConfigValue {
    <#
    .SYNOPSIS
        Reads a config value by trying several alias keys, with a default.
    .DESCRIPTION
        Lets the config use either camelCase (maxParallel) or the kebab-case
        spelling GitHub uses in YAML (max-parallel).
    #>
    param(
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Config,
        [Parameter(Mandatory)] [string[]] $Names,
        [object] $Default
    )
    foreach ($name in $Names) {
        if ($Config.Contains($name)) { return $Config[$name] }
    }
    return $Default
}

function ConvertTo-PositiveInt {
    # Parses a value as a positive integer or throws a labelled error.
    param([object] $Value, [string] $Label)
    $parsed = 0
    if (-not [int]::TryParse("$Value", [ref] $parsed) -or $parsed -le 0) {
        throw "Configuration '$Label' must be a positive integer (got '$Value')."
    }
    return $parsed
}

function New-BuildMatrix {
    <#
    .SYNOPSIS
        Builds a complete GitHub Actions strategy matrix from a configuration.
    .DESCRIPTION
        Orchestrates axis expansion, exclude filtering and include merging, then
        attaches the strategy options (max-parallel, fail-fast) and validates the
        final size. Returns an ordered object ready to serialise to JSON:

            {
              "matrix":      { "include": [ <one object per job> ] },
              "max-parallel": <int|null>,
              "fail-fast":    <bool>,
              "count":        <int>,
              "max-size":     <int>
            }

        Using matrix.include (a fully-expanded job list) is the canonical pattern
        for dynamically-generated matrices consumed via fromJSON() in a workflow.
    .PARAMETER Config
        The configuration (an [ordered] hashtable or a PSCustomObject parsed from
        JSON). See README / fixtures for the schema.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [object] $Config)

    $cfg = ConvertTo-OrderedDict $Config
    if (-not ($cfg -is [System.Collections.IDictionary])) {
        throw 'Configuration must be a JSON object mapping settings to values.'
    }

    if (-not $cfg.Contains('matrix')) {
        throw "Configuration is missing the required 'matrix' section."
    }
    $matrix = $cfg['matrix']
    if (-not ($matrix -is [System.Collections.IDictionary])) {
        throw "Configuration 'matrix' must be an object mapping axis names to value lists."
    }

    # Split the matrix section into axes vs. the special include/exclude keys.
    $axes = [ordered]@{}
    $include = $null
    $exclude = $null
    foreach ($key in $matrix.Keys) {
        if     ($key -eq 'include') { $include = @($matrix[$key]) }
        elseif ($key -eq 'exclude') { $exclude = @($matrix[$key]) }
        else                        { $axes[$key] = $matrix[$key] }
    }

    # Every declared axis must offer at least one value.
    foreach ($axisName in @($axes.Keys)) {
        if (@($axes[$axisName]).Count -eq 0) {
            throw "Matrix axis '$axisName' has an empty value list; every axis needs at least one value."
        }
    }

    # Strategy options (accept camelCase or kebab-case spellings).
    $maxParallel = Get-ConfigValue -Config $cfg -Names @('maxParallel', 'max-parallel') -Default $null
    $failFast    = Get-ConfigValue -Config $cfg -Names @('failFast', 'fail-fast') -Default $true
    $maxSizeRaw  = Get-ConfigValue -Config $cfg -Names @('maxSize', 'max-size') -Default 256

    $maxSize = ConvertTo-PositiveInt -Value $maxSizeRaw -Label 'max-size'
    if ($null -ne $maxParallel) {
        $maxParallel = ConvertTo-PositiveInt -Value $maxParallel -Label 'max-parallel'
    }
    $failFast = ConvertTo-StrategyBool -Value $failFast -Label 'fail-fast'

    # Expand -> exclude -> include.
    $axisKeys = @($axes.Keys)
    # NB: assign the empty array directly (an `if { @() }` expression would emit
    # nothing and leave $base $null).
    $base = @()
    if ($axisKeys.Count -gt 0) { $base = @(Get-MatrixCombinations -Matrix $axes) }
    $afterExclude = @(Remove-ExcludedCombinations -Combinations $base -Exclude $exclude)
    $final = @(Add-IncludedCombinations -Combinations $afterExclude -Include $include -OriginalKeys $axisKeys)

    $count = $final.Count
    if ($count -eq 0) {
        throw 'The configuration produced no combinations; check your matrix axes and include/exclude rules.'
    }
    if ($count -gt $maxSize) {
        throw ("Generated matrix exceeds the maximum allowed size. The configuration produces " +
               "$count combinations but 'max-size' is $maxSize. Add exclude rules, reduce axes, " +
               "or raise 'max-size'.")
    }

    return [ordered]@{
        matrix         = [ordered]@{ include = $final }
        'max-parallel' = $maxParallel
        'fail-fast'    = $failFast
        count          = $count
        'max-size'     = $maxSize
    }
}

function ConvertTo-StrategyBool {
    # Coerces a config value to a strict boolean (JSON true/false, or strings).
    param([object] $Value, [string] $Label)
    if ($Value -is [bool]) { return $Value }
    switch ("$Value".Trim().ToLowerInvariant()) {
        'true'  { return $true }
        'false' { return $false }
        '1'     { return $true }
        '0'     { return $false }
        default { throw "Configuration '$Label' must be a boolean (got '$Value')." }
    }
}

function ConvertTo-BuildMatrixJson {
    <#
    .SYNOPSIS
        Serialises the generated build matrix to a JSON string.
    .DESCRIPTION
        Thin wrapper over New-BuildMatrix that produces deterministic JSON. The
        include list is always serialised as a JSON array, even when it holds a
        single job, so GitHub Actions' fromJSON() sees a list of jobs.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $Config,
        [int] $Depth = 16
    )
    $result = New-BuildMatrix -Config $Config
    return ($result | ConvertTo-Json -Depth $Depth)
}

Export-ModuleMember -Function Get-MatrixCombinations, Test-CombinationMatchesFilter, `
    Remove-ExcludedCombinations, Add-IncludedCombinations, New-BuildMatrix, ConvertTo-BuildMatrixJson
