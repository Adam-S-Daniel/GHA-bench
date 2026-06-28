# PRLabelAssigner.psm1
# Core logic for assigning labels to a PR based on its changed files.
#
# This module is built up incrementally via red/green TDD. Functions are added
# one at a time, each driven by a failing Pester test.

function ConvertTo-LabelRegex {
    <#
    .SYNOPSIS
        Convert a glob pattern into an anchored .NET regular expression string.
    .DESCRIPTION
        Supported glob syntax:
          **  matches any run of characters, including path separators (/)
          *   matches any run of characters except the path separator (/)
          ?   matches exactly one character except the path separator (/)
          .   is treated literally (escaped)
        All other regex metacharacters are escaped so they match literally.
        The result is anchored with ^ and $ so the whole string must match.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Pattern
    )

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append('^')

    $chars = $Pattern.ToCharArray()
    for ($i = 0; $i -lt $chars.Length; $i++) {
        $c = $chars[$i]
        switch ($c) {
            '*' {
                if ($i + 1 -lt $chars.Length -and $chars[$i + 1] -eq '*') {
                    # '**' -> match across directory separators.
                    [void]$sb.Append('.*')
                    $i++   # consume the second '*'
                }
                else {
                    # '*' -> match within a single path segment.
                    [void]$sb.Append('[^/]*')
                }
            }
            '?' { [void]$sb.Append('[^/]') }
            default {
                # Escape any character that is special to regex so it matches literally.
                [void]$sb.Append([regex]::Escape([string]$c))
            }
        }
    }

    [void]$sb.Append('$')
    return $sb.ToString()
}

function Test-PathPattern {
    <#
    .SYNOPSIS
        Test whether a file path matches a glob pattern.
    .DESCRIPTION
        Matching semantics:
          * If the pattern contains a '/', it is matched against the full,
            normalised path (e.g. 'src/api/**' against 'src/api/users.js').
          * If the pattern contains no '/', it is matched against the file's
            basename only, so 'name'-style patterns like '*.test.*' apply
            anywhere in the tree.
        Matching is case-insensitive, mirroring common labeler behaviour.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Pattern
    )

    # Normalise Windows-style separators so rules are written with '/'.
    $normalisedPath = $Path -replace '\\', '/'

    $target = if ($Pattern -like '*/*') {
        $normalisedPath
    }
    else {
        # No directory component in the pattern -> compare against the basename.
        $normalisedPath -replace '.*/', ''
    }

    $regex = ConvertTo-LabelRegex -Pattern $Pattern
    return [regex]::IsMatch($target, $regex, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
}

function ConvertTo-NormalisedRule {
    <#
    .SYNOPSIS
        Validate a single rule object and normalise it into a predictable shape.
    .DESCRIPTION
        Accepts either a hashtable or a PSCustomObject (e.g. from JSON) with:
          pattern  (required, non-empty string)
          labels   (required, string or array of non-empty strings)
          priority (optional, integer; defaults to 0)
        Throws a descriptive error if the rule is malformed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Rule,

        [int] $Index = 0
    )

    # Read a property in a way that works for both hashtables and PSCustomObjects.
    $get = {
        param($obj, $name)
        if ($obj -is [System.Collections.IDictionary]) {
            if ($obj.Contains($name)) { return $obj[$name] }
            return $null
        }
        return $obj.PSObject.Properties[$name].Value
    }

    $pattern = & $get $Rule 'pattern'
    if ([string]::IsNullOrWhiteSpace([string]$pattern)) {
        throw "Rule #$Index is invalid: 'pattern' is required and must be a non-empty string."
    }

    $rawLabels = & $get $Rule 'labels'
    if ($null -eq $rawLabels) {
        throw "Rule #$Index ('$pattern') is invalid: 'labels' is required."
    }
    # Accept a single label string as a convenience.
    $labels = @($rawLabels) | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    if ($labels.Count -eq 0) {
        throw "Rule #$Index ('$pattern') is invalid: 'labels' must contain at least one non-empty label."
    }

    $priority = 0
    $rawPriority = & $get $Rule 'priority'
    if ($null -ne $rawPriority -and "$rawPriority" -ne '') {
        $parsed = 0
        if (-not [int]::TryParse([string]$rawPriority, [ref]$parsed)) {
            throw "Rule #$Index ('$pattern') is invalid: 'priority' must be an integer, got '$rawPriority'."
        }
        $priority = $parsed
    }

    return [pscustomobject]@{
        Pattern  = [string]$pattern
        Labels   = $labels
        Priority = $priority
    }
}

