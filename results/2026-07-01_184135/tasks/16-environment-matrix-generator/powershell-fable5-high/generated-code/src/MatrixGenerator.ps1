<#
.SYNOPSIS
    Environment Matrix Generator - core library.

.DESCRIPTION
    Generates a GitHub Actions strategy.matrix JSON document from a
    configuration describing OS options, language versions, and feature flags.

    Approach:
      1. Expand the configured axes (os / languageVersions / featureFlags)
         into the full cartesian product of combinations.
      2. Apply exclude rules (partial match, GitHub Actions semantics: a
         combination is removed when every key in an exclude rule matches it).
      3. Apply include rules (GitHub-Actions-like semantics: an include whose
         axis keys all match existing combinations merges its extra keys into
         them; otherwise it is appended as a brand-new combination).
      4. Validate the resulting matrix size against a configurable cap
         (default 256, the real GitHub Actions limit).
      5. Assemble the strategy object: fail-fast, max-parallel, and
         matrix.include (emitting the combination list under `include` is the
         standard shape consumed via `matrix: ${{ fromJSON(...) }}`).

    All functions throw terminating errors with meaningful messages on
    invalid input so callers (and CI) fail loudly instead of emitting a
    silently-wrong matrix.
#>

Set-StrictMode -Version Latest

function Expand-MatrixAxes {
    <#
    .SYNOPSIS
        Expands named axes into the cartesian product of their values.
    .PARAMETER Axes
        Ordered dictionary of axisName -> array of values. Order determines
        expansion order: the first axis varies slowest, so output is
        deterministic and reads naturally (grouped by OS, then version, ...).
    .OUTPUTS
        Array of ordered hashtables, one per combination.
    #>
    param(
        [Parameter(Mandatory)]
        [System.Collections.Specialized.OrderedDictionary]$Axes
    )

    # Start from a single empty combination and fold each axis in.
    $combos = [System.Collections.Generic.List[object]]::new()
    $combos.Add([ordered]@{})

    foreach ($axisName in $Axes.Keys) {
        $next = [System.Collections.Generic.List[object]]::new()
        foreach ($combo in $combos) {
            foreach ($value in @($Axes[$axisName])) {
                $expanded = [ordered]@{}
                foreach ($key in $combo.Keys) { $expanded[$key] = $combo[$key] }
                $expanded[$axisName] = $value
                $next.Add($expanded)
            }
        }
        $combos = $next
    }

    # Comma operator prevents PowerShell from unrolling the list.
    return , $combos
}

function Test-CombinationMatch {
    <#
    .SYNOPSIS
        True when every key in Rule exists in Combination with an equal value.
        This is the GitHub Actions "partial match" rule used by exclude.
    #>
    param(
        [Parameter(Mandatory)]$Combination,
        [Parameter(Mandatory)]$Rule
    )

    foreach ($key in $Rule.Keys) {
        if (-not $Combination.Contains($key)) { return $false }
        # Compare as invariant strings so '3.11' (string) matches 3.11 (number).
        if ([string]$Combination[$key] -cne [string]$Rule[$key]) { return $false }
    }
    return $true
}

function Remove-ExcludedCombination {
    <#
    .SYNOPSIS
        Removes every combination matched by at least one exclude rule.
    .DESCRIPTION
        GitHub Actions semantics: an exclude rule may specify any subset of
        keys; a combination is removed when ALL keys in the rule match it.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()]$Combinations,
        [Parameter(Mandatory)][AllowEmptyCollection()][array]$ExcludeRules
    )

    $kept = [System.Collections.Generic.List[object]]::new()
    foreach ($combo in $Combinations) {
        $excluded = $false
        foreach ($rule in $ExcludeRules) {
            if (Test-CombinationMatch -Combination $combo -Rule $rule) {
                $excluded = $true
                break
            }
        }
        if (-not $excluded) { $kept.Add($combo) }
    }
    return , $kept
}

function Add-IncludedCombination {
    <#
    .SYNOPSIS
        Applies include rules to an expanded matrix.
    .DESCRIPTION
        GitHub-Actions-like semantics:
          - Split each include rule's keys into axis keys (keys that are part
            of the original matrix axes) and extra keys.
          - If the rule's axis keys match one or more existing combinations,
            the extra keys are merged into every matching combination
            (original axis values are never overwritten).
          - If nothing matches (e.g. the rule names an axis value that does
            not exist in the matrix), the rule is appended as a brand-new
            combination.
        An include with only extra keys matches - and enriches - every
        combination, exactly like GitHub Actions.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()]$Combinations,
        [Parameter(Mandatory)][AllowEmptyCollection()][array]$IncludeRules,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$AxisNames
    )

    $result = [System.Collections.Generic.List[object]]::new()
    foreach ($combo in $Combinations) { $result.Add($combo) }

    foreach ($rule in $IncludeRules) {
        # Only the rule's axis keys participate in matching.
        $axisPart = [ordered]@{}
        foreach ($key in $rule.Keys) {
            if ($AxisNames -contains $key) { $axisPart[$key] = $rule[$key] }
        }

        $matched = $false
        foreach ($combo in $result) {
            if (Test-CombinationMatch -Combination $combo -Rule $axisPart) {
                $matched = $true
                foreach ($key in $rule.Keys) {
                    # Merge extra keys only; never overwrite an axis value.
                    if (-not $combo.Contains($key)) { $combo[$key] = $rule[$key] }
                }
            }
        }

        if (-not $matched) {
            # No existing combination matched: the include becomes a new one.
            $new = [ordered]@{}
            foreach ($key in $rule.Keys) { $new[$key] = $rule[$key] }
            $result.Add($new)
        }
    }
    return , $result
}

