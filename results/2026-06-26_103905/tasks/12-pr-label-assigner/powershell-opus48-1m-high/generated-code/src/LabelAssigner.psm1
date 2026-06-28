# LabelAssigner.psm1
# Core logic for assigning labels to a PR based on its changed files.
#
# Public functions:
#   ConvertTo-GlobRegex  - translate a glob pattern into a .NET regex
#   Test-GlobMatch       - test whether a file path matches a glob pattern
#   Get-FileLabels       - resolve the labels for a single file
#   Get-PrLabels         - resolve the final, deduplicated label set for a PR
#   Get-LabelRules       - load + validate rules from a JSON config file
#   Invoke-LabelAssigner - CLI-style entry point used by the workflow

Set-StrictMode -Version Latest

function ConvertTo-GlobRegex {
    <#
        .SYNOPSIS
            Translate a glob pattern into an anchored .NET regular expression.
        .DESCRIPTION
            Supported glob tokens:
              **  matches any sequence of characters, including '/'
              *   matches any sequence of characters except '/'
              ?   matches exactly one character except '/'
            Every other character is treated literally (regex metacharacters
            such as '.', '+', '(' are escaped). The returned regex is anchored
            with ^...$ so it must match the whole input string.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Pattern
    )

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append('^')

    for ($i = 0; $i -lt $Pattern.Length; $i++) {
        $c = $Pattern[$i]
        switch ($c) {
            '*' {
                if ($i + 1 -lt $Pattern.Length -and $Pattern[$i + 1] -eq '*') {
                    # '**' => any characters including separators.
                    [void]$sb.Append('.*')
                    $i++  # consume the second '*'
                    # Swallow a trailing slash after '**' so that 'docs/**'
                    # also matches the directory itself ('docs').
                    if ($i + 1 -lt $Pattern.Length -and $Pattern[$i + 1] -eq '/') {
                        $i++
                    }
                }
                else {
                    # single '*' => anything except a path separator.
                    [void]$sb.Append('[^/]*')
                }
            }
            '?' { [void]$sb.Append('[^/]') }
            default {
                # Escape the single character so regex metacharacters stay literal.
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
            Returns $true when $Path matches the glob $Pattern.
        .DESCRIPTION
            A pattern containing no '/' is matched against the file's basename
            (gitignore-style), so '*.test.*' matches 'src/foo.test.js'.
            Otherwise the full relative path is matched. Matching is
            case-sensitive to mirror how Git tracks paths.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Pattern
    )

    # Normalise Windows separators so rules can be written with '/'.
    $normalisedPath = $Path -replace '\\', '/'

    # Slash-less patterns apply to the basename at any directory depth.
    $target = if ($Pattern -notmatch '/') {
        Split-Path -Path $normalisedPath -Leaf
    }
    else {
        $normalisedPath
    }

    $regex = ConvertTo-GlobRegex -Pattern $Pattern
    return [regex]::IsMatch($target, $regex)
}

function Get-FileLabels {
    <#
        .SYNOPSIS
            Resolve the set of labels that apply to a single changed file.
        .DESCRIPTION
            Each rule has: pattern, labels[], priority (higher = stronger),
            and an optional exclusiveGroup. All matching rules contribute their
            labels EXCEPT that, within a single exclusiveGroup, only the labels
            of the highest-priority matching rule are kept (ties broken by the
            rule's position in the list — earlier wins). This is how conflicting
            rules are arbitrated. Labels are returned de-duplicated, preserving
            first-seen order.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Rules
    )

    # Find every rule whose pattern matches this file, remembering input order.
    $matched = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $Rules.Count; $i++) {
        $rule = $Rules[$i]
        if (Test-GlobMatch -Path $Path -Pattern $rule.pattern) {
            $matched.Add([pscustomobject]@{ Rule = $rule; Index = $i })
        }
    }

    # Track which exclusive group has already been "won" so later, lower
    # priority rules in that group are suppressed.
    $groupWinner = @{}
    foreach ($m in $matched) {
        $group = $m.Rule.exclusiveGroup
        if ([string]::IsNullOrEmpty($group)) { continue }

        if (-not $groupWinner.ContainsKey($group)) {
            $groupWinner[$group] = $m
            continue
        }

        $current = $groupWinner[$group]
        # Higher priority wins; on a tie the earlier rule (smaller index) wins.
        if ($m.Rule.priority -gt $current.Rule.priority -or
            ($m.Rule.priority -eq $current.Rule.priority -and $m.Index -lt $current.Index)) {
            $groupWinner[$group] = $m
        }
    }

    # Collect labels, skipping group losers, de-duplicating in order.
    $result = [System.Collections.Generic.List[string]]::new()
    foreach ($m in $matched) {
        $group = $m.Rule.exclusiveGroup
        if (-not [string]::IsNullOrEmpty($group) -and $groupWinner[$group] -ne $m) {
            continue  # a stronger rule already owns this exclusive group
        }
        foreach ($label in $m.Rule.labels) {
            if (-not $result.Contains($label)) { $result.Add($label) }
        }
    }

    return $result.ToArray()
}