function Get-PRLabels {
    <#
    .SYNOPSIS
        Compute the final set of labels for a set of changed files.
    .DESCRIPTION
        Each rule maps a glob pattern to one or more labels and an optional
        priority. A file may match several rules (multiple labels per file),
        and labels are unioned and de-duplicated across all changed files.

        The returned set is ordered by descending rule priority, then by label
        name, so the most significant labels come first and the order is stable.

        With -FirstMatchWins, conflicting rules are resolved per file: only the
        single highest-priority matching rule contributes its labels for that
        file (ties broken by the rule's position in the list).
    .OUTPUTS
        [string[]] the ordered, de-duplicated label set.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $ChangedFiles,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        $Rules,

        [switch] $FirstMatchWins
    )

    # Validate/normalise rules up front so a bad config fails fast and clearly.
    $normalised = @()
    $i = 0
    foreach ($rule in @($Rules)) {
        $normalised += ConvertTo-NormalisedRule -Rule $rule -Index $i
        $i++
    }

    # Map of label -> highest priority observed, used for ordering and dedup.
    $labelPriority = @{}

    foreach ($file in $ChangedFiles) {
        if ([string]::IsNullOrWhiteSpace($file)) { continue }

        # Find all rules that match this file, most important first.
        $matches = $normalised |
            Where-Object { Test-PathPattern -Path $file -Pattern $_.Pattern } |
            Sort-Object -Property Priority -Descending

        if (-not $matches) { continue }

        $contributing = if ($FirstMatchWins) { @($matches)[0] } else { $matches }

        foreach ($rule in $contributing) {
            foreach ($label in $rule.Labels) {
                if (-not $labelPriority.ContainsKey($label) -or $rule.Priority -gt $labelPriority[$label]) {
                    $labelPriority[$label] = $rule.Priority
                }
            }
        }
    }

    # Order by descending priority, then alphabetically for a stable result.
    $ordered = $labelPriority.Keys |
        Sort-Object -Property @{ Expression = { $labelPriority[$_] }; Descending = $true }, @{ Expression = { $_ }; Descending = $false }

    return @($ordered)
}

function Import-LabelRules {
    <#
    .SYNOPSIS
        Load label rules from a JSON configuration file.
    .DESCRIPTION
        The file may be either:
          * an object with a top-level "rules" array, or
          * a bare top-level array of rule objects.
        Each rule has the shape consumed by Get-PRLabels
        ({ pattern, labels, priority }). The rules are validated as they load,
        so malformed configs fail fast with a clear message.
    .OUTPUTS
        [object[]] an array of normalised rule objects.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Label rules file not found: '$Path'."
    }

    $raw = Get-Content -LiteralPath $Path -Raw
    try {
        $config = $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Failed to parse label rules file '$Path': $($_.Exception.Message)"
    }

    # Accept either { "rules": [...] } or a bare [...] array. Note that
    # ConvertFrom-Json collapses a single-element array to a scalar object, so we
    # normalise with @(...) below rather than relying on the value being an array.
    $rawRules =
        if ($config -isnot [System.Array] -and $null -ne $config.PSObject.Properties['rules']) {
            $config.rules
        }
        else {
            $config
        }

    # Normalise (and thereby validate) every rule before returning.
    $result = @()
    $i = 0
    foreach ($rule in @($rawRules)) {
        $result += ConvertTo-NormalisedRule -Rule $rule -Index $i
        $i++
    }
    return $result
}

# Export the public surface of the module.
Export-ModuleMember -Function ConvertTo-LabelRegex, Test-PathPattern, ConvertTo-NormalisedRule, Get-PRLabels, Import-LabelRules