function Test-MatrixSize {
    <#
    .SYNOPSIS
        Throws when the matrix has more combinations than the allowed cap.
    #>
    param(
        [Parameter(Mandatory)][int]$Count,
        [Parameter(Mandatory)][int]$MaxSize
    )

    if ($Count -gt $MaxSize) {
        throw ("Matrix size {0} exceeds the maximum allowed size of {1}. " +
            'Reduce the number of axis values or add exclude rules.') -f $Count, $MaxSize
    }
}

function Get-ConfigProperty {
    <#
    .SYNOPSIS
        Safe property lookup on a ConvertFrom-Json PSCustomObject.
        Returns $null when the property is absent.
    #>
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][string]$Name
    )

    $prop = $Config.PSObject.Properties[$Name]
    if ($null -ne $prop) { return $prop.Value }
    # Emit nothing (AutomationNull) so @(...) around an absent property is an
    # empty array rather than @($null).
    return
}

function ConvertTo-OrderedRule {
    <#
    .SYNOPSIS
        Converts a JSON-parsed include/exclude entry (PSCustomObject) into an
        ordered hashtable, preserving the property order from the JSON file.
    #>
    param([Parameter(Mandatory)]$Rule)

    $ordered = [ordered]@{}
    foreach ($prop in $Rule.PSObject.Properties) { $ordered[$prop.Name] = $prop.Value }
    return $ordered
}

function New-BuildMatrixStrategy {
    <#
    .SYNOPSIS
        Builds the complete strategy object from a parsed configuration.
    .DESCRIPTION
        Config schema (JSON):
          os               [string[]]  required, non-empty -> matrix key 'os'
          languageVersions [string[]]  required, non-empty -> matrix key 'version'
          featureFlags     [string[]]  optional            -> matrix key 'flags'
          exclude          [object[]]  optional partial-match removal rules
          include          [object[]]  optional merge-or-append rules
          failFast         [bool]      optional, default true  -> 'fail-fast'
          maxParallel      [int]       optional; omitted if unset -> 'max-parallel'
          maxMatrixSize    [int]       optional, default 256 (the GHA hard limit)
    .OUTPUTS
        Ordered hashtable ready for ConvertTo-Json:
          { 'fail-fast', ['max-parallel'], matrix = { include = [combos] } }
    #>
    param([Parameter(Mandatory)]$Config)

    # --- Validate required axes -----------------------------------------
    $os = @(Get-ConfigProperty -Config $Config -Name 'os')
    if ($os.Count -eq 0) {
        throw "Invalid configuration: it must include a non-empty 'os' array."
    }
    $versions = @(Get-ConfigProperty -Config $Config -Name 'languageVersions')
    if ($versions.Count -eq 0) {
        throw "Invalid configuration: it must include a non-empty 'languageVersions' array."
    }

    # --- Validate numeric options ---------------------------------------
    $maxParallel = Get-ConfigProperty -Config $Config -Name 'maxParallel'
    if ($null -ne $maxParallel -and ([int]$maxParallel -lt 1 -or $maxParallel -ne [math]::Floor($maxParallel))) {
        throw "Invalid configuration: 'maxParallel' must be a positive integer, got '$maxParallel'."
    }
    $maxMatrixSize = Get-ConfigProperty -Config $Config -Name 'maxMatrixSize'
    if ($null -eq $maxMatrixSize) {
        $maxMatrixSize = 256  # GitHub Actions' own per-workflow-run matrix limit.
    }
    elseif ([int]$maxMatrixSize -lt 1 -or $maxMatrixSize -ne [math]::Floor($maxMatrixSize)) {
        throw "Invalid configuration: 'maxMatrixSize' must be a positive integer, got '$maxMatrixSize'."
    }

    # --- Build axes (featureFlags axis only when configured) ------------
    $axes = [ordered]@{ os = $os; version = $versions }
    $flags = @(Get-ConfigProperty -Config $Config -Name 'featureFlags')
    if ($flags.Count -gt 0) { $axes['flags'] = $flags }

    # --- Expand, then apply exclude and include rules --------------------
    $combos = Expand-MatrixAxes -Axes $axes

    $excludeRules = @(Get-ConfigProperty -Config $Config -Name 'exclude') |
        Where-Object { $null -ne $_ } | ForEach-Object { ConvertTo-OrderedRule -Rule $_ }
    $combos = Remove-ExcludedCombination -Combinations $combos -ExcludeRules @($excludeRules)
    if ($combos.Count -eq 0) {
        throw 'Invalid configuration: the resulting matrix is empty - the exclude rules removed every combination.'
    }

    $includeRules = @(Get-ConfigProperty -Config $Config -Name 'include') |
        Where-Object { $null -ne $_ } | ForEach-Object { ConvertTo-OrderedRule -Rule $_ }
    $combos = Add-IncludedCombination -Combinations $combos -IncludeRules @($includeRules) -AxisNames @($axes.Keys)

    # --- Enforce the size cap on the final combination count -------------
    Test-MatrixSize -Count $combos.Count -MaxSize ([int]$maxMatrixSize)

    # --- Assemble the strategy object ------------------------------------
    $failFast = Get-ConfigProperty -Config $Config -Name 'failFast'
    if ($null -eq $failFast) { $failFast = $true }  # GHA's own default

    $strategy = [ordered]@{ 'fail-fast' = [bool]$failFast }
    if ($null -ne $maxParallel) { $strategy['max-parallel'] = [int]$maxParallel }
    # Emitting combinations under matrix.include is the canonical shape for
    # dynamic matrices consumed via: matrix: ${{ fromJSON(outputs.x).matrix }}
    $strategy['matrix'] = [ordered]@{ include = @($combos) }
    return $strategy
}
