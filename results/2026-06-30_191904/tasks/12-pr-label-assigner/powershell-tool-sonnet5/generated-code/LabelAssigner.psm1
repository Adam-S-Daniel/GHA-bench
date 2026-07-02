# LabelAssigner.psm1
# Core engine for assigning PR labels based on configurable path-to-label
# glob rules. Pure functions only (no I/O) so they are trivially testable;
# file/JSON handling lives in Assign-PrLabels.ps1.

function ConvertTo-GlobRegex {
    <#
    Converts a glob pattern into an anchored .NET regex string.
      **   matches any number of characters, including '/', across path segments
      *    matches any characters *except* '/' (stays within one path segment)
      ?    matches exactly one character except '/'
    Everything else is treated as a literal and regex-escaped.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Glob
    )

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append('^')
    $i = 0
    $len = $Glob.Length
    while ($i -lt $len) {
        $c = $Glob[$i]
        if ($c -eq '*' -and ($i + 1) -lt $len -and $Glob[$i + 1] -eq '*') {
            # '**' consumes any number of path segments. If it's immediately
            # followed by '/', that slash is optional (so 'docs/**' also
            # matches files directly inside docs/, not just nested ones).
            if (($i + 2) -lt $len -and $Glob[$i + 2] -eq '/') {
                [void]$sb.Append('(?:.*/)?')
                $i += 3
            }
            else {
                [void]$sb.Append('.*')
                $i += 2
            }
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
    Tests whether a file path matches a glob pattern.
    Patterns containing '/' are anchored to the full relative path.
    Patterns with no '/' match the file's leaf name at any depth
    (gitignore-style), so '*.md' matches both 'readme.md' and 'docs/readme.md'.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Pattern
    )

    $normalizedPath = $Path -replace '\\', '/'
    $normalizedPattern = $Pattern -replace '\\', '/'

    if ($normalizedPattern -notmatch '/') {
        $candidates = @($normalizedPath, (Split-Path -Path $normalizedPath -Leaf))
    }
    else {
        $candidates = @($normalizedPath)
    }

    $regex = ConvertTo-GlobRegex -Glob $normalizedPattern
    foreach ($candidate in $candidates) {
        if ($candidate -match $regex) {
            return $true
        }
    }
    return $false
}

function New-LabelRule {
    <#
    Constructs a validated label rule. Rules are matched in priority order
    when they belong to the same ExclusiveGroup (see Get-PrLabels); rules
    with no ExclusiveGroup are always independently applied.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Pattern,

        [Parameter(Mandatory)]
        [string]$Label,

        [int]$Priority = 0,

        [string]$ExclusiveGroup = $null
    )

    if ([string]::IsNullOrWhiteSpace($Pattern)) {
        throw "Invalid label rule: 'Pattern' cannot be empty."
    }
    if ([string]::IsNullOrWhiteSpace($Label)) {
        throw "Invalid label rule: 'Label' cannot be empty."
    }

    [PSCustomObject]@{
        Pattern        = $Pattern
        Label          = $Label
        Priority       = $Priority
        ExclusiveGroup = $ExclusiveGroup
    }
}

function Import-LabelRules {
    <#
    Loads label rules from a JSON file. The file must contain an array of
    objects, each with at least 'Pattern' and 'Label'; 'Priority' (default 0)
    and 'ExclusiveGroup' (default $null) are optional.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        throw "Label rules file not found: '$Path'"
    }

    try {
        $raw = Get-Content -Path $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Failed to parse label rules file '$Path': $($_.Exception.Message)"
    }

    if (-not $raw) {
        throw "Label rules file '$Path' does not contain any rules."
    }

    $rules = @()
    foreach ($item in @($raw)) {
        if (-not $item.PSObject.Properties.Match('Pattern').Count) {
            throw "Invalid rule entry in '$Path': each rule requires 'Pattern' and 'Label' properties. Offending entry: $($item | ConvertTo-Json -Compress)"
        }
        if (-not $item.PSObject.Properties.Match('Label').Count) {
            throw "Invalid rule entry in '$Path': each rule requires 'Pattern' and 'Label' properties. Offending entry: $($item | ConvertTo-Json -Compress)"
        }

        $priority = if ($item.PSObject.Properties.Match('Priority').Count) { [int]$item.Priority } else { 0 }
        $exclusiveGroup = if ($item.PSObject.Properties.Match('ExclusiveGroup').Count) { $item.ExclusiveGroup } else { $null }

        $rules += New-LabelRule -Pattern $item.Pattern -Label $item.Label -Priority $priority -ExclusiveGroup $exclusiveGroup
    }

    return $rules
}

function Get-PrLabels {
    <#
    Computes the final label set for a list of changed files against a set
    of rules.

    Multiple labels per file: every matching rule contributes its label,
    except rules that share an ExclusiveGroup, which compete with each
    other for that one file.

    Priority ordering when rules conflict: within a given (file,
    ExclusiveGroup) pair, only the matching rule with the highest Priority
    contributes its label (ties broken alphabetically by Label, for
    deterministic output). Rules with no ExclusiveGroup never conflict with
    anything and always contribute when they match.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$ChangedFiles,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Rules
    )

    foreach ($rule in $Rules) {
        foreach ($propertyName in 'Pattern', 'Label') {
            if (-not $rule.PSObject.Properties.Match($propertyName).Count) {
                throw "Invalid label rule: missing required property '$propertyName'. Rule: $($rule | ConvertTo-Json -Compress)"
            }
        }
    }

    $resultLabels = [System.Collections.Generic.HashSet[string]]::new()

    foreach ($file in $ChangedFiles) {
        if ([string]::IsNullOrWhiteSpace($file)) {
            throw 'Changed file entries cannot be null or empty.'
        }

        $matchedRules = @($Rules | Where-Object { Test-GlobMatch -Path $file -Pattern $_.Pattern })
        if ($matchedRules.Count -eq 0) {
            continue
        }

        $independentMatches = @($matchedRules | Where-Object { -not $_.ExclusiveGroup })
        foreach ($rule in $independentMatches) {
            [void]$resultLabels.Add($rule.Label)
        }

        $exclusiveMatches = @($matchedRules | Where-Object { $_.ExclusiveGroup })
        $groups = $exclusiveMatches | Group-Object -Property ExclusiveGroup
        foreach ($group in $groups) {
            $winner = $group.Group |
                Sort-Object -Property @{Expression = 'Priority'; Descending = $true }, @{Expression = 'Label'; Descending = $false } |
                Select-Object -First 1
            [void]$resultLabels.Add($winner.Label)
        }
    }

    return @($resultLabels | Sort-Object)
}

Export-ModuleMember -Function Test-GlobMatch, ConvertTo-GlobRegex, New-LabelRule, Import-LabelRules, Get-PrLabels
