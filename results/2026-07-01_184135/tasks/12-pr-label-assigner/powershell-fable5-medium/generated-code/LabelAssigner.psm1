# LabelAssigner.psm1
#
# Core logic for the PR Label Assigner.
#
# Approach:
#   * Test-GlobMatch converts a glob pattern into an anchored .NET regex.
#     `**` crosses directory separators, `*` and `?` do not. A pattern with
#     no `/` is matched against the file's basename (like .gitignore), so
#     `*.test.*` tags test files anywhere in the tree.
#   * Rules are evaluated per file in descending Priority order. A rule can
#     be marked Exclusive, which stops lower-priority rules from labelling
#     that file — this is how conflicts are resolved deterministically.

function Convert-GlobToRegex {
    <#
    .SYNOPSIS
        Translates a glob pattern to an anchored regular expression string.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Pattern
    )

    $sb = [System.Text.StringBuilder]::new('^')
    $i = 0
    while ($i -lt $Pattern.Length) {
        $c = $Pattern[$i]
        switch ($c) {
            '*' {
                if ($i + 1 -lt $Pattern.Length -and $Pattern[$i + 1] -eq '*') {
                    # `**/` may match zero directories; a trailing/inner `**`
                    # matches anything including separators.
                    if ($i + 2 -lt $Pattern.Length -and $Pattern[$i + 2] -eq '/') {
                        [void]$sb.Append('(?:.*/)?')
                        $i += 3
                    }
                    else {
                        [void]$sb.Append('.*')
                        $i += 2
                    }
                }
                else {
                    [void]$sb.Append('[^/]*')
                    $i++
                }
            }
            '?' {
                [void]$sb.Append('[^/]')
                $i++
            }
            default {
                [void]$sb.Append([regex]::Escape([string]$c))
                $i++
            }
        }
    }
    [void]$sb.Append('$')
    return $sb.ToString()
}

function Test-GlobMatch {
    <#
    .SYNOPSIS
        Returns $true when a file path matches a glob pattern.
    .NOTES
        Patterns without a directory separator are matched against the
        basename of the path, so `*.test.*` matches `src/api/users.test.ts`.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Pattern
    )

    $subject = if ($Pattern.Contains('/')) { $Path } else { Split-Path -Leaf $Path }
    return [regex]::IsMatch($subject, (Convert-GlobToRegex -Pattern $Pattern))
}

function Resolve-LabelRule {
    <#
    .SYNOPSIS
        Validates one raw rule (hashtable or PSCustomObject) and normalises it
        into a canonical shape: Pattern, Labels[], Priority, Exclusive.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Rule,

        [Parameter(Mandatory)]
        [int]$Index
    )

    # Support both hashtables (tests) and PSCustomObjects (JSON config).
    $get = { param($name)
        if ($Rule -is [System.Collections.IDictionary]) { $Rule[$name] }
        else { $Rule.PSObject.Properties[$name].Value }
    }

    $pattern = & $get 'Pattern'
    if ([string]::IsNullOrWhiteSpace($pattern)) {
        throw "Rule #$Index is missing a 'Pattern'. Every rule needs a glob pattern such as 'docs/**'."
    }

    $labels = @(& $get 'Labels') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    if ($labels.Count -eq 0) {
        throw "Rule #$Index ('$pattern') must define at least one label in 'Labels'."
    }

    $priority = & $get 'Priority'

    [pscustomobject]@{
        Pattern   = [string]$pattern
        Labels    = @($labels | ForEach-Object { [string]$_ })
        Priority  = if ($null -ne $priority) { [int]$priority } else { 0 }
        Exclusive = [bool](& $get 'Exclusive')
    }
}

function Get-PRLabels {
    <#
    .SYNOPSIS
        Computes the final label set for a list of changed file paths.
    .DESCRIPTION
        For each file, rules are evaluated in descending Priority order
        (ties keep their declaration order). Every matching rule contributes
        its labels; if a matching rule is marked Exclusive, lower-priority
        rules are skipped for that file, which resolves conflicts such as
        'docs/internal/**' overriding 'docs/**'. The result is the sorted,
        de-duplicated union across all files.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$ChangedFiles,

        [Parameter(Mandatory)]
        [object[]]$Rules
    )

    $i = 0
    $normalized = @($Rules | ForEach-Object { $i++; Resolve-LabelRule -Rule $_ -Index $i }) |
        Sort-Object -Property @{ Expression = 'Priority'; Descending = $true } -Stable

    $labels = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($file in $ChangedFiles) {
        foreach ($rule in $normalized) {
            if (Test-GlobMatch -Path $file -Pattern $rule.Pattern) {
                foreach ($label in $rule.Labels) { [void]$labels.Add($label) }
                if ($rule.Exclusive) { break }  # conflict resolved: skip lower-priority rules
            }
        }
    }

    return @($labels) | Sort-Object
}

Export-ModuleMember -Function Test-GlobMatch, Convert-GlobToRegex, Get-PRLabels
