# LabelAssigner.psm1
# Assigns GitHub PR labels to a set of changed file paths based on a
# configurable list of glob-pattern -> label rules, with support for
# multiple labels per file and priority-based conflict resolution.

function ConvertTo-GlobRegex {
    <#
        Converts a glob pattern (supporting *, ?, and **) into an anchored,
        case-insensitive regex that matches a forward-slash-normalized path.
        - "**" matches any sequence of characters, including "/".
        - "*"  matches any sequence of characters except "/".
        - "?"  matches exactly one character except "/".
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Pattern
    )

    $normalized = $Pattern -replace '\\', '/'
    $sb = [System.Text.StringBuilder]::new('^')
    $i = 0
    while ($i -lt $normalized.Length) {
        $c = $normalized[$i]
        if ($c -eq '*' -and $i + 1 -lt $normalized.Length -and $normalized[$i + 1] -eq '*') {
            [void]$sb.Append('.*')
            $i += 2
        }
        elseif ($c -eq '*') {
            [void]$sb.Append('[^/]*')
            $i += 1
        }
        elseif ($c -eq '?') {
            [void]$sb.Append('[^/]')
            $i += 1
        }
        else {
            [void]$sb.Append([regex]::Escape([string]$c))
            $i += 1
        }
    }
    [void]$sb.Append('$')
    return $sb.ToString()
}

function Test-GlobMatch {
    <#
        Returns $true when Path matches the glob Pattern. Comparison is
        case-insensitive and treats backslashes as forward slashes so the
        same rules work regardless of OS path separators.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Pattern
    )

    $normalizedPath = $Path -replace '\\', '/'
    $regex = ConvertTo-GlobRegex -Pattern $Pattern
    return [regex]::IsMatch($normalizedPath, $regex, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
}

function Import-LabelRules {
    <#
        Loads and validates label rules from a JSON config file. Each rule
        requires "pattern" and "label"; "priority" defaults to 0 and
        "group" (optional) marks mutually-exclusive rule sets.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Label rules config not found at '$Path'."
    }

    try {
        $raw = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    }
    catch {
        throw "Failed to parse label rules config '$Path' as JSON: $($_.Exception.Message)"
    }

    if (-not $raw) {
        throw "Label rules config '$Path' is empty."
    }

    $rules = @()
    $index = 0
    foreach ($entry in $raw) {
        $index++
        if (-not $entry.pattern) {
            throw "Rule #$index in '$Path' is missing required field 'pattern'."
        }
        if (-not $entry.label) {
            throw "Rule #$index in '$Path' is missing required field 'label'."
        }
        $priority = 0
        if ($null -ne $entry.priority) { $priority = [int]$entry.priority }
        $group = $null
        if ($entry.PSObject.Properties.Name -contains 'group') { $group = $entry.group }

        $rules += [PSCustomObject]@{
            Pattern  = [string]$entry.pattern
            Label    = [string]$entry.label
            Priority = $priority
            Group    = $group
        }
    }

    return $rules
}

function Resolve-FileLabels {
    <#
        Determines the labels that apply to a single file given a set of
        rules. Rules with no Group each contribute their label
        independently. Rules that share a Group are mutually exclusive:
        only the highest-Priority matching rule in that group contributes
        its label (ties broken by rule order).
    #>
    param(
        [Parameter(Mandatory)]
        [string]$File,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Rules
    )

    $matched = @($Rules | Where-Object { Test-GlobMatch -Path $File -Pattern $_.Pattern })
    if ($matched.Count -eq 0) { return @() }

    $labels = [System.Collections.Generic.List[string]]::new()

    # Ungrouped rules all contribute.
    foreach ($rule in ($matched | Where-Object { -not $_.Group })) {
        if (-not $labels.Contains($rule.Label)) { [void]$labels.Add($rule.Label) }
    }

    # Grouped rules: highest priority wins per group.
    $grouped = $matched | Where-Object { $_.Group } | Group-Object -Property Group
    foreach ($g in $grouped) {
        $winner = $g.Group | Sort-Object -Property Priority -Descending | Select-Object -First 1
        if (-not $labels.Contains($winner.Label)) { [void]$labels.Add($winner.Label) }
    }

    return $labels.ToArray()
}

function Get-PRLabels {
    <#
        Computes the final, de-duplicated, sorted set of labels for a list
        of changed files given a set of rules.
    #>
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Files,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Rules
    )

    $allLabels = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($file in $Files) {
        foreach ($label in (Resolve-FileLabels -File $file -Rules $Rules)) {
            [void]$allLabels.Add($label)
        }
    }

    return @($allLabels | Sort-Object)
}

Export-ModuleMember -Function ConvertTo-GlobRegex, Test-GlobMatch, Import-LabelRules, Resolve-FileLabels, Get-PRLabels
