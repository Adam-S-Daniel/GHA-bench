# MatrixGenerator.psm1
#
# Environment Matrix Generator -- core logic.
#
# Given a configuration describing build axes (OS options, language versions,
# feature flags, ...), this module produces a fully-expanded GitHub Actions
# build matrix following GitHub's documented `strategy.matrix` semantics:
#
#   1. The base matrix is the cartesian product of every axis.
#   2. `exclude` rules remove any base combination that matches all of an
#      exclude entry's key/value pairs.
#   3. `include` rules either extend existing combinations (when they do not
#      overwrite an original axis value) or are appended as brand-new
#      standalone combinations.
#   4. The result is validated against a maximum size and emitted as JSON
#      suitable for `strategy.matrix` (the `{ "include": [ ... ] }` form).
#
# The functions here are deliberately pure (no file or console side effects) so
# they are trivially unit-testable. The thin CLI wrapper Invoke-MatrixGenerator.ps1
# handles I/O and process exit codes.

Set-StrictMode -Version Latest

# GitHub Actions allows at most 256 jobs per matrix; we use that as the default
# ceiling when a configuration does not specify its own `max-size`.
$script:DefaultMaxSize = 256

# Keys that live alongside the axes inside `matrix` but are not themselves axes.
$script:ReservedMatrixKeys = @('include', 'exclude')

#region Internal helpers

function Get-PropertyNameList {
    # Returns the ordered list of "keys" for either an IDictionary (hashtable /
    # ordered dictionary) or a PSCustomObject (as produced by ConvertFrom-Json).
    param([Parameter(Mandatory)] $InputObject)

    if ($InputObject -is [System.Collections.IDictionary]) {
        return @($InputObject.Keys)
    }
    return @($InputObject.PSObject.Properties.Name)
}

function Test-HasProperty {
    # True if the object exposes the given key/property.
    param($InputObject, [string]$Name)

    if ($null -eq $InputObject) { return $false }
    if ($InputObject -is [System.Collections.IDictionary]) {
        return $InputObject.Contains($Name)
    }
    return $null -ne $InputObject.PSObject.Properties[$Name]
}

function Get-PropertyValue {
    # Reads a key/property value from either a dictionary or a PSCustomObject,
    # returning $null when it is absent.
    param($InputObject, [string]$Name)

    if (-not (Test-HasProperty -InputObject $InputObject -Name $Name)) { return $null }
    if ($InputObject -is [System.Collections.IDictionary]) {
        return $InputObject[$Name]
    }
    return $InputObject.PSObject.Properties[$Name].Value
}

function ConvertTo-OrderedHashtable {
    # Normalises any dictionary / PSCustomObject into a fresh [ordered] hashtable
    # so downstream code has a single, predictable shape to work with.
    param([Parameter(Mandatory)] $InputObject)

    $result = [ordered]@{}
    foreach ($name in (Get-PropertyNameList -InputObject $InputObject)) {
        $result[$name] = Get-PropertyValue -InputObject $InputObject -Name $name
    }
    return $result
}

function Test-ValueEquals {
    # GitHub compares matrix values loosely -- the number 18 and the string "18"
    # are treated as the same value. We mirror that by comparing string forms
    # (PowerShell's -eq on strings is case-insensitive, which also makes
    # boolean True/true comparisons behave sensibly).
    param($First, $Second)
    return ([string]$First -eq [string]$Second)
}

#endregion

function Get-CartesianProduct {
    <#
    .SYNOPSIS
        Returns the cartesian product of a set of named axes.
    .PARAMETER Axes
        An ordered dictionary mapping axis name -> array of values. Declaration
        order is preserved so output combinations have stable, predictable keys.
    .OUTPUTS
        An array of [ordered] hashtables, one per combination. With zero axes the
        result is an empty array (GitHub treats an axis-less matrix as having no
        base combinations -- include-only matrices are handled by the caller).
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.Specialized.OrderedDictionary]$Axes
    )

    # No axes -> no base combinations. The unary comma keeps PowerShell from
    # unrolling the empty array away.
    if ($Axes.Count -eq 0) {
        return , @()
    }

    # Seed with a single empty combination, then fold each axis in turn.
    $combinations = @([ordered]@{})

    foreach ($axisName in $Axes.Keys) {
        $axisValues = @($Axes[$axisName])
        $next = [System.Collections.Generic.List[object]]::new()

        foreach ($combo in $combinations) {
            foreach ($value in $axisValues) {
                # Clone the partial combination so siblings stay independent.
                $clone = [ordered]@{}
                foreach ($key in $combo.Keys) { $clone[$key] = $combo[$key] }
                $clone[$axisName] = $value
                $next.Add($clone)
            }
        }

        $combinations = $next.ToArray()
    }

    return , $combinations
}

