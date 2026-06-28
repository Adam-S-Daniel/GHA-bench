# Converts a shell-style glob pattern into an anchored .NET regular expression.
#
# Supported wildcards (documented intentionally so behavior is predictable):
#   **/   -> matches zero or more leading path segments  ((?:.*/)?)
#   **    -> matches any run of characters, including '/' (.*)
#   *     -> matches any run of characters except '/'     ([^/]*)
#   ?     -> matches exactly one character except '/'     ([^/])
# Every other character is treated literally (regex-escaped).
function Convert-GlobToRegex {
    param([Parameter(Mandatory)][string]$Glob)

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append('^')
    $i = 0
    while ($i -lt $Glob.Length) {
        $c = $Glob[$i]
        if ($c -eq '*' -and ($i + 1) -lt $Glob.Length -and $Glob[$i + 1] -eq '*') {
            if (($i + 2) -lt $Glob.Length -and $Glob[$i + 2] -eq '/') {
                # '**/' collapses to an optional run of directory segments so the
                # pattern still matches when there are no leading directories.
                [void]$sb.Append('(?:.*/)?'); $i += 3; continue
            }
            # bare '**' matches anything, including path separators.
            [void]$sb.Append('.*'); $i += 2; continue
        }
        if ($c -eq '*') { [void]$sb.Append('[^/]*'); $i++; continue }
        if ($c -eq '?') { [void]$sb.Append('[^/]'); $i++; continue }
        [void]$sb.Append([regex]::Escape([string]$c)); $i++
    }
    [void]$sb.Append('$')
    return $sb.ToString()
}

# Tests whether a (forward-slash separated) file path matches a glob pattern.
#
# Anchoring rule (mirrors .gitignore semantics so it is intuitive):
#   * A pattern containing no '/' is matched against the file's *basename*,
#     so "*.test.*" matches "src/components/Button.test.tsx".
#   * A pattern containing a '/' is matched against the full relative path.
# Matching is case-insensitive.
function Test-GlobMatch {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Pattern
    )
    # Normalize Windows-style separators so callers can pass either form.
    $normalized = $Path -replace '\\', '/'
    $regex = Convert-GlobToRegex -Glob $Pattern
    $target = if ($Pattern.Contains('/')) { $normalized } else { ($normalized -split '/')[-1] }
    return [regex]::IsMatch($target, $regex, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
}

# Reads a named property from a rule expressed as either a [hashtable] or a
# [pscustomobject] (the latter is what ConvertFrom-Json produces), returning
# $Default when the property is absent or null.
function Get-RuleProperty {
    param(
        [Parameter(Mandatory)]$Rule,
        [Parameter(Mandatory)][string]$Name,
        $Default = $null
    )
    if ($Rule -is [System.Collections.IDictionary]) {
        if ($Rule.Contains($Name) -and $null -ne $Rule[$Name]) { return $Rule[$Name] }
        return $Default
    }
    $prop = $Rule.PSObject.Properties[$Name]
    if ($null -ne $prop -and $null -ne $prop.Value) { return $prop.Value }
    return $Default
}

