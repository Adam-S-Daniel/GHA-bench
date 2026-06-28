<#
.SYNOPSIS
    Assigns labels to a pull request based on its changed file paths and a set
    of configurable glob-pattern-to-label rules.

.DESCRIPTION
    This module is the engine behind a "PR labeler". Given:

      * a list of changed file paths (the PR's diff), and
      * a set of rules, each mapping one or more glob patterns to one or more
        labels (with an optional priority and an optional mutual-exclusion
        group),

    it produces the final, de-duplicated, priority-ordered set of labels.

    Design highlights
    -----------------
    * Glob support: '**' (globstar, crosses '/'), '*' (within a path segment),
      '?' (single char), and gitignore-style basename matching for slash-less
      patterns (so the classic example '*.test.*' matches a test file at any
      depth).
    * Multiple labels per file: labels are additive — every matching rule
      contributes, and the union is returned.
    * Priority ordering: the output is ordered by descending rule priority so
      the most significant labels come first.
    * Conflict resolution: rules may declare a 'group'. Within a group the
      labels are mutually exclusive — only the highest-priority matching rule's
      label(s) survive. This is how genuinely conflicting rules are resolved
      (e.g. a size/area taxonomy where a PR should carry exactly one value).

    The functions are intentionally small and pure so they can be unit-tested
    directly (see tests/PRLabelAssigner.Tests.ps1).
#>

Set-StrictMode -Version Latest

function Get-LabelRuleProperty {
    <#
    .SYNOPSIS
        Safely reads a property/key from either a hashtable or a PSCustomObject,
        returning a default when it is absent.

    .DESCRIPTION
        Rules can arrive either as hashtables (handy in unit tests) or as
        PSCustomObjects (the shape ConvertFrom-Json produces). Under
        Set-StrictMode, blindly touching a missing property on a PSCustomObject
        throws. This helper normalises access across both shapes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowNull()] $InputObject,
        [Parameter(Mandatory)] [string] $Name,
        $Default = $null
    )

    if ($null -eq $InputObject) { return $Default }

    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) { return $InputObject[$Name] }
        return $Default
    }

    $prop = $InputObject.PSObject.Properties[$Name]
    if ($prop) { return $prop.Value }
    return $Default
}

function ConvertTo-LabelGlobRegex {
    <#
    .SYNOPSIS
        Converts a glob pattern into an anchored .NET regex string.

    .DESCRIPTION
        Translation rules (scanned left-to-right so we never corrupt the regex
        we are emitting):

          **/  -> (?:.*/)?   zero or more leading/middle path segments
          **   -> .*         any run of characters, including '/'
          *    -> [^/]*      any run of characters except '/'
          ?    -> [^/]       exactly one character except '/'
          else -> the regex-escaped literal character

        The result is anchored with ^...$ so a pattern matches the whole path
        (or basename) rather than just a substring.

    .EXAMPLE
        ConvertTo-LabelGlobRegex -Pattern 'docs/**'   # -> '^docs/.*$'
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $Pattern
    )

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append('^')

    $i = 0
    $n = $Pattern.Length
    while ($i -lt $n) {
        $c = $Pattern[$i]
        if ($c -eq '*') {
            $isGlobstar = ($i + 1 -lt $n) -and ($Pattern[$i + 1] -eq '*')
            if ($isGlobstar) {
                $followedBySlash = ($i + 2 -lt $n) -and ($Pattern[$i + 2] -eq '/')
                if ($followedBySlash) {
                    # '**/' collapses any number of leading segments (including none).
                    [void]$sb.Append('(?:.*/)?')
                    $i += 3
                }
                else {
                    # Trailing or bare '**' matches anything, crossing '/'.
                    [void]$sb.Append('.*')
                    $i += 2
                }
            }
            else {
                # A single '*' stays within one path segment.
                [void]$sb.Append('[^/]*')
                $i += 1
            }
        }
        elseif ($c -eq '?') {
            [void]$sb.Append('[^/]')
            $i += 1
        }
        else {
            # Escape everything else so '.', '+', '(', etc. stay literal.
            [void]$sb.Append([regex]::Escape([string]$c))
            $i += 1
        }
    }

    [void]$sb.Append('$')
    return $sb.ToString()
}

