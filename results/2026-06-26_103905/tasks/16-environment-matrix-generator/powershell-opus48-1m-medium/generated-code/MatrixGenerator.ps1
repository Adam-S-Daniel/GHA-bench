#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Generate a GitHub Actions build matrix (strategy.matrix) from a declarative
    configuration describing OS options, language versions and feature flags.

.DESCRIPTION
    The generator expands the cartesian product of every matrix dimension, then
    applies GitHub-Actions-compatible `exclude` and `include` rules, and finally
    validates that the resulting matrix does not exceed a configurable maximum
    size. The output is a JSON document suitable for use as `strategy.matrix`
    (the expanded combinations are emitted under `matrix.include`, which lets
    GitHub Actions consume the list verbatim) together with `max-parallel` and
    `fail-fast` strategy settings.

    Config schema (JSON):
        {
          "matrix": {
            "os":   ["ubuntu-latest", "windows-latest"],   # dimensions...
            "node": [18, 20],
            "include": [ { ... } ],                          # optional
            "exclude": [ { ... } ]                           # optional
          },
          "maxParallel": 4,        # optional -> max-parallel
          "failFast":   false,     # optional -> fail-fast (default true)
          "maxSize":    256        # optional, validation cap (default 256)
        }

.PARAMETER ConfigPath
    Path to a JSON configuration file. When supplied the script runs as a CLI:
    it reads the config, builds the matrix and writes the JSON result.

.PARAMETER OutputPath
    Optional path to write the resulting JSON to. When omitted the JSON is
    written to standard output.

.EXAMPLE
    ./MatrixGenerator.ps1 -ConfigPath ./config.json
#>
[CmdletBinding()]
param(
    [string]$ConfigPath,
    [string]$OutputPath
)

# Keys inside the `matrix` object that are control rules rather than dimensions.
$script:ReservedMatrixKeys = @('include', 'exclude')

function Expand-Matrix {
    <#
    .SYNOPSIS
        Compute the cartesian product of all matrix dimensions.
    .DESCRIPTION
        Given a hashtable of dimension-name -> value-array, return an array of
        ordered hashtables, one per combination. With no dimensions a single
        empty combination is returned (matching GitHub Actions semantics, where
        an empty matrix still yields one job when combined with includes).
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Dimensions
    )

    # Start with one empty combination and fold each dimension into the set.
    $combinations = @([ordered]@{})

    foreach ($name in $Dimensions.Keys) {
        $values = @($Dimensions[$name])
        if ($values.Count -eq 0) {
            # A dimension with no values contributes nothing and would collapse
            # the whole product to empty; treat it as an error-worthy condition.
            throw "Matrix dimension '$name' has no values."
        }

        $next = [System.Collections.Generic.List[object]]::new()
        foreach ($combo in $combinations) {
            foreach ($value in $values) {
                # Clone the existing combination and append this dimension value
                # so each branch is independent.
                $clone = [ordered]@{}
                foreach ($k in $combo.Keys) { $clone[$k] = $combo[$k] }
                $clone[$name] = $value
                $next.Add($clone)
            }
        }
        $combinations = $next.ToArray()
    }

    return ,@($combinations)
}

function Test-ExcludeMatch {
    <#
    .SYNOPSIS
        Return $true when a combination matches an exclude rule.
    .DESCRIPTION
        An exclude rule is a partial match: the combination is excluded when
        every key in the rule exists in the combination with an equal value.
    #>
    param(
        [Parameter(Mandatory)] $Combination,
        [Parameter(Mandatory)] $Rule
    )

    foreach ($key in $Rule.Keys) {
        if (-not $Combination.Contains($key)) { return $false }
        if ($Combination[$key] -ne $Rule[$key]) { return $false }
    }
    return $true
}

function Remove-Excludes {
    <#
    .SYNOPSIS
        Drop every combination that matches any exclude rule.
    #>
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]]$Combinations,
        $Excludes
    )

    if (-not $Excludes) { return ,@($Combinations) }

    $kept = [System.Collections.Generic.List[object]]::new()
    foreach ($combo in $Combinations) {
        $excluded = $false
        foreach ($rule in $Excludes) {
            if (Test-ExcludeMatch -Combination $combo -Rule $rule) {
                $excluded = $true
                break
            }
        }
        if (-not $excluded) { $kept.Add($combo) }
    }
    return ,@($kept.ToArray())
}