# Core engine. Given a list of changed file paths and a set of rules, returns an
# object with:
#   .Labels -> the final, de-duplicated label set ordered by descending rule
#              priority (ties broken alphabetically for determinism)
#   .Files  -> per-file detail ([{ Path; Labels }]) for transparency/debugging
#
# Conflict resolution: rules are evaluated highest-priority-first. A rule flagged
# StopOnMatch is "exclusive" -- once it matches a file, no lower-priority rule is
# applied to that file (e.g. a generated/vendored file gets ONLY its 'generated'
# label and nothing else).
function Resolve-PrLabels {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$ChangedFiles,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Rules
    )

    # 1. Normalize + validate every rule into a predictable internal shape.
    $normalized = [System.Collections.Generic.List[object]]::new()
    for ($idx = 0; $idx -lt $Rules.Count; $idx++) {
        $r = $Rules[$idx]
        $pattern = Get-RuleProperty -Rule $r -Name 'Pattern'
        if ([string]::IsNullOrWhiteSpace([string]$pattern)) {
            throw "Rule at index $idx is missing a non-empty 'Pattern'."
        }
        $labels = @(Get-RuleProperty -Rule $r -Name 'Labels' -Default @())
        if ($labels.Count -eq 0) {
            throw "Rule at index $idx (pattern '$pattern') must define at least one label."
        }
        $normalized.Add([pscustomobject]@{
            Pattern     = [string]$pattern
            Labels      = $labels
            Priority    = [int](Get-RuleProperty -Rule $r -Name 'Priority' -Default 0)
            StopOnMatch = [bool](Get-RuleProperty -Rule $r -Name 'StopOnMatch' -Default $false)
            Index       = $idx
        })
    }

    # 2. Stable sort: highest priority first, original order as the tie-breaker.
    $sorted = @($normalized | Sort-Object `
        @{ Expression = 'Priority'; Descending = $true }, `
        @{ Expression = 'Index';    Descending = $false })

    # Tracks the highest priority that contributed each label across ALL files,
    # which is what determines the final label set's ordering.
    $labelPriority = @{}
    $fileResults = [System.Collections.Generic.List[object]]::new()

    foreach ($file in $ChangedFiles) {
        $fileLabelPriority = @{}
        foreach ($rule in $sorted) {
            if (Test-GlobMatch -Path $file -Pattern $rule.Pattern) {
                foreach ($lbl in $rule.Labels) {
                    if (-not $fileLabelPriority.ContainsKey($lbl) -or $fileLabelPriority[$lbl] -lt $rule.Priority) {
                        $fileLabelPriority[$lbl] = $rule.Priority
                    }
                    if (-not $labelPriority.ContainsKey($lbl) -or $labelPriority[$lbl] -lt $rule.Priority) {
                        $labelPriority[$lbl] = $rule.Priority
                    }
                }
                # Exclusive rule -> stop applying any lower-priority rules here.
                if ($rule.StopOnMatch) { break }
            }
        }
        $fileResults.Add([pscustomobject]@{
            Path   = $file
            Labels = @(Sort-LabelsByPriority -LabelPriority $fileLabelPriority)
        })
    }

    return [pscustomobject]@{
        Labels = @(Sort-LabelsByPriority -LabelPriority $labelPriority)
        Files  = $fileResults.ToArray()
    }
}

# Orders a label->priority map by descending priority, then ascending label name.
function Sort-LabelsByPriority {
    param([Parameter(Mandatory)][hashtable]$LabelPriority)
    return @(
        $LabelPriority.Keys | Sort-Object `
            @{ Expression = { $LabelPriority[$_] }; Descending = $true }, `
            @{ Expression = { $_ };                 Descending = $false }
    )
}

# Loads label rules from a JSON config file shaped like:
#   { "rules": [ { "pattern": "...", "labels": ["..."], "priority": N,
#                  "stopOnMatch": true|false }, ... ] }
# Returns the array of rule objects (consumed directly by Resolve-PrLabels).
# Fails loudly with actionable messages for the common error cases.
function Import-LabelRules {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Label rules config not found at '$Path'."
    }

    $raw = Get-Content -LiteralPath $Path -Raw
    try {
        $config = $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Failed to parse JSON in '$Path': $($_.Exception.Message)"
    }

    if ($null -eq $config.PSObject.Properties['rules'] -or $null -eq $config.rules) {
        throw "Config '$Path' must contain a top-level 'rules' array."
    }

    return @($config.rules)
}

# Reads a changed-file manifest: one path per line. Blank lines and lines whose
# first non-whitespace character is '#' (comments) are ignored; each remaining
# line is trimmed. This is the "mock file list" used for testing.
function Get-ChangedFile {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Changed-files manifest not found at '$Path'."
    }

    $lines = Get-Content -LiteralPath $Path
    return @(
        $lines |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -ne '' -and -not $_.StartsWith('#') }
    )
}

# Renders a Resolve-PrLabels result into a human-readable report whose last two
# lines are machine-parseable markers consumed by CI / the act test harness:
#   PR_LABELS=<comma-separated, priority-ordered>   (empty when none)
#   PR_LABEL_COUNT=<n>
function Format-PrLabelOutput {
    param([Parameter(Mandatory)][object]$Result)

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('=== PR Label Assigner ===')
    $lines.Add("Changed files: $($Result.Files.Count)")
    $lines.Add('--- Per-file labels ---')
    foreach ($file in $Result.Files) {
        $labelText = if ($file.Labels.Count -gt 0) { $file.Labels -join ', ' } else { '(no labels)' }
        $lines.Add("$($file.Path) -> $labelText")
    }
    $lines.Add('--- Final label set ---')
    $lines.Add("PR_LABELS=$($Result.Labels -join ',')")
    $lines.Add("PR_LABEL_COUNT=$($Result.Labels.Count)")
    return $lines.ToArray()
}

Export-ModuleMember -Function Convert-GlobToRegex, Test-GlobMatch, Get-RuleProperty, `
    Resolve-PrLabels, Import-LabelRules, Get-ChangedFile, Format-PrLabelOutput
