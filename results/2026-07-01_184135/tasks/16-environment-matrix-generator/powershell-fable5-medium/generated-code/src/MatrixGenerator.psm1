# MatrixGenerator.psm1
#
# Core logic for generating a GitHub Actions strategy.matrix from a
# declarative configuration (OS options, language versions, feature flags,
# include/exclude rules, max-parallel and fail-fast settings).
#
# Built test-first with Pester (see tests/MatrixGenerator.Tests.ps1).

function Expand-MatrixCombination {
    <#
    .SYNOPSIS
        Expands a set of named dimensions into the full cartesian product.
    .DESCRIPTION
        Given an ordered dictionary of dimension-name -> value-list, returns
        one ordered hashtable per combination. Order is deterministic
        row-major: the first dimension varies slowest, the last fastest —
        this makes the output stable and testable against exact values.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.Specialized.OrderedDictionary]$Dimensions
    )

    $combos = [System.Collections.Generic.List[object]]::new()
    $combos.Add([ordered]@{})

    foreach ($name in $Dimensions.Keys) {
        $values = @($Dimensions[$name])
        $next = [System.Collections.Generic.List[object]]::new()
        foreach ($combo in $combos) {
            foreach ($value in $values) {
                $expanded = [ordered]@{}
                foreach ($key in $combo.Keys) { $expanded[$key] = $combo[$key] }
                $expanded[$name] = $value
                $next.Add($expanded)
            }
        }
        $combos = $next
    }

    return ,$combos
}

function ConvertTo-OrderedHashtable {
    # Normalizes a PSCustomObject (as produced by ConvertFrom-Json) into an
    # ordered hashtable so we can iterate keys deterministically.
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$InputObject)

    if ($InputObject -is [System.Collections.IDictionary]) {
        $result = [ordered]@{}
        foreach ($key in $InputObject.Keys) { $result[$key] = $InputObject[$key] }
        return $result
    }
    $result = [ordered]@{}
    foreach ($prop in $InputObject.PSObject.Properties) { $result[$prop.Name] = $prop.Value }
    return $result
}

function Test-CombinationMatch {
    <#
    .SYNOPSIS
        Tests whether a combination matches a rule using partial-match
        semantics (like GitHub Actions exclude): every key in the rule must
        exist in the combination with an equal value; keys not named by the
        rule are ignored.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Combination,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Rule
    )

    foreach ($key in $Rule.Keys) {
        if (-not $Combination.Contains($key)) { return $false }
        if ("$($Combination[$key])" -ne "$($Rule[$key])") { return $false }
    }
    return $true
}

function New-BuildMatrix {
    <#
    .SYNOPSIS
        Builds a GitHub Actions strategy block from a matrix configuration.
    .DESCRIPTION
        Config schema (typically parsed from JSON with ConvertFrom-Json):
          dimensions  - map of dimension name -> list of values (required)
          exclude     - list of partial-match rules removing combinations
          include     - list of extra combinations appended verbatim
          failFast    - bool, default true  -> strategy fail-fast
          maxParallel - int, optional       -> strategy max-parallel
          maxSize     - int, optional       -> hard cap on final combo count

        Returns an ordered hashtable shaped like a strategy block:
          @{ 'fail-fast' = ...; 'max-parallel' = ...; matrix = @{ include = @(...) } }
        The full cross product is expanded into matrix.include so the output
        is directly usable via fromJSON() in a workflow.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Config)

    $cfg = ConvertTo-OrderedHashtable $Config

    # --- Validate dimensions -------------------------------------------------
    if (-not $cfg.Contains('dimensions') -or $null -eq $cfg['dimensions']) {
        throw 'Invalid configuration: it must define at least one dimension under "dimensions".'
    }
    $dimensions = ConvertTo-OrderedHashtable $cfg['dimensions']
    if ($dimensions.Count -eq 0) {
        throw 'Invalid configuration: it must define at least one dimension under "dimensions".'
    }
    foreach ($name in $dimensions.Keys) {
        if (@($dimensions[$name]).Count -eq 0) {
            throw "Invalid configuration: Dimension '$name' has no values."
        }
    }

    # --- Expand and apply exclude rules (partial match) ----------------------
    $combos = Expand-MatrixCombination -Dimensions $dimensions

    $excludeRules = @($cfg['exclude']) | Where-Object { $null -ne $_ } |
        ForEach-Object { ConvertTo-OrderedHashtable $_ }
    if ($excludeRules.Count -gt 0) {
        $combos = @($combos | Where-Object {
            $combo = $_
            -not ($excludeRules | Where-Object { Test-CombinationMatch -Combination $combo -Rule $_ } | Select-Object -First 1)
        })
    }

    # --- Append include rules as extra combinations --------------------------
    $includeRules = @($cfg['include']) | Where-Object { $null -ne $_ } |
        ForEach-Object { ConvertTo-OrderedHashtable $_ }
    $final = @($combos) + @($includeRules)

    # --- Enforce the maximum matrix size --------------------------------------
    if ($cfg.Contains('maxSize') -and $null -ne $cfg['maxSize']) {
        $maxSize = [int]$cfg['maxSize']
        if ($maxSize -le 0) {
            throw "Invalid configuration: maxSize must be a positive integer, got $maxSize."
        }
        if ($final.Count -gt $maxSize) {
            throw "Matrix size $($final.Count) exceeds maximum allowed size $maxSize. Reduce dimensions or add exclude rules."
        }
    }

    # --- Assemble the strategy block ------------------------------------------
    $strategy = [ordered]@{}
    $failFast = $true
    if ($cfg.Contains('failFast') -and $null -ne $cfg['failFast']) { $failFast = [bool]$cfg['failFast'] }
    $strategy['fail-fast'] = $failFast
    if ($cfg.Contains('maxParallel') -and $null -ne $cfg['maxParallel']) {
        $strategy['max-parallel'] = [int]$cfg['maxParallel']
    }
    $strategy['matrix'] = [ordered]@{ include = @($final) }

    return $strategy
}

function ConvertTo-MatrixJson {
    <#
    .SYNOPSIS
        Serializes a strategy block to compact single-line JSON, suitable for
        a GitHub Actions step output consumed with fromJSON().
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Matrix)

    # Ordered hashtables serialize keys in insertion order, so the output is
    # deterministic and can be asserted against exact strings in tests.
    return $Matrix | ConvertTo-Json -Depth 10 -Compress
}

Export-ModuleMember -Function Expand-MatrixCombination, Test-CombinationMatch, New-BuildMatrix, ConvertTo-MatrixJson