function Add-Includes {
    <#
    .SYNOPSIS
        Apply GitHub-Actions `include` semantics to a set of combinations.
    .DESCRIPTION
        For each include object, its key:value pairs are added to every existing
        combination provided none of the pairs would overwrite an *original*
        matrix dimension value. If an include object can be merged into at least
        one combination it is merged (and not added separately); otherwise it is
        appended as a brand new combination. Original dimension values are never
        overwritten, but values added by earlier includes may be.
    #>
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]]$Combinations,
        $Includes,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]]$DimensionKeys
    )

    if (-not $Includes) { return ,@($Combinations) }

    # `result` is the running output list; `targets` are only the ORIGINAL
    # expanded combinations. Includes may merge into originals but never into
    # combinations created by a previous include (those stand alone).
    $result = [System.Collections.Generic.List[object]]::new()
    $targets = [System.Collections.Generic.List[object]]::new()
    foreach ($c in $Combinations) { $result.Add($c); $targets.Add($c) }

    foreach ($inc in $Includes) {
        $mergedSomewhere = $false

        foreach ($combo in $targets) {
            # The include is compatible with this combination only if, for every
            # key it shares with an ORIGINAL matrix dimension, the values match.
            $compatible = $true
            foreach ($key in $inc.Keys) {
                if ($DimensionKeys -contains $key -and $combo.Contains($key) -and
                    $combo[$key] -ne $inc[$key]) {
                    $compatible = $false
                    break
                }
            }
            if (-not $compatible) { continue }

            # Merge: add new keys and overwrite previously-added (non-original)
            # keys, but never overwrite an original dimension value.
            foreach ($key in $inc.Keys) {
                if ($DimensionKeys -contains $key -and $combo.Contains($key)) {
                    continue  # original value protected
                }
                $combo[$key] = $inc[$key]
            }
            $mergedSomewhere = $true
        }

        if (-not $mergedSomewhere) {
            # Could not extend any existing combination -> new standalone job.
            $new = [ordered]@{}
            foreach ($key in $inc.Keys) { $new[$key] = $inc[$key] }
            $result.Add($new)
        }
    }

    return ,@($result.ToArray())
}

function ConvertTo-Hashtable {
    <#
    .SYNOPSIS
        Recursively convert a PSCustomObject (e.g. from ConvertFrom-Json) into
        ordered hashtables / arrays so the rest of the code can treat config
        uniformly regardless of its source.
    #>
    param($InputObject)

    if ($null -eq $InputObject) { return $null }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $ht = [ordered]@{}
        foreach ($key in $InputObject.Keys) {
            $ht[$key] = ConvertTo-Hashtable $InputObject[$key]
        }
        return $ht
    }

    if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
        $ht = [ordered]@{}
        foreach ($prop in $InputObject.PSObject.Properties) {
            $ht[$prop.Name] = ConvertTo-Hashtable $prop.Value
        }
        return $ht
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and
        $InputObject -isnot [string]) {
        return @($InputObject | ForEach-Object { ConvertTo-Hashtable $_ })
    }

    return $InputObject
}