function Test-CombinationMatch {
    <#
    .SYNOPSIS
        Tests whether a combination satisfies every key/value pair of a filter.
    .DESCRIPTION
        Used for both exclude rules (does this combination match the rule?) and
        include compatibility checks. A combination matches only if, for every
        key in the filter, the combination has that key with an equal value.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] $Combination,
        [Parameter(Mandatory)] $Filter
    )

    foreach ($key in (Get-PropertyNameList -InputObject $Filter)) {
        if (-not (Test-HasProperty -InputObject $Combination -Name $key)) { return $false }
        $comboValue  = Get-PropertyValue -InputObject $Combination -Name $key
        $filterValue = Get-PropertyValue -InputObject $Filter -Name $key
        if (-not (Test-ValueEquals -First $comboValue -Second $filterValue)) { return $false }
    }
    return $true
}

function Get-BuildMatrix {
    <#
    .SYNOPSIS
        Expands a matrix configuration into a validated set of combinations.
    .PARAMETER Config
        A configuration object (hashtable or PSCustomObject). Expected shape:
            matrix:        { <axis>: [..], ..., include: [..], exclude: [..] }
            fail-fast:     bool   (optional, default $true)
            max-parallel:  int    (optional, default unset)
            max-size:      int    (optional, default 256 -- GitHub's hard limit)
    .OUTPUTS
        An [ordered] hashtable with: Combinations, Count, FailFast, MaxParallel,
        MaxSize.
    .NOTES
        Throws (terminating) with ErrorId 'InvalidConfig', 'EmptyMatrix' or
        'MatrixTooLarge' on the corresponding error conditions.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)] $Config
    )

    $matrix = Get-PropertyValue -InputObject $Config -Name 'matrix'
    if ($null -eq $matrix) {
        Write-MatrixError -Message "Configuration is missing the required 'matrix' section." -ErrorId 'InvalidConfig'
    }

    # --- 1. Collect the axes (everything under matrix except include/exclude) ---
    $axes = [ordered]@{}
    foreach ($name in (Get-PropertyNameList -InputObject $matrix)) {
        if ($script:ReservedMatrixKeys -notcontains $name) {
            $axes[$name] = @(Get-PropertyValue -InputObject $matrix -Name $name)
        }
    }
    $axisKeys = @($axes.Keys)

    # --- 2. Base cartesian product (empty when there are no axes) ---
    # Note: Get-CartesianProduct returns an array via the `,` idiom; assign it
    # directly (no `@()` wrapper) to avoid double-wrapping the result.
    if ($axes.Count -gt 0) {
        $base = Get-CartesianProduct -Axes $axes
    }
    else {
        $base = @()
    }

    # --- 3. Apply exclude rules ---
    $excludes = @()
    $rawExcludes = Get-PropertyValue -InputObject $matrix -Name 'exclude'
    if ($null -ne $rawExcludes) {
        $excludes = @($rawExcludes | Where-Object { $null -ne $_ } |
            ForEach-Object { ConvertTo-OrderedHashtable -InputObject $_ })
    }
    if ($excludes.Count -gt 0) {
        $base = @($base | Where-Object {
                $combo = $_
                $isExcluded = $false
                foreach ($rule in $excludes) {
                    if (Test-CombinationMatch -Combination $combo -Filter $rule) {
                        $isExcluded = $true
                        break
                    }
                }
                -not $isExcluded
            })
    }

    # --- 4. Apply include rules (GitHub semantics) ---
    $combinations = [System.Collections.Generic.List[object]]::new()
    foreach ($combo in $base) { $combinations.Add($combo) }

    $includes = @()
    $rawIncludes = Get-PropertyValue -InputObject $matrix -Name 'include'
    if ($null -ne $rawIncludes) {
        $includes = @($rawIncludes | Where-Object { $null -ne $_ } |
            ForEach-Object { ConvertTo-OrderedHashtable -InputObject $_ })
    }

    # New standalone combinations are collected separately so that later include
    # rules only ever match against the *original* base combinations, exactly as
    # GitHub does.
    $standalone = [System.Collections.Generic.List[object]]::new()
    foreach ($include in $includes) {
        $matchedAny = $false
        foreach ($combo in $combinations) {
            # The include can extend this combination only if none of its keys
            # would overwrite an *original axis* value already present here.
            $compatible = $true
            foreach ($key in (Get-PropertyNameList -InputObject $include)) {
                if (($axisKeys -contains $key) -and (Test-HasProperty -InputObject $combo -Name $key)) {
                    $comboValue   = Get-PropertyValue -InputObject $combo   -Name $key
                    $includeValue = Get-PropertyValue -InputObject $include -Name $key
                    if (-not (Test-ValueEquals -First $comboValue -Second $includeValue)) {
                        $compatible = $false
                        break
                    }
                }
            }
            if ($compatible) {
                $matchedAny = $true
                foreach ($key in (Get-PropertyNameList -InputObject $include)) {
                    # Adds new keys and may overwrite values added by earlier
                    # includes, but never the original axis values (guarded above).
                    $combo[$key] = Get-PropertyValue -InputObject $include -Name $key
                }
            }
        }
        if (-not $matchedAny) {
            $standalone.Add((ConvertTo-OrderedHashtable -InputObject $include))
        }
    }
    foreach ($combo in $standalone) { $combinations.Add($combo) }

    # --- 5. Resolve strategy knobs ---
    $failFast = $true
    $rawFailFast = Get-PropertyValue -InputObject $Config -Name 'fail-fast'
    if ($null -ne $rawFailFast) { $failFast = [bool]$rawFailFast }

    $maxParallel = $null
    $rawMaxParallel = Get-PropertyValue -InputObject $Config -Name 'max-parallel'
    if ($null -ne $rawMaxParallel) { $maxParallel = [int]$rawMaxParallel }

    $maxSize = $script:DefaultMaxSize
    $rawMaxSize = Get-PropertyValue -InputObject $Config -Name 'max-size'
    if ($null -ne $rawMaxSize) { $maxSize = [int]$rawMaxSize }

    # --- 6. Validate ---
    $count = $combinations.Count
    if ($count -eq 0) {
        Write-MatrixError -ErrorId 'EmptyMatrix' -Message (
            'The generated matrix is empty: there are no combinations to build. ' +
            'Check the axes and exclude rules in your configuration.')
    }
    if ($count -gt $maxSize) {
        Write-MatrixError -ErrorId 'MatrixTooLarge' -Message (
            "The generated matrix has $count combinations, which exceeds the " +
            "maximum allowed size of $maxSize. Reduce axis values, add exclude " +
            "rules, or raise 'max-size'.")
    }

    return [ordered]@{
        Combinations = @($combinations)
        Count        = $count
        FailFast     = $failFast
        MaxParallel  = $maxParallel
        MaxSize      = $maxSize
    }
}

