<#
.SYNOPSIS
    Build-matrix generator for GitHub Actions strategy.matrix.

.DESCRIPTION
    Given a configuration describing matrix dimensions (OS options, language
    versions, feature flags, ...) plus optional include/exclude rules,
    max-parallel, fail-fast and a max-size guard, this module produces a
    GitHub Actions `strategy` object and validates that the expanded matrix
    does not exceed the allowed size.

    The module is intentionally built from small, pure functions so the logic
    is unit-testable (with Pester) without going through GitHub Actions.

    Reserved/control keys in the config: matrix, include, exclude,
    max-parallel, fail-fast, max-size.
#>

Set-StrictMode -Version Latest

# Keys that are NOT matrix dimensions when found at the top level of a config.
$script:ReservedKeys = @('matrix', 'include', 'exclude', 'max-parallel', 'fail-fast', 'max-size')

function ConvertTo-Hashtable {
    <#
    .SYNOPSIS
        Normalises a value (PSCustomObject from ConvertFrom-Json, hashtable,
        or ordered dict) into an ordered hashtable so downstream code can treat
        all inputs uniformly. Arrays/scalars are returned unchanged.
    #>
    param([Parameter(ValueFromPipeline = $true)] $InputObject)

    process {
        if ($null -eq $InputObject) { return $null }

        if ($InputObject -is [System.Collections.IDictionary]) {
            $out = [ordered]@{}
            foreach ($key in $InputObject.Keys) {
                $out[$key] = ConvertTo-Hashtable $InputObject[$key]
            }
            return $out
        }

        if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
            $out = [ordered]@{}
            foreach ($prop in $InputObject.PSObject.Properties) {
                $out[$prop.Name] = ConvertTo-Hashtable $prop.Value
            }
            return $out
        }

        # Arrays: normalise each element but keep array-ness.
        if ($InputObject -is [System.Array]) {
            return @($InputObject | ForEach-Object { ConvertTo-Hashtable $_ })
        }

        return $InputObject
    }
}

function Get-MatrixCombination {
    <#
    .SYNOPSIS
        Expand matrix dimensions into the list of job combinations, applying
        exclude then include rules following GitHub Actions' documented
        algorithm.

    .PARAMETER Matrix
        Ordered dictionary of dimensionName -> array of values.

    .PARAMETER Exclude
        Array of partial combinations to remove.

    .PARAMETER Include
        Array of partial combinations to merge in / append.

    .OUTPUTS
        An array of ordered hashtables, one per resulting job.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Matrix,
        $Exclude = @(),
        $Include = @()
    )

    $Matrix  = ConvertTo-Hashtable $Matrix
    # Normalise each entry individually, filtering out any $null entries so the
    # function is robust to $null / empty-array inputs.
    $Exclude = @($Exclude | Where-Object { $null -ne $_ } | ForEach-Object { ConvertTo-Hashtable $_ })
    $Include = @($Include | Where-Object { $null -ne $_ } | ForEach-Object { ConvertTo-Hashtable $_ })

    # Track which keys came from the original matrix dimensions. GitHub only
    # lets an include merge into a combination when it does not overwrite any
    # ORIGINAL matrix value (added keys may be overwritten by later includes).
    $dimensionKeys = @($Matrix.Keys)

    # 1. Cartesian product of the dimensions.
    $combos = @([ordered]@{})  # start with one empty combination
    foreach ($key in $dimensionKeys) {
        $values = @($Matrix[$key])
        $next = @()
        foreach ($combo in $combos) {
            foreach ($value in $values) {
                $clone = [ordered]@{}
                foreach ($k in $combo.Keys) { $clone[$k] = $combo[$k] }
                $clone[$key] = $value
                $next += $clone
            }
        }
        $combos = $next
    }

    # If there were no dimensions at all, there are zero base combinations.
    if ($dimensionKeys.Count -eq 0) { $combos = @() }

    # 2. Apply exclude rules: drop any combination that matches ALL key/value
    #    pairs of an exclude entry (unspecified keys act as wildcards).
    if ($Exclude.Count -gt 0) {
        $combos = @($combos | Where-Object {
            $combo = $_
            $matchesAnyExclude = $false
            foreach ($ex in $Exclude) {
                $allMatch = $true
                foreach ($k in $ex.Keys) {
                    if (-not $combo.Contains($k) -or ("$($combo[$k])" -ne "$($ex[$k])")) {
                        $allMatch = $false
                        break
                    }
                }
                if ($allMatch) { $matchesAnyExclude = $true; break }
            }
            -not $matchesAnyExclude
        })
    }

    # 3. Apply include rules.
    foreach ($inc in $Include) {
        $merged = $false
        foreach ($combo in $combos) {
            # An include can merge into a combo if none of its keys would
            # overwrite an ORIGINAL matrix value with a different value.
            $canMerge = $true
            foreach ($k in $inc.Keys) {
                if ($dimensionKeys -contains $k -and $combo.Contains($k) -and
                    "$($combo[$k])" -ne "$($inc[$k])") {
                    $canMerge = $false
                    break
                }
            }
            if ($canMerge) {
                foreach ($k in $inc.Keys) { $combo[$k] = $inc[$k] }
                $merged = $true
            }
        }
        # If it could not merge into any existing combination, it becomes a new
        # standalone combination.
        if (-not $merged) {
            $new = [ordered]@{}
            foreach ($k in $inc.Keys) { $new[$k] = $inc[$k] }
            $combos = @($combos) + @($new)
        }
    }

    return @($combos)
}