function New-BuildMatrix {
    <#
    .SYNOPSIS
        Build the complete strategy object from a configuration.
    .DESCRIPTION
        Validates the configuration, expands dimensions, applies exclude and
        include rules, enforces the maximum size and returns a PSCustomObject
        ready to be serialized to JSON.
    .OUTPUTS
        PSCustomObject with properties: matrix (containing `include`),
        max-parallel, fail-fast and size.
    #>
    param(
        [Parameter(Mandatory)] $Config
    )

    $cfg = ConvertTo-Hashtable $Config

    if ($null -eq $cfg -or -not $cfg.Contains('matrix')) {
        throw "Configuration must contain a 'matrix' object."
    }

    $matrix = $cfg['matrix']
    if ($matrix -isnot [System.Collections.IDictionary]) {
        throw "Configuration 'matrix' must be an object/map of dimensions."
    }

    # Separate dimensions from the reserved include/exclude rules.
    $dimensions = [ordered]@{}
    foreach ($key in $matrix.Keys) {
        if ($script:ReservedMatrixKeys -contains $key) { continue }
        $dimensions[$key] = @($matrix[$key])
    }

    $includes = if ($matrix.Contains('include')) { @($matrix['include']) } else { @() }
    $excludes = if ($matrix.Contains('exclude')) { @($matrix['exclude']) } else { @() }

    if ($dimensions.Count -eq 0 -and $includes.Count -eq 0) {
        throw "Configuration must define at least one matrix dimension or include entry."
    }

    # 1. Cartesian product of dimensions. With no dimensions there are no base
    # combinations to seed (each include becomes its own standalone job), so we
    # start from an empty set rather than the single empty seed combination.
    if ($dimensions.Count -eq 0) {
        $combos = @()
    }
    else {
        $combos = Expand-Matrix -Dimensions ([hashtable]$dimensions)
    }

    # 2. Remove excluded combinations.
    $combos = Remove-Excludes -Combinations $combos -Excludes $excludes

    # 3. Apply includes (extend matching base combinations or append new ones).
    $dimKeys = @($dimensions.Keys)
    $combos = Add-Includes -Combinations $combos -Includes $includes -DimensionKeys $dimKeys

    # 4. Validate maximum size.
    $maxSize = if ($cfg.Contains('maxSize')) { [int]$cfg['maxSize'] } else { 256 }
    if ($maxSize -lt 1) {
        throw "maxSize must be a positive integer (got $maxSize)."
    }
    $size = @($combos).Count
    if ($size -eq 0) {
        throw "Generated matrix is empty after applying exclude rules; nothing to build."
    }
    if ($size -gt $maxSize) {
        throw "Generated matrix size $size exceeds the maximum allowed size of $maxSize."
    }

    # Build the strategy settings.
    $failFast = if ($cfg.Contains('failFast')) { [bool]$cfg['failFast'] } else { $true }

    # Convert ordered hashtables to PSCustomObjects for clean JSON output.
    $includeList = foreach ($combo in $combos) {
        $obj = [ordered]@{}
        foreach ($k in $combo.Keys) { $obj[$k] = $combo[$k] }
        [pscustomobject]$obj
    }

    $output = [ordered]@{
        'fail-fast' = $failFast
        'matrix'    = [pscustomobject]@{ include = @($includeList) }
        'size'      = $size
    }
    if ($cfg.Contains('maxParallel')) {
        $output['max-parallel'] = [int]$cfg['maxParallel']
    }

    return [pscustomobject]$output
}

function ConvertTo-MatrixJson {
    <#
    .SYNOPSIS
        Serialize the strategy object to indented JSON.
    #>
    param(
        [Parameter(Mandatory)] $Matrix,
        [int]$Depth = 10
    )
    return ($Matrix | ConvertTo-Json -Depth $Depth)
}

function Invoke-MatrixGenerator {
    <#
    .SYNOPSIS
        CLI entry point: read config file, build matrix, emit JSON.
    #>
    param(
        [Parameter(Mandatory)] [string]$ConfigPath,
        [string]$OutputPath
    )

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        throw "Config file not found: $ConfigPath"
    }

    $raw = Get-Content -LiteralPath $ConfigPath -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "Config file is empty: $ConfigPath"
    }

    try {
        $config = $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Failed to parse config JSON '$ConfigPath': $($_.Exception.Message)"
    }

    $matrix = New-BuildMatrix -Config $config
    $json = ConvertTo-MatrixJson -Matrix $matrix

    if ($OutputPath) {
        Set-Content -LiteralPath $OutputPath -Value $json -Encoding utf8
    }
    # Always emit to stdout as well so CI logs and pipelines can capture it.
    Write-Output $json
}

# Run as a CLI only when a config path is supplied AND the script is invoked
# directly (not dot-sourced by the test suite).
if ($MyInvocation.InvocationName -ne '.' -and $ConfigPath) {
    try {
        Invoke-MatrixGenerator -ConfigPath $ConfigPath -OutputPath $OutputPath
    }
    catch {
        Write-Error $_.Exception.Message
        exit 1
    }
}
