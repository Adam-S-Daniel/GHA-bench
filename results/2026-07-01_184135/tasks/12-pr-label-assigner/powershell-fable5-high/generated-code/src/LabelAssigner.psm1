# LabelAssigner.psm1
#
# Core logic for the PR label assigner. Built via red/green TDD; see
# tests/LabelAssigner.Tests.ps1 for the cycle-by-cycle specification.

function Convert-GlobToRegex {
    <#
    .SYNOPSIS
        Converts a glob pattern into an anchored .NET regular expression.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Pattern
    )

    # Escape everything, then translate the escaped glob tokens back into
    # their regex equivalents, longest token first so '**' is not consumed
    # as two single '*'s:
    #   **  -> .*     (crosses '/' boundaries)
    #   *   -> [^/]*  (stays within one path segment)
    #   ?   -> [^/]   (exactly one non-separator character)
    $regex = [regex]::Escape($Pattern)
    $regex = $regex -replace '\\\*\\\*/', '(.*/)?'   # '**/' also matches zero directories
    $regex = $regex -replace '\\\*\\\*', '.*'
    $regex = $regex -replace '\\\*', '[^/]*'
    $regex = $regex -replace '\\\?', '[^/]'

    # A pattern with no '/' (e.g. '*.test.*') matches the basename at any
    # depth, mirroring .gitignore semantics. Slashed patterns anchor to the
    # repo root.
    $anchor = if ($Pattern.Contains('/')) { '^' } else { '(^|.*/)' }

    return "$anchor$regex$"
}

function Test-GlobMatch {
    <#
    .SYNOPSIS
        Tests whether a repo-relative file path matches a glob pattern.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Pattern
    )

    return $Path -match (Convert-GlobToRegex -Pattern $Pattern)
}

function Get-RulePriority {
    # Internal helper: a rule's effective priority (default 100).
    param($Rule)

    if ($null -ne $Rule.Priority) { return [int]$Rule.Priority }
    return 100
}

function Get-PRLabels {
    <#
    .SYNOPSIS
        Computes the label set for a list of changed file paths.
    .DESCRIPTION
        For each changed file, the matching rules with the highest priority
        (lowest Priority number; default 100) contribute their labels —
        equal-priority matches all contribute, lower-priority matches for
        that file are discarded. The result is the sorted, de-duplicated
        union across all files.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$ChangedFiles,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Rules
    )

    # Validate up front so a misconfigured ruleset fails loudly with a
    # message that points at the offending rule, instead of silently
    # assigning no labels.
    if ($Rules.Count -eq 0) {
        throw 'The rule set is empty: provide at least one rule with Pattern and Labels.'
    }
    for ($i = 0; $i -lt $Rules.Count; $i++) {
        $rule = $Rules[$i]
        if ([string]::IsNullOrWhiteSpace([string]$rule.Pattern)) {
            throw "Rule #$($i + 1) is missing a 'Pattern' (glob) property."
        }
        if ($null -eq $rule.Labels -or @($rule.Labels).Count -eq 0) {
            throw "Rule #$($i + 1) ('$($rule.Pattern)') is missing 'Labels': every rule must assign at least one label."
        }
    }

    $labels = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($file in $ChangedFiles) {
        $matching = @($Rules | Where-Object { Test-GlobMatch -Path $file -Pattern $_.Pattern })
        if ($matching.Count -eq 0) { continue }

        # Conflict resolution: keep only the best (numerically lowest)
        # priority among the rules matching THIS file. Missing Priority
        # defaults to 100 so explicit rules outrank catch-alls.
        $best = ($matching | ForEach-Object { Get-RulePriority $_ } | Measure-Object -Minimum).Minimum

        foreach ($rule in $matching) {
            if ((Get-RulePriority $rule) -ne $best) { continue }
            foreach ($label in @($rule.Labels)) {
                [void]$labels.Add($label)
            }
        }
    }

    return @($labels) | Sort-Object
}

Export-ModuleMember -Function Test-GlobMatch, Convert-GlobToRegex, Get-PRLabels