function Test-LabelGlobMatch {
    <#
    .SYNOPSIS
        Tests whether a single file path matches a single glob pattern.

    .DESCRIPTION
        Path separators are normalised to '/'. A pattern that contains no '/'
        is matched against the file's basename (gitignore semantics), so
        '*.test.*' catches a test file anywhere in the tree. A pattern that
        contains a '/' is matched against the full, normalised path.

        Matching is case-sensitive because git treats paths case-sensitively.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Pattern
    )

    $normalisedPath    = ($Path    -replace '\\', '/').Trim()
    $normalisedPattern = ($Pattern -replace '\\', '/').Trim()

    # Slash-less patterns target the basename at any depth.
    if ($normalisedPattern -notmatch '/') {
        $target = ($normalisedPath -split '/')[-1]
    }
    else {
        $target = $normalisedPath
    }

    $regex = ConvertTo-LabelGlobRegex -Pattern $normalisedPattern
    return [regex]::IsMatch($target, $regex)
}

function Get-PRLabel {
    <#
    .SYNOPSIS
        Computes the final, ordered, de-duplicated label set for a PR.

    .PARAMETER ChangedFiles
        The PR's changed file paths (the simulated diff).

    .PARAMETER Rules
        An array of rule objects. Each rule may expose:
          Pattern  - a glob string or array of glob strings (OR semantics). Required.
          Labels   - a label string or array of label strings. Required.
          Priority - integer; higher wins. Optional (default 0).
          Group    - mutual-exclusion group name. Optional (default none).
        Rules may be hashtables or PSCustomObjects (e.g. from ConvertFrom-Json).

    .OUTPUTS
        [string[]] ordered by descending effective priority, ties broken by the
        order in which the label was first declared. Always an array.

    .NOTES
        Algorithm
        ---------
        1. For each rule, decide whether it matches the PR: a rule matches if any
           of its patterns matches any changed file.
        2. Each matching rule contributes its labels, tagged with the rule's
           priority, group, and a monotonically increasing declaration order.
        3. Conflict resolution: within every group, drop every contribution whose
           priority is below the group's maximum. Ungrouped contributions are
           always kept.
        4. Collapse to a unique label set — a label's effective priority is the
           highest among its surviving contributions; its order is the earliest.
        5. Sort by (priority desc, order asc) and emit the label names.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $ChangedFiles,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Rules
    )

    # Normalise the changed-file list once: forward slashes, trimmed, no blanks.
    $files = @(
        $ChangedFiles |
            ForEach-Object { ($_ -replace '\\', '/').Trim() } |
            Where-Object   { $_ }
    )

    # --- Steps 1 & 2: collect contributions from every matching rule. ---------
    $contributions = [System.Collections.Generic.List[object]]::new()
    $order = 0

    foreach ($rule in $Rules) {
        $patterns = @(Get-LabelRuleProperty -InputObject $rule -Name 'Pattern')
        $labels   = @(Get-LabelRuleProperty -InputObject $rule -Name 'Labels')
        $priority = [int](Get-LabelRuleProperty -InputObject $rule -Name 'Priority' -Default 0)
        $group    =      Get-LabelRuleProperty -InputObject $rule -Name 'Group'    -Default $null
        if ([string]::IsNullOrWhiteSpace([string]$group)) { $group = $null }

        # A rule matches the PR if any pattern matches any changed file.
        $ruleMatches = $false
        foreach ($file in $files) {
            foreach ($pattern in $patterns) {
                if (Test-LabelGlobMatch -Path $file -Pattern ([string]$pattern)) {
                    $ruleMatches = $true
                    break
                }
            }
            if ($ruleMatches) { break }
        }

        if (-not $ruleMatches) { continue }

        foreach ($label in $labels) {
            $contributions.Add([pscustomobject]@{
                Label    = [string]$label
                Priority = $priority
                Group    = $group
                Order    = $order
            })
            $order++
        }
    }

    if ($contributions.Count -eq 0) { return @() }

    # --- Step 3: resolve conflicts within each group. -------------------------
    $surviving = [System.Collections.Generic.List[object]]::new()

    foreach ($c in $contributions) {
        if ($null -eq $c.Group) { $surviving.Add($c) }   # ungrouped is always additive
    }

    $grouped = $contributions | Where-Object { $null -ne $_.Group }
    foreach ($g in ($grouped | Group-Object -Property Group)) {
        $maxPriority = ($g.Group | Measure-Object -Property Priority -Maximum).Maximum
        foreach ($c in $g.Group) {
            if ($c.Priority -eq $maxPriority) { $surviving.Add($c) }
        }
    }

    # --- Step 4: collapse to a unique label set. ------------------------------
    # Preserve insertion order with an ordered dictionary so ties stay stable.
    $byLabel = [ordered]@{}
    foreach ($c in ($surviving | Sort-Object -Property Order)) {
        if (-not $byLabel.Contains($c.Label)) {
            $byLabel[$c.Label] = [pscustomobject]@{
                Label    = $c.Label
                Priority = $c.Priority
                Order    = $c.Order
            }
        }
        else {
            $existing = $byLabel[$c.Label]
            if ($c.Priority -gt $existing.Priority) { $existing.Priority = $c.Priority }
            # Order already minimal because we iterated in ascending order.
        }
    }

    # --- Step 5: sort and emit. -----------------------------------------------
    $ordered = $byLabel.Values |
        Sort-Object -Property @{ Expression = 'Priority'; Descending = $true },
                              @{ Expression = 'Order';    Descending = $false }

    # Emit the label names to the pipeline (unrolled). Callers that need a
    # guaranteed array — even for a single or empty result — should wrap the
    # call in @(), e.g. $labels = @(Get-PRLabel ...).
    return @($ordered | ForEach-Object { $_.Label })
}

