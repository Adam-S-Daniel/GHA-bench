<#
    PRLabelAssigner.psm1

    A small, dependency-free PowerShell module that assigns labels to a set of
    changed file paths (e.g. the files touched by a pull request) based on a list
    of path-to-label rules.

    Design overview
    ---------------
    A *rule* is an object with three fields:
        pattern  - a glob describing which files it applies to (e.g. 'docs/**')
        label    - the label to attach when the glob matches (e.g. 'documentation')
        priority - an integer; LOWER numbers are MORE important and sort first

    Glob semantics (gitignore-flavoured, deliberately predictable):
        **        matches any number of characters, including '/' (crosses dirs)
        *         matches any run of characters except '/' (stays in one segment)
        ?         matches exactly one character except '/'
        a pattern with NO '/' is matched against the file's basename, so a rule
        like '*.test.*' tags test files anywhere in the tree.

    All comparisons are case-insensitive, which matches how Git/GitHub treat
    most label-config tooling and avoids surprising misses on case-only diffs.
#>

Set-StrictMode -Version Latest

function Convert-GlobToRegex {
    <#
        .SYNOPSIS
            Convert a glob pattern into an anchored .NET regular expression string.
        .DESCRIPTION
            The conversion walks the glob character by character so that regex
            metacharacters in the literal portions of the path are escaped, while
            the glob wildcards (** , * and ?) are translated to their regex
            equivalents. The result is anchored with ^...$ so callers get a full
            match rather than a substring match.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Glob
    )

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append('^')

    for ($i = 0; $i -lt $Glob.Length; $i++) {
        $c = $Glob[$i]
        switch ($c) {
            '*' {
                if ($i + 1 -lt $Glob.Length -and $Glob[$i + 1] -eq '*') {
                    # '**' -> match anything, including directory separators.
                    [void]$sb.Append('.*')
                    $i++  # consume the second '*'
                }
                else {
                    # single '*' -> match within a single path segment only.
                    [void]$sb.Append('[^/]*')
                }
            }
            '?' { [void]$sb.Append('[^/]') }
            default {
                # Escape any character that is special in regex so it matches literally.
                [void]$sb.Append([regex]::Escape([string]$c))
            }
        }
    }

    [void]$sb.Append('$')
    return $sb.ToString()
}

function Test-GlobMatch {
    <#
        .SYNOPSIS
            Test whether a single file path matches a glob pattern.
        .DESCRIPTION
            If the glob contains no '/', it is treated as a basename pattern and
            matched against the final path segment (gitignore behaviour). Otherwise
            it is matched against the full, normalised path. Matching is
            case-insensitive.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Glob
    )

    # Normalise Windows-style separators so rules are platform-agnostic.
    $normalisedPath = $Path -replace '\\', '/'

    $regex = Convert-GlobToRegex -Glob $Glob

    # Basename matching for slash-free patterns (e.g. '*.test.*').
    $target = if ($Glob -notmatch '/') {
        ($normalisedPath -split '/')[-1]
    }
    else {
        $normalisedPath
    }

    return [regex]::IsMatch($target, $regex, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
}

function Assert-ValidRule {
    <#
        .SYNOPSIS
            Validate a single rule object, throwing a meaningful error if malformed.
    #>
    param(
        [Parameter(Mandatory)]
        $Rule,

        [int] $Index
    )

    foreach ($field in 'pattern', 'label') {
        $hasField = $Rule.PSObject.Properties.Name -contains $field
        if (-not $hasField -or [string]::IsNullOrWhiteSpace([string]$Rule.$field)) {
            throw "Rule at index $Index is invalid: missing or empty required field '$field'."
        }
    }
}

function Get-PRLabels {
    <#
        .SYNOPSIS
            Resolve the final set of labels for a list of changed files.
        .DESCRIPTION
            Every changed file is tested against every rule. A matching rule
            contributes its label. The final set is de-duplicated and ordered by
            ascending rule priority (lower = more important); ties are broken
            alphabetically by label name so output is deterministic.
        .PARAMETER ChangedFiles
            The list of file paths touched by the PR.
        .PARAMETER Rules
            The path-to-label rules. Each rule must expose 'pattern', 'label' and
            (optionally) 'priority'.
        .OUTPUTS
            [string[]] the ordered, de-duplicated label set (empty if none match).
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $ChangedFiles,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Rules
    )

    # Fail fast on malformed rules so CI surfaces config bugs clearly.
    for ($i = 0; $i -lt $Rules.Count; $i++) {
        Assert-ValidRule -Rule $Rules[$i] -Index $i
    }

    # Track, per label, the best (lowest) priority any matching rule gave it.
    $bestPriority = @{}

    foreach ($file in $ChangedFiles) {
        if ([string]::IsNullOrWhiteSpace($file)) { continue }

        foreach ($rule in $Rules) {
            if (Test-GlobMatch -Path $file -Glob $rule.pattern) {
                # Default missing/blank priority to a large number (least important).
                $priority = 1000
                if ($rule.PSObject.Properties.Name -contains 'priority' -and
                    $null -ne $rule.priority -and "$($rule.priority)".Trim() -ne '') {
                    $priority = [int]$rule.priority
                }

                $label = [string]$rule.label
                if (-not $bestPriority.ContainsKey($label) -or $priority -lt $bestPriority[$label]) {
                    $bestPriority[$label] = $priority
                }
            }
        }
    }

    if ($bestPriority.Count -eq 0) {
        return @()
    }

    # Sort by priority ascending, then by label name for stable tie-breaking.
    $ordered = $bestPriority.Keys |
        Sort-Object @{ Expression = { $bestPriority[$_] } }, @{ Expression = { $_ } }

    return [string[]]$ordered
}

function Import-LabelRules {
    <#
        .SYNOPSIS
            Load label rules from a JSON file.
        .DESCRIPTION
            The file must contain a JSON array of objects with 'pattern', 'label'
            and 'priority' fields. Missing files and invalid JSON produce clear,
            actionable error messages.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Rules file not found: '$Path'."
    }

    $raw = Get-Content -LiteralPath $Path -Raw

    try {
        $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Rules file '$Path' does not contain valid JSON: $($_.Exception.Message)"
    }

    # Always return an array, even for a single-object file.
    return @($parsed)
}

Export-ModuleMember -Function Convert-GlobToRegex, Test-GlobMatch, Get-PRLabels, Import-LabelRules
