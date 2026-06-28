<#
  BuildMatrix.psm1
  -----------------
  Pure logic for turning a build-matrix configuration into a GitHub Actions
  `strategy.matrix` definition. No file/console I/O lives here so the logic stays
  trivially unit-testable; the CLI wrapper (Invoke-MatrixGenerator.ps1) handles
  files, stdout and workflow-command annotations.

  The include/exclude semantics intentionally mirror GitHub's documented matrix
  expansion algorithm ("Expanding or adding matrix configurations" in the GitHub
  Actions docs), so a matrix generated here behaves identically to one GitHub would
  expand natively:

    * The cartesian product of the axes is generated, first axis varying slowest.
    * `exclude` entries remove every combination they partially match.
    * Each `include` entry is merged into every ORIGINAL combination it is
      compatible with (compatible = it does not overwrite an original axis value).
      Added, non-axis keys MAY be overwritten by later includes. An include that is
      compatible with no original combination is appended as a new standalone job.
#>

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# Small accessors that work for both PSCustomObject (from ConvertFrom-Json) and
# IDictionary, so callers can pass either shape.
# ---------------------------------------------------------------------------

function Get-ConfigProperty {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $null
    }
    $prop = $Object.PSObject.Properties[$Name]
    if ($prop) { return $prop.Value }
    return $null
}

function Test-ConfigHas {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $false }
    if ($Object -is [System.Collections.IDictionary]) { return $Object.Contains($Name) }
    return $null -ne $Object.PSObject.Properties[$Name]
}

function ConvertTo-OrderedHashtable {
    # Copy a PSCustomObject / IDictionary into a fresh ordered hashtable so we can
    # mutate combinations freely without aliasing the caller's data.
    param($Object)
    $h = [ordered]@{}
    if ($null -eq $Object) { return $h }
    if ($Object -is [System.Collections.IDictionary]) {
        foreach ($k in $Object.Keys) { $h[$k] = $Object[$k] }
    }
    else {
        foreach ($p in $Object.PSObject.Properties) { $h[$p.Name] = $p.Value }
    }
    return $h
}

function Test-FilterMatch {
    # True when every key in $Filter is present in $Combination with an equal value.
    # An empty filter matches nothing (so an empty exclude entry is a no-op).
    param([System.Collections.IDictionary]$Combination, [System.Collections.IDictionary]$Filter)
    if ($Filter.Count -eq 0) { return $false }
    foreach ($key in $Filter.Keys) {
        if (-not $Combination.Contains($key)) { return $false }
        if ($Combination[$key] -ne $Filter[$key]) { return $false }
    }
    return $true
}

function Get-CartesianProduct {
    <#
        .SYNOPSIS
            Expand an ordered set of axes into every combination.
        .DESCRIPTION
            Returns one ordered hashtable per combination. The FIRST declared axis
            varies slowest (it is the outermost loop) and the LAST axis varies
            fastest — matching how GitHub Actions orders generated matrix jobs.
        .PARAMETER Axes
            An ordered dictionary mapping axis name -> array of values.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Axes
    )

    # Start with a single empty combination and fold each axis in, left to right.
    # Folding left-to-right while appending the new axis as the inner key makes the
    # first axis vary slowest, exactly as GitHub orders its jobs.
    $combinations = [System.Collections.Generic.List[object]]::new()
    $combinations.Add([ordered]@{})

    foreach ($axisName in $Axes.Keys) {
        $values = @($Axes[$axisName])
        if ($values.Count -eq 0) {
            throw "Matrix axis '$axisName' has no values; every axis must list at least one value."
        }

        $next = [System.Collections.Generic.List[object]]::new()
        foreach ($combo in $combinations) {
            foreach ($value in $values) {
                # Clone the partial combination and extend it with this axis value.
                $copy = [ordered]@{}
                foreach ($key in $combo.Keys) { $copy[$key] = $combo[$key] }
                $copy[$axisName] = $value
                $next.Add($copy)
            }
        }
        $combinations = $next
    }

    return $combinations
}

