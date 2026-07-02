# PrLabelAssigner.psm1
# Assigns labels to a PR based on a set of glob-pattern -> label rules,
# applied to a list of changed file paths.

function Test-GlobMatch {
    <#
        Matches a single file path against a glob pattern.
        Supports '**' (any depth), '*' (single path segment / any chars
        within a segment) and '?' via .NET wildcard-to-regex translation.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Pattern
    )

    # Normalize path separators to forward slashes for consistent matching.
    $normalizedPath = $Path -replace '\\', '/'
    $normalizedPattern = $Pattern -replace '\\', '/'

    # A pattern with no '/' (e.g. '*.test.*') is a basename-style pattern:
    # match it against the file anywhere in the tree, not just at the root.
    if ($normalizedPattern -notmatch '/') {
        $normalizedPattern = "**/$normalizedPattern"
    }

    # Translate the glob pattern into a regex:
    #  '**' -> match anything (including '/')
    #  '*'  -> match anything except '/'
    #  '?'  -> match a single character except '/'
    $regexPattern = [regex]::Escape($normalizedPattern)
    # '**/' at the start means "optionally, any number of leading path segments".
    $regexPattern = $regexPattern -replace '^\\\*\\\*/', '(.*/)?'
    $regexPattern = $regexPattern -replace '\\\*\\\*', '§DOUBLESTAR§'
    $regexPattern = $regexPattern -replace '\\\*', '[^/]*'
    $regexPattern = $regexPattern -replace '\\\?', '[^/]'
    $regexPattern = $regexPattern -replace '§DOUBLESTAR§', '.*'

    return $normalizedPath -match "^$regexPattern$"
}

function Get-PrLabels {
    <#
        Given a list of changed file paths and a list of rules
        (@{ Pattern = '<glob>'; Label = '<label>'; Priority = <int>;
        Exclusive = <bool> }), returns the de-duplicated set of labels
        whose pattern matches at least one changed file.

        Rules marked Exclusive compete against each other: among all
        matching Exclusive rules, only the one with the lowest Priority
        number wins. Non-exclusive rules are always additive.
    #>
    param(
        [Parameter(Mandatory)][string[]]$ChangedFiles,
        [Parameter(Mandatory)][array]$Rules
    )

    if (-not $ChangedFiles -or $ChangedFiles.Count -eq 0) {
        throw "Get-PrLabels: ChangedFiles must contain at least one file path."
    }

    foreach ($rule in $Rules) {
        if (-not $rule.ContainsKey('Pattern') -or [string]::IsNullOrWhiteSpace($rule.Pattern)) {
            throw "Get-PrLabels: each rule must define a non-empty 'Pattern' property."
        }
        if (-not $rule.ContainsKey('Label') -or [string]::IsNullOrWhiteSpace($rule.Label)) {
            throw "Get-PrLabels: each rule must define a non-empty 'Label' property."
        }
    }

    $matchedRules = New-Object System.Collections.Generic.List[hashtable]

    foreach ($rule in $Rules) {
        foreach ($file in $ChangedFiles) {
            if (Test-GlobMatch -Path $file -Pattern $rule.Pattern) {
                $matchedRules.Add($rule)
                break
            }
        }
    }

    $resultLabels = New-Object System.Collections.Generic.List[string]

    # Non-exclusive matched rules are always added.
    foreach ($rule in $matchedRules) {
        if (-not $rule.ContainsKey('Exclusive') -or -not $rule.Exclusive) {
            if ($resultLabels -notcontains $rule.Label) {
                $resultLabels.Add($rule.Label)
            }
        }
    }

    # Among exclusive matched rules, only the lowest-Priority-number rule wins.
    $exclusiveMatches = $matchedRules | Where-Object { $_.ContainsKey('Exclusive') -and $_.Exclusive }
    if ($exclusiveMatches) {
        $winner = $exclusiveMatches | Sort-Object { $_.Priority } | Select-Object -First 1
        if ($resultLabels -notcontains $winner.Label) {
            $resultLabels.Add($winner.Label)
        }
    }

    return $resultLabels
}

function Import-PrLabelRules {
    <#
        Loads label rules from a JSON configuration file. Each entry
        must be an object with at least Pattern and Label properties,
        and may optionally include Priority and Exclusive.
    #>
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Import-PrLabelRules: configuration file not found at path '$Path'."
    }

    $jsonContent = Get-Content -LiteralPath $Path -Raw
    $parsed = $jsonContent | ConvertFrom-Json

    $rules = New-Object System.Collections.Generic.List[hashtable]
    foreach ($entry in $parsed) {
        $rule = @{
            Pattern = $entry.Pattern
            Label   = $entry.Label
        }
        if ($null -ne $entry.PSObject.Properties['Priority']) {
            $rule.Priority = $entry.Priority
        }
        if ($null -ne $entry.PSObject.Properties['Exclusive']) {
            $rule.Exclusive = [bool]$entry.Exclusive
        }
        $rules.Add($rule)
    }

    return $rules
}

Export-ModuleMember -Function Get-PrLabels, Test-GlobMatch, Import-PrLabelRules