function Get-LabelRules {
    <#
        .SYNOPSIS
            Load and validate path-to-label mapping rules from a JSON file.
        .DESCRIPTION
            The file must contain a top-level "rules" array. Each rule requires
            a "pattern" (glob string) and a non-empty "labels" array. "priority"
            (number, default 0) and "exclusiveGroup" (string, default $null)
            are optional. Throws descriptive errors for missing files, invalid
            JSON, or malformed rules.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Rules file not found: '$Path'"
    }

    $raw = Get-Content -LiteralPath $Path -Raw
    try {
        $config = $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Failed to parse rules JSON in '$Path': $($_.Exception.Message)"
    }

    if (-not ($config.PSObject.Properties.Name -contains 'rules') -or $null -eq $config.rules) {
        throw "Rules file '$Path' must contain a top-level 'rules' array."
    }

    $normalized = [System.Collections.Generic.List[object]]::new()
    $index = 0
    foreach ($rule in @($config.rules)) {
        $index++

        if ([string]::IsNullOrWhiteSpace($rule.pattern)) {
            throw "Rule #$index in '$Path' is missing a non-empty 'pattern'."
        }
        if ($null -eq $rule.labels -or @($rule.labels).Count -eq 0) {
            throw "Rule #$index ('$($rule.pattern)') in '$Path' is missing a non-empty 'labels' array."
        }

        # Apply defaults for the optional fields so downstream code is simple.
        $priority = 0
        if ($rule.PSObject.Properties.Name -contains 'priority' -and $null -ne $rule.priority) {
            $priority = [int]$rule.priority
        }
        $group = $null
        if ($rule.PSObject.Properties.Name -contains 'exclusiveGroup') {
            $group = $rule.exclusiveGroup
        }

        $normalized.Add([pscustomobject]@{
            pattern        = [string]$rule.pattern
            labels         = @($rule.labels | ForEach-Object { [string]$_ })
            priority       = $priority
            exclusiveGroup = $group
        })
    }

    return $normalized.ToArray()
}

function Get-PrLabels {
    <#
        .SYNOPSIS
            Resolve the final, ordered, de-duplicated label set for a PR.
        .DESCRIPTION
            Applies the rules to every changed file, takes the union of the
            resulting labels, and orders them by the highest rule priority that
            produced each label (descending), breaking ties alphabetically for
            deterministic output.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$ChangedFiles,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Rules
    )

    # Map each emitted label to the strongest priority that produced it.
    $labelPriority = @{}
    foreach ($file in $ChangedFiles) {
        $labels = Get-FileLabels -Path $file -Rules $Rules
        foreach ($label in $labels) {
            # Find the strongest priority among rules that emit this label and
            # actually match this file (so ordering reflects real precedence).
            foreach ($rule in $Rules) {
                if ($rule.labels -contains $label -and (Test-GlobMatch -Path $file -Pattern $rule.pattern)) {
                    if (-not $labelPriority.ContainsKey($label) -or $rule.priority -gt $labelPriority[$label]) {
                        $labelPriority[$label] = $rule.priority
                    }
                }
            }
        }
    }

    if ($labelPriority.Count -eq 0) { return @() }

    # Sort by priority desc, then label name asc for stable output.
    return @(
        $labelPriority.GetEnumerator() |
            Sort-Object -Property @{ Expression = 'Value'; Descending = $true },
                                  @{ Expression = 'Key';   Descending = $false } |
            ForEach-Object { $_.Key }
    )
}

function Invoke-LabelAssigner {
    <#
        .SYNOPSIS
            High-level entry point: resolve the labels for a set of changed
            files using rules loaded from a JSON config.
        .DESCRIPTION
            Changed files may be supplied either as an in-memory array
            (-ChangedFiles) or via a newline-delimited list file
            (-ChangedFilesPath). Blank lines are skipped and entries trimmed.
            Returns an object with .Labels (string[]), .ChangedFiles and
            .RuleCount for convenient downstream reporting.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'List')]
        [string]$ChangedFilesPath,

        [Parameter(Mandatory, ParameterSetName = 'Array')]
        [AllowEmptyCollection()]
        [string[]]$ChangedFiles,

        [Parameter(Mandatory)]
        [string]$RulesPath
    )

    $rules = Get-LabelRules -Path $RulesPath

    if ($PSCmdlet.ParameterSetName -eq 'List') {
        if (-not (Test-Path -LiteralPath $ChangedFilesPath -PathType Leaf)) {
            throw "Changed-files list not found: '$ChangedFilesPath'"
        }
        $ChangedFiles = @(
            Get-Content -LiteralPath $ChangedFilesPath |
                ForEach-Object { $_.Trim() } |
                Where-Object { $_ -ne '' }
        )
    }

    $labels = Get-PrLabels -ChangedFiles $ChangedFiles -Rules $rules

    return [pscustomobject]@{
        Labels       = $labels
        ChangedFiles = $ChangedFiles
        RuleCount    = $rules.Count
    }
}

# Export only the intended public surface.
Export-ModuleMember -Function ConvertTo-GlobRegex, Test-GlobMatch, Get-FileLabels,
    Get-PrLabels, Get-LabelRules, Invoke-LabelAssigner