function Get-BuildMatrix {
    <#
        .SYNOPSIS
            Build a validated GitHub Actions strategy from a matrix configuration.
        .DESCRIPTION
            Accepts a config object (typically the result of ConvertFrom-Json) with:
              matrix       : object of axisName -> array of values  (OS / versions / flags)
              include      : array of objects (extra/expanded combinations)
              exclude      : array of objects (combinations to drop)
              max-parallel : positive integer (optional)
              fail-fast    : boolean (optional, default true)
              max-size     : integer cap on the number of jobs (optional, default 256)
            Returns a PSCustomObject whose `.strategy` member is a ready-to-use GitHub
            Actions strategy block, plus `.size`, `.max-size`, `.valid` and `.axes`
            metadata. Throws a descriptive error on any validation failure.
        .PARAMETER Config
            The parsed configuration object.
        .PARAMETER MaxSize
            Overrides the config's max-size (and the default of 256).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Config,

        [Parameter()]
        [int]$MaxSize
    )

    # --- Read the axes (preserving declaration order) ---------------------------
    $matrixObj = Get-ConfigProperty $Config 'matrix'
    $axes = ConvertTo-OrderedHashtable $matrixObj
    $axisKeys = @($axes.Keys)

    # --- Read include / exclude as lists of ordered hashtables ------------------
    $excludes = @()
    $excludeRaw = Get-ConfigProperty $Config 'exclude'
    if ($null -ne $excludeRaw) {
        $excludes = @($excludeRaw) | ForEach-Object { ConvertTo-OrderedHashtable $_ }
    }

    $includes = @()
    $includeRaw = Get-ConfigProperty $Config 'include'
    if ($null -ne $includeRaw) {
        $includes = @($includeRaw) | ForEach-Object { ConvertTo-OrderedHashtable $_ }
    }

    # --- A matrix needs at least one axis or one include entry ------------------
    if ($axisKeys.Count -eq 0 -and $includes.Count -eq 0) {
        throw "Invalid configuration: a matrix must define at least one axis (under 'matrix') or one 'include' entry."
    }

    # --- 1. Cartesian product of the axes --------------------------------------
    $baseCombos = [System.Collections.Generic.List[object]]::new()
    if ($axisKeys.Count -gt 0) {
        foreach ($c in @(Get-CartesianProduct -Axes $axes)) { $baseCombos.Add($c) }
    }

    # --- 2. Apply excludes (partial match acts as a wildcard) ------------------
    if ($excludes.Count -gt 0) {
        $kept = [System.Collections.Generic.List[object]]::new()
        foreach ($combo in $baseCombos) {
            $drop = $false
            foreach ($ex in $excludes) {
                if (Test-FilterMatch -Combination $combo -Filter $ex) { $drop = $true; break }
            }
            if (-not $drop) { $kept.Add($combo) }
        }
        $baseCombos = $kept
    }

    # --- 3. Apply includes (GitHub's documented merge/append algorithm) --------
    $extraCombos = [System.Collections.Generic.List[object]]::new()
    foreach ($inc in $includes) {
        $added = $false
        foreach ($combo in $baseCombos) {
            # Compatible iff no original AXIS key in the include overwrites the combo.
            $compatible = $true
            foreach ($key in $inc.Keys) {
                if ($axisKeys -contains $key) {
                    if (-not $combo.Contains($key) -or $combo[$key] -ne $inc[$key]) {
                        $compatible = $false
                        break
                    }
                }
            }
            if ($compatible) {
                foreach ($key in $inc.Keys) { $combo[$key] = $inc[$key] }
                $added = $true
            }
        }
        if (-not $added) {
            # Could not be merged into any original combination -> new standalone job.
            $extraCombos.Add($inc)
        }
    }

    $allCombos = [System.Collections.Generic.List[object]]::new()
    foreach ($c in $baseCombos)  { $allCombos.Add($c) }
    foreach ($c in $extraCombos) { $allCombos.Add($c) }
    $size = $allCombos.Count

    # --- 4. Resolve strategy knobs ---------------------------------------------
    $failFast = $true
    if (Test-ConfigHas $Config 'fail-fast') {
        $failFast = [bool](Get-ConfigProperty $Config 'fail-fast')
    }

    $maxParallel = $null
    if (Test-ConfigHas $Config 'max-parallel') {
        $maxParallel = [int](Get-ConfigProperty $Config 'max-parallel')
        if ($maxParallel -le 0) {
            throw "Invalid configuration: max-parallel must be a positive integer (got $maxParallel)."
        }
    }

    # max-size precedence: explicit -MaxSize > config max-size > GitHub's 256 cap.
    $effectiveMax = 256
    if (Test-ConfigHas $Config 'max-size') {
        $effectiveMax = [int](Get-ConfigProperty $Config 'max-size')
    }
    if ($PSBoundParameters.ContainsKey('MaxSize')) {
        $effectiveMax = $MaxSize
    }

    # --- 5. Validate size -------------------------------------------------------
    if ($size -eq 0) {
        throw "The expanded matrix is empty; every combination was removed by the exclude rules."
    }
    if ($size -gt $effectiveMax) {
        throw "Generated matrix exceeds the maximum allowed size (max-size = $effectiveMax, actual = $size). Reduce the number of axis values, add excludes, or raise max-size."
    }

    # --- 6. Shape the result. Convert ordered hashtables to PSCustomObjects so the
    #        keys serialize as JSON object properties (and not the dictionary's
    #        .NET members), and so include-only matrices remain valid GHA matrices.
    $includeArray = @($allCombos | ForEach-Object { [pscustomobject]$_ })

    $matrix = [pscustomobject][ordered]@{ include = $includeArray }

    $strategy = [ordered]@{
        matrix      = $matrix
        'fail-fast' = $failFast
    }
    if ($null -ne $maxParallel) { $strategy['max-parallel'] = $maxParallel }

    return [pscustomobject][ordered]@{
        strategy   = [pscustomobject]$strategy
        size       = $size
        'max-size' = $effectiveMax
        valid      = $true
        axes       = $axisKeys
    }
}

function Import-MatrixConfig {
    <#
        .SYNOPSIS
            Read and parse a matrix configuration JSON file with clear error messages.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Configuration file not found: '$Path'."
    }

    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "Configuration file '$Path' is empty."
    }

    try {
        return $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Configuration file '$Path' contains invalid JSON: $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function Get-CartesianProduct, Get-BuildMatrix, Import-MatrixConfig
