# Environment Matrix Generator
#
# Builds a GitHub Actions strategy.matrix (with include/exclude rules,
# max-parallel and fail-fast) from a small JSON config, and validates
# that the resulting matrix does not exceed a configured maximum size.

function Get-CartesianProduct {
    <#
        .SYNOPSIS
        Expands an ordered hashtable of axis-name -> value-array into the
        cartesian product of all axes, one row (hashtable) per combination.
    #>
    param(
        [Parameter(Mandatory)]
        [System.Collections.Specialized.OrderedDictionary]$Axes
    )

    $keys = @($Axes.Keys)
    $rows = @([ordered]@{})

    foreach ($key in $keys) {
        $values = $Axes[$key]
        $expanded = New-Object System.Collections.Generic.List[object]
        foreach ($row in $rows) {
            foreach ($value in $values) {
                $newRow = [ordered]@{}
                foreach ($existingKey in $row.Keys) { $newRow[$existingKey] = $row[$existingKey] }
                $newRow[$key] = $value
                $expanded.Add($newRow)
            }
        }
        $rows = $expanded
    }

    return , $rows
}

function Remove-ExcludedCombinations {
    <#
        .SYNOPSIS
        Drops any row that matches every key/value pair of at least one
        exclude rule (a rule with keys not present on a row never matches it).
    #>
    param(
        [Parameter(Mandatory)]
        [array]$Rows,
        [array]$Excludes = @()
    )

    if (-not $Excludes -or $Excludes.Count -eq 0) {
        return , $Rows
    }

    $kept = New-Object System.Collections.Generic.List[object]
    foreach ($row in $Rows) {
        $excluded = $false
        foreach ($rule in $Excludes) {
            $ruleKeys = @($rule.Keys)
            $allMatch = $true
            foreach ($key in $ruleKeys) {
                if (-not $row.Contains($key) -or $row[$key] -ne $rule[$key]) {
                    $allMatch = $false
                    break
                }
            }
            if ($allMatch -and $ruleKeys.Count -gt 0) {
                $excluded = $true
                break
            }
        }
        if (-not $excluded) { $kept.Add($row) }
    }

    return , $kept
}

function Merge-IncludedCombinations {
    <#
        .SYNOPSIS
        Applies GitHub Actions include semantics: if an include rule's
        values match an existing row on every axis key the rule specifies,
        the rule's remaining keys are merged onto that row. Otherwise the
        rule is appended as a brand new row.
    #>
    param(
        [Parameter(Mandatory)]
        [array]$Rows,
        [array]$Includes = @(),
        [array]$AxisKeys = @()
    )

    $result = New-Object System.Collections.Generic.List[object]
    foreach ($row in $Rows) { $result.Add($row) }

    foreach ($rule in $Includes) {
        $ruleKeys = @($rule.Keys)
        $matchKeys = $ruleKeys | Where-Object { $AxisKeys -contains $_ }

        $matched = $false
        if ($matchKeys.Count -gt 0) {
            foreach ($row in $result) {
                $allMatch = $true
                foreach ($key in $matchKeys) {
                    if (-not $row.Contains($key) -or $row[$key] -ne $rule[$key]) {
                        $allMatch = $false
                        break
                    }
                }
                if ($allMatch) {
                    foreach ($key in $ruleKeys) { $row[$key] = $rule[$key] }
                    $matched = $true
                }
            }
        }

        if (-not $matched) {
            $newRow = [ordered]@{}
            foreach ($key in $ruleKeys) { $newRow[$key] = $rule[$key] }
            $result.Add($newRow)
        }
    }

    return , $result
}

function Test-MatrixSizeLimit {
    <#
        .SYNOPSIS
        Throws a terminating error if the row count exceeds MaxSize.
    #>
    param(
        [Parameter(Mandatory)]
        [array]$Rows,
        [Parameter(Mandatory)]
        [int]$MaxSize
    )

    if ($Rows.Count -gt $MaxSize) {
        throw "Generated matrix size ($($Rows.Count)) exceeds the maximum allowed size ($MaxSize)."
    }
}

function ConvertTo-PlainHashtable {
    <#
        .SYNOPSIS
        Converts a PSCustomObject (as produced by ConvertFrom-Json) into an
        ordered hashtable of scalar/array values, one level deep.
    #>
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $InputObject
    )

    $hash = [ordered]@{}
    if ($null -eq $InputObject) { return $hash }

    foreach ($property in $InputObject.PSObject.Properties) {
        $hash[$property.Name] = $property.Value
    }
    return $hash
}

function New-BuildMatrix {
    <#
        .SYNOPSIS
        Builds a full GitHub Actions strategy object (matrix, max-parallel,
        fail-fast) from a config object, applying exclude/include rules and
        validating the result against a maximum matrix size.

        .PARAMETER Config
        A PSCustomObject (typically from ConvertFrom-Json) with an optional
        shape:
          matrix:      { <axisName>: [values...], ... }  (required, non-empty)
          include:     [ { <key>: <value>, ... }, ... ]
          exclude:     [ { <key>: <value>, ... }, ... ]
          maxParallel: <int>
          failFast:    <bool>   (defaults to $true)
          maxSize:     <int>    (defaults to 256)
    #>
    param(
        [Parameter(Mandatory)]
        $Config
    )

    $matrixSpec = ConvertTo-PlainHashtable -InputObject $Config.matrix
    if ($matrixSpec.Count -eq 0) {
        throw "Config is missing a non-empty 'matrix' section describing at least one axis."
    }

    $axes = [ordered]@{}
    foreach ($key in $matrixSpec.Keys) {
        $values = @($matrixSpec[$key])
        if ($values.Count -eq 0) {
            throw "Matrix axis '$key' must contain at least one value."
        }
        $axes[$key] = $values
    }
    $axisKeys = @($axes.Keys)

    $rows = Get-CartesianProduct -Axes $axes

    $excludes = @()
    if ($Config.PSObject.Properties.Name -contains 'exclude' -and $Config.exclude) {
        $excludes = @($Config.exclude | ForEach-Object { ConvertTo-PlainHashtable -InputObject $_ })
    }
    $rows = Remove-ExcludedCombinations -Rows $rows -Excludes $excludes

    $includes = @()
    if ($Config.PSObject.Properties.Name -contains 'include' -and $Config.include) {
        $includes = @($Config.include | ForEach-Object { ConvertTo-PlainHashtable -InputObject $_ })
    }
    $rows = Merge-IncludedCombinations -Rows $rows -Includes $includes -AxisKeys $axisKeys

    $maxSize = 256
    if ($Config.PSObject.Properties.Name -contains 'maxSize' -and $Config.maxSize) {
        $maxSize = [int]$Config.maxSize
    }
    Test-MatrixSizeLimit -Rows $rows -MaxSize $maxSize

    $failFast = $true
    if ($Config.PSObject.Properties.Name -contains 'failFast') {
        $failFast = [bool]$Config.failFast
    }

    $result = [ordered]@{
        matrix    = [ordered]@{ include = @($rows | ForEach-Object { [PSCustomObject]$_ }) }
        'fail-fast' = $failFast
    }

    if ($Config.PSObject.Properties.Name -contains 'maxParallel' -and $Config.maxParallel) {
        $result['max-parallel'] = [int]$Config.maxParallel
    }

    return [PSCustomObject]$result
}

Export-ModuleMember -Function Get-CartesianProduct, Remove-ExcludedCombinations, Merge-IncludedCombinations, Test-MatrixSizeLimit, New-BuildMatrix, ConvertTo-PlainHashtable