function New-BuildMatrix {
    <#
    .SYNOPSIS
        Build the full GitHub Actions strategy object from a config, validating
        against max-size.

    .PARAMETER Config
        Hashtable/PSCustomObject with a `matrix` section plus optional
        include/exclude/max-parallel/fail-fast/max-size keys.

    .OUTPUTS
        PSCustomObject with .strategy (the GitHub Actions strategy block) and
        .jobCount (number of expanded jobs).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Config)

    $Config = ConvertTo-Hashtable $Config

    if (-not $Config.Contains('matrix')) {
        throw "Invalid configuration: required 'matrix' section is missing."
    }

    $matrix = $Config['matrix']
    if ($null -eq $matrix -or @($matrix.Keys).Count -eq 0) {
        throw "Invalid configuration: 'matrix' section must define at least one dimension."
    }

    # NB: an `if` expression whose chosen branch is an empty array evaluates to
    # $null (the empty array unrolls to nothing), so assign defaults explicitly.
    $include = @()
    if ($Config.Contains('include')) { $include = @($Config['include']) }
    $exclude = @()
    if ($Config.Contains('exclude')) { $exclude = @($Config['exclude']) }

    # Expand to validate the resulting job count.
    $combos = Get-MatrixCombination -Matrix $matrix -Include $include -Exclude $exclude
    $jobCount = @($combos).Count

    if ($jobCount -eq 0) {
        throw "Invalid configuration: the matrix expanded to zero jobs (check your exclude rules)."
    }

    # Validate max-size if present.
    if ($Config.Contains('max-size')) {
        $maxSize = [int]$Config['max-size']
        if ($jobCount -gt $maxSize) {
            throw "Matrix validation failed: the expanded matrix has $jobCount jobs, which exceeds the maximum allowed size of $maxSize."
        }
    }

    # Build the strategy.matrix block: dimensions + include/exclude.
    $strategyMatrix = [ordered]@{}
    foreach ($k in $matrix.Keys) { $strategyMatrix[$k] = @($matrix[$k]) }
    if ($include.Count -gt 0) { $strategyMatrix['include'] = $include }
    if ($exclude.Count -gt 0) { $strategyMatrix['exclude'] = $exclude }

    # Build the strategy block. fail-fast defaults to true (GitHub's default).
    $strategy = [ordered]@{}
    $strategy['fail-fast'] = if ($Config.Contains('fail-fast')) { [bool]$Config['fail-fast'] } else { $true }
    if ($Config.Contains('max-parallel')) {
        $strategy['max-parallel'] = [int]$Config['max-parallel']
    }
    $strategy['matrix'] = $strategyMatrix

    return [pscustomobject]@{
        strategy = [pscustomobject]$strategy
        jobCount = $jobCount
    }
}

function Invoke-MatrixGenerator {
    <#
    .SYNOPSIS
        CLI-style entry point: read a config JSON file, build the matrix, and
        return the result as JSON text.

    .PARAMETER ConfigPath
        Path to a JSON configuration file.

    .OUTPUTS
        JSON string of the form { "strategy": {...}, "jobCount": N }.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $ConfigPath)

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        throw "Configuration file not found: '$ConfigPath'."
    }

    $raw = Get-Content -LiteralPath $ConfigPath -Raw
    try {
        $config = $raw | ConvertFrom-Json
    }
    catch {
        throw "Configuration file '$ConfigPath' is not valid JSON: $($_.Exception.Message)"
    }

    $result = New-BuildMatrix -Config $config

    # Emit the full result as JSON. Depth 20 covers nested include/exclude.
    return ($result | ConvertTo-Json -Depth 20)
}

Export-ModuleMember -Function Get-MatrixCombination, New-BuildMatrix, Invoke-MatrixGenerator, ConvertTo-Hashtable
