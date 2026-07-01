<#
.SYNOPSIS
    Generates a GitHub Actions build matrix (as a hashtable, or JSON) from a
    config describing OS options, language versions, and feature flags.
#>

function New-EnvironmentMatrix {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Config
    )

    if ($null -eq $Config) {
        throw "Malformed config: config object is null."
    }

    # Support both hashtable and PSCustomObject (from ConvertFrom-Json) inputs.
    $cfg = @{}
    if ($Config -is [hashtable]) {
        $cfg = $Config
    }
    else {
        $Config.PSObject.Properties | ForEach-Object { $cfg[$_.Name] = $_.Value }
    }

    if (-not $cfg.ContainsKey('os') -or $null -eq $cfg['os']) {
        throw "Malformed config: missing required key 'os'."
    }
    if (-not $cfg.ContainsKey('version') -or $null -eq $cfg['version']) {
        throw "Malformed config: missing required key 'version'."
    }
    if (-not $cfg.ContainsKey('flags') -or $null -eq $cfg['flags']) {
        throw "Malformed config: missing required key 'flags'."
    }

    $osList = @($cfg['os'])
    $versionList = @($cfg['version'])
    $flagsList = @($cfg['flags'])

    if ($osList.Count -eq 0 -or $versionList.Count -eq 0 -or $flagsList.Count -eq 0) {
        throw "Malformed config: 'os', 'version', and 'flags' must each contain at least one value."
    }

    # Cartesian product of the three axes.
    $combos = New-Object System.Collections.Generic.List[object]
    foreach ($os in $osList) {
        foreach ($version in $versionList) {
            foreach ($flags in $flagsList) {
                $combos.Add([ordered]@{ os = $os; version = [string]$version; flags = $flags })
            }
        }
    }

    # Apply exclude rules before include rules, matching GitHub Actions matrix semantics.
    if ($cfg.ContainsKey('exclude') -and $cfg['exclude']) {
        foreach ($rule in @($cfg['exclude'])) {
            $ruleHash = ConvertTo-PlainHashtable $rule
            $combos = [System.Collections.Generic.List[object]]($combos | Where-Object {
                -not (Test-ComboMatchesRule -Combo $_ -Rule $ruleHash)
            })
        }
    }

    if ($cfg.ContainsKey('include') -and $cfg['include']) {
        foreach ($rule in @($cfg['include'])) {
            $ruleHash = ConvertTo-PlainHashtable $rule
            $entry = [ordered]@{}
            foreach ($key in $ruleHash.Keys) { $entry[$key] = [string]$ruleHash[$key] }
            $combos.Add($entry)
        }
    }

    $maxSize = if ($cfg.ContainsKey('maxSize') -and $cfg['maxSize']) { [int]$cfg['maxSize'] } else { $null }
    if ($null -ne $maxSize -and $combos.Count -gt $maxSize) {
        throw "Matrix size ($($combos.Count)) exceeds maximum size ($maxSize)."
    }

    $failFast = if ($cfg.ContainsKey('failFast')) { [bool]$cfg['failFast'] } else { $true }

    $result = [ordered]@{
        matrix = [ordered]@{ include = $combos.ToArray() }
        'fail-fast' = $failFast
    }

    if ($cfg.ContainsKey('maxParallel') -and $cfg['maxParallel']) {
        $result['max-parallel'] = [int]$cfg['maxParallel']
    }

    return $result
}

function ConvertTo-PlainHashtable {
    param($Object)
    $hash = @{}
    if ($Object -is [hashtable]) {
        foreach ($key in $Object.Keys) { $hash[$key] = $Object[$key] }
    }
    else {
        $Object.PSObject.Properties | ForEach-Object { $hash[$_.Name] = $_.Value }
    }
    return $hash
}

function Test-ComboMatchesRule {
    param($Combo, $Rule)
    foreach ($key in $Rule.Keys) {
        if (-not $Combo.Contains($key)) { return $false }
        if ([string]$Combo[$key] -ne [string]$Rule[$key]) { return $false }
    }
    return $true
}

function New-EnvironmentMatrixJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Config,
        [int]$Depth = 10
    )
    $result = New-EnvironmentMatrix -Config $Config
    return $result | ConvertTo-Json -Depth $Depth
}