function Import-LabelRule {
    <#
    .SYNOPSIS
        Loads and normalises label rules from a JSON config file.

    .DESCRIPTION
        The JSON shape is:

            {
              "rules": [
                { "pattern": "docs/**", "labels": ["documentation"], "priority": 10 },
                { "pattern": ["src/api/**", "api/**"], "labels": ["api", "backend"],
                  "priority": 50, "group": "area" }
              ]
            }

        'pattern' and 'labels' may each be a single string or an array of
        strings. 'priority' defaults to 0; 'group' defaults to none. The result
        is an array of PSCustomObjects with Pattern/Labels (always arrays),
        Priority (int) and Group (string or $null) — exactly the shape
        Get-PRLabel expects.

        Errors are surfaced with actionable messages: a missing file, malformed
        JSON, a missing 'rules' array, or a rule missing its pattern/labels all
        throw with context about what was wrong and where.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)] [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Label rules config not found: '$Path'. Provide a JSON file with a 'rules' array."
    }

    try {
        $raw  = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        $data = $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Failed to parse label rules JSON at '$Path': $($_.Exception.Message)"
    }

    $rulesNode = Get-LabelRuleProperty -InputObject $data -Name 'rules'
    if ($null -eq $rulesNode) {
        throw "Label rules config '$Path' must contain a top-level 'rules' array."
    }

    $normalised = [System.Collections.Generic.List[object]]::new()
    $index = 0
    foreach ($rule in @($rulesNode)) {
        $index++

        $pattern = Get-LabelRuleProperty -InputObject $rule -Name 'pattern'
        $labels  = Get-LabelRuleProperty -InputObject $rule -Name 'labels'

        if ($null -eq $pattern -or @($pattern).Count -eq 0) {
            throw "Rule #$index in '$Path' is missing a 'pattern'."
        }
        if ($null -eq $labels -or @($labels).Count -eq 0) {
            throw "Rule #$index in '$Path' is missing 'labels'."
        }

        $priorityValue = Get-LabelRuleProperty -InputObject $rule -Name 'priority' -Default 0
        $groupValue    = Get-LabelRuleProperty -InputObject $rule -Name 'group'    -Default $null
        if ([string]::IsNullOrWhiteSpace([string]$groupValue)) { $groupValue = $null }

        $normalised.Add([pscustomobject]@{
            Pattern  = @($pattern  | ForEach-Object { [string]$_ })
            Labels   = @($labels   | ForEach-Object { [string]$_ })
            Priority = [int]$priorityValue
            Group    = $groupValue
        })
    }

    return , @($normalised.ToArray())
}

Export-ModuleMember -Function `
    ConvertTo-LabelGlobRegex,
    Test-LabelGlobMatch,
    Get-LabelRuleProperty,
    Get-PRLabel,
    Import-LabelRule
