# LabelAssigner.ps1
# Applies labels to a PR based on a configurable list of glob-pattern -> label
# rules, given a list of changed file paths.

function Convert-GlobToRegex {
    <#
        Converts a simple glob pattern (supporting *, ** and ?) into an
        anchored regular expression usable for matching file paths.
    #>
    param(
        [Parameter(Mandatory)]
        [string] $Pattern
    )

    # Escape regex special characters first, then re-introduce glob semantics
    # using placeholder tokens so the escaping of '*' and '?' doesn't collide.
    $escaped = [regex]::Escape($Pattern)

    # [regex]::Escape turns '*' into '\*', '?' into '\?'. Replace the escaped
    # double-star first (matches across path separators), then single-star
    # (matches within a path segment), then '?' (single char).
    $escaped = $escaped -replace '\\\*\\\*', '§§DOUBLESTAR§§'
    $escaped = $escaped -replace '\\\*', '§§STAR§§'
    $escaped = $escaped -replace '\\\?', '§§QMARK§§'

    $escaped = $escaped -replace '§§DOUBLESTAR§§', '.*'
    $escaped = $escaped -replace '§§STAR§§', '[^/]*'
    $escaped = $escaped -replace '§§QMARK§§', '.'

    return "^$escaped$"
}

function Test-GlobMatch {
    <#
        Tests whether a given file path matches a glob pattern.
    #>
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Pattern
    )

    $regex = Convert-GlobToRegex -Pattern $Pattern

    if ($Path -match $regex) {
        return $true
    }

    # Patterns without a path separator (e.g. "*.test.*") are treated like
    # gitignore basename patterns: they match the file's basename regardless
    # of which directory it lives in.
    if ($Pattern -notmatch '/') {
        $baseName = Split-Path -Path $Path -Leaf
        return $baseName -match $regex
    }

    return $false
}

function Get-PrLabels {
    <#
        Given a list of changed file paths and a list of rules
        (@{ Pattern = <glob>; Label = <string>; Priority = <int> }),
        returns the sorted, de-duplicated set of labels that apply.

        Priority is used only when rules conflict, i.e. when the caller
        expects a single label out of a mutually-exclusive group; by default
        all matching labels across all matching rules are returned, ordered
        by descending priority then by label name.
    #>
    param(
        [Parameter(Mandatory)]
        [string[]] $ChangedFiles,

        [Parameter(Mandatory)]
        [array] $Rules
    )

    if (-not $ChangedFiles -or $ChangedFiles.Count -eq 0) {
        throw "ChangedFiles must contain at least one file path."
    }

    if (-not $Rules -or $Rules.Count -eq 0) {
        throw "Rules must contain at least one label rule."
    }

    $matchedLabels = New-Object System.Collections.Generic.List[object]

    foreach ($rule in $Rules) {
        if (-not $rule.ContainsKey('Pattern') -or -not $rule.ContainsKey('Label')) {
            throw "Each rule must define a 'Pattern' and a 'Label'."
        }

        $priority = if ($rule.ContainsKey('Priority')) { $rule.Priority } else { 0 }

        foreach ($file in $ChangedFiles) {
            if (Test-GlobMatch -Path $file -Pattern $rule.Pattern) {
                $matchedLabels.Add([pscustomobject]@{
                    Label    = $rule.Label
                    Priority = $priority
                })
                break
            }
        }
    }

    $labels = $matchedLabels |
        Sort-Object -Property @{Expression = 'Priority'; Descending = $true}, Label |
        Select-Object -ExpandProperty Label -Unique

    return $labels
}
