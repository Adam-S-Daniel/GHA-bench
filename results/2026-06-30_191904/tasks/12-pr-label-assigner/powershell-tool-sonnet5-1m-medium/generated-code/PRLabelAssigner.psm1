<#
    PRLabelAssigner.psm1

    Core engine for mapping a PR's changed files to labels using
    configurable glob-pattern rules. Three public functions:

      ConvertTo-GlobRegex  - turns a glob pattern into an anchored regex
      Test-GlobMatch       - tests one path against one glob pattern
      Get-PRLabels         - resolves the full label set for a set of
                              changed files against a rule list

    Glob semantics (deliberately simple and predictable):
      *   matches any run of characters except '/'   (one path segment)
      **  matches any run of characters, including '/' (crosses directories)
      ?   matches exactly one character except '/'
      A pattern with no '/' at all (e.g. "*.test.*") is also matched against
      just the file's basename, so it behaves like a gitignore-style rule
      that applies at any depth.
#>

function ConvertTo-GlobRegex {
    <#
        Converts a glob pattern into an anchored, case-insensitive regex
        string. Kept separate from Test-GlobMatch so the conversion itself
        is independently testable/inspectable.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Pattern
    )

    $normalized = $Pattern -replace '\\', '/'
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append('(?i)^')

    $i = 0
    while ($i -lt $normalized.Length) {
        $c = $normalized[$i]
        if ($c -eq '*') {
            if (($i + 1) -lt $normalized.Length -and $normalized[$i + 1] -eq '*') {
                [void]$sb.Append('.*')
                $i += 2
            }
            else {
                [void]$sb.Append('[^/]*')
                $i += 1
            }
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
        Tests whether a (relative, forward-slash or backslash) file path
        matches a single glob pattern.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Pattern
    )

    $normalizedPath = $Path -replace '\\', '/'
    $regexString = ConvertTo-GlobRegex -Pattern $Pattern

    if ($normalizedPath -match $regexString) {
        return $true
    }

    # A slash-less pattern is a basename pattern: it should match regardless
    # of which directory the file lives in.
    if ($Pattern -notmatch '/') {
        $baseName = Split-Path -Leaf $normalizedPath
        if ($baseName -match $regexString) {
            return $true
        }
    }

    return $false
}

function Get-PRLabels {
    <#
        Resolves the final label set for a PR given its changed files and a
        list of path-to-label rules.

        Each rule is an object with:
          Pattern         (required) glob pattern, matched via Test-GlobMatch
          Label           (required) label to apply when the pattern matches
          Priority        (optional, default 0) used to break ties within
                           an ExclusiveGroup
          ExclusiveGroup  (optional) rules sharing the same ExclusiveGroup
                           name compete for a single file: only the
                           matching rule with the highest Priority
                           contributes its label for that file. Rules
                           without an ExclusiveGroup never compete with
                           anything - every matching one contributes.

        Returns a sorted array of unique labels (the union across all
        changed files).
    #>
    param(
        [Parameter(Mandatory)]
        [string[]]$ChangedFiles,

        [Parameter(Mandatory)]
        [object[]]$Rules
    )

    if (-not $ChangedFiles -or $ChangedFiles.Count -eq 0) {
        throw "Get-PRLabels: ChangedFiles must contain at least one file path."
    }

    foreach ($rule in $Rules) {
        if (-not $rule.Pattern) {
            throw "Get-PRLabels: every rule requires a non-empty Pattern property."
        }
        if (-not $rule.Label) {
            throw "Get-PRLabels: every rule requires a non-empty Label property."
        }
    }

    $labelSet = [System.Collections.Generic.HashSet[string]]::new()

    foreach ($file in $ChangedFiles) {
        $matchingRules = @($Rules | Where-Object { Test-GlobMatch -Path $file -Pattern $_.Pattern })
        if ($matchingRules.Count -eq 0) {
            continue
        }

        # Rules without an ExclusiveGroup each get a unique key so they
        # never compete with one another; rules sharing a group name compete
        # for the single highest-Priority label.
        $groups = $matchingRules | Group-Object -Property {
            if ($_.ExclusiveGroup) { "group:$($_.ExclusiveGroup)" } else { "rule:$([guid]::NewGuid())" }
        }

        foreach ($group in $groups) {
            $winner = $group.Group | Sort-Object -Property @{ Expression = { [int]($_.Priority ?? 0) } } -Descending | Select-Object -First 1
            [void]$labelSet.Add($winner.Label)
        }
    }

    return @($labelSet | Sort-Object)
}

Export-ModuleMember -Function ConvertTo-GlobRegex, Test-GlobMatch, Get-PRLabels