function Write-MatrixError {
    # Raises a terminating error with a stable, testable ErrorId. Kept as a
    # helper so every error path produces a consistent ErrorRecord.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Message,
        [Parameter(Mandatory)] [string]$ErrorId
    )

    $record = [System.Management.Automation.ErrorRecord]::new(
        [System.InvalidOperationException]::new($Message),
        $ErrorId,
        [System.Management.Automation.ErrorCategory]::InvalidData,
        $null)
    throw $record
}

function ConvertTo-StrategyObject {
    <#
    .SYNOPSIS
        Shapes a Get-BuildMatrix result into a GitHub Actions `strategy` object.
    .OUTPUTS
        An [ordered] hashtable: { fail-fast, [max-parallel], matrix: { include } }.
        `max-parallel` is only present when it was configured.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param([Parameter(Mandatory)] $Result)

    $strategy = [ordered]@{
        'fail-fast' = [bool]$Result.FailFast
    }
    if ($null -ne $Result.MaxParallel) {
        $strategy['max-parallel'] = [int]$Result.MaxParallel
    }
    $strategy['matrix'] = [ordered]@{
        include = @($Result.Combinations)
    }
    return $strategy
}

function ConvertTo-MatrixObject {
    <#
    .SYNOPSIS
        Returns just the `{ include: [...] }` object consumed directly by a job's
        `strategy.matrix: ${{ fromJSON(...) }}`.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param([Parameter(Mandatory)] $Result)

    return [ordered]@{ include = @($Result.Combinations) }
}

function Read-MatrixConfig {
    <#
    .SYNOPSIS
        Loads and parses a matrix configuration from a JSON file or raw string.
    .PARAMETER Path
        Path to a JSON configuration file.
    .PARAMETER Json
        A raw JSON string (mutually exclusive with -Path; handy for tests).
    .OUTPUTS
        The parsed configuration as a PSCustomObject.
    .NOTES
        Throws with ErrorId 'ConfigNotFound' or 'InvalidJson' on failure.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    [OutputType([object])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Path')]
        [string]$Path,

        [Parameter(Mandatory, ParameterSetName = 'Json')]
        [string]$Json
    )

    if ($PSCmdlet.ParameterSetName -eq 'Path') {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            Write-MatrixError -ErrorId 'ConfigNotFound' -Message "Configuration file not found: '$Path'."
        }
        $Json = Get-Content -LiteralPath $Path -Raw
    }

    if ([string]::IsNullOrWhiteSpace($Json)) {
        Write-MatrixError -ErrorId 'InvalidJson' -Message 'Configuration is empty.'
    }

    try {
        return $Json | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-MatrixError -ErrorId 'InvalidJson' -Message "Configuration is not valid JSON: $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function @(
    'Get-CartesianProduct',
    'Test-CombinationMatch',
    'Get-BuildMatrix',
    'ConvertTo-StrategyObject',
    'ConvertTo-MatrixObject',
    'Read-MatrixConfig'
)
