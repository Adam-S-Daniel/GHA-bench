<#
    PrLabelAssigner.psm1

    Assigns PR labels based on a configurable path-to-label rule set. A rule
    maps a glob Pattern to a Label; rules may optionally declare a Priority
    (used to break ties) and a Group (rules sharing a Group are mutually
    exclusive per file - see Resolve-PrLabels for details).
#>

Set-StrictMode -Version Latest

function ConvertTo-PrLabelGlobRegex {
    <#
        Translates a gitignore-style glob pattern into an anchored regex string.

        Semantics:
          - A pattern with no '/' matches the file's basename at ANY depth
            (e.g. '*.test.*' matches both 'foo.test.ts' and 'src/foo.test.ts'),
            mirroring how .gitignore treats slash-less patterns.
          - '**' matches zero or more path segments (any depth, including none).
          - A single '*' matches within one path segment only (never '/').
          - '?' matches exactly one character, never '/'.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Pattern
    )

    $normalized = $Pattern.Trim().Replace('\', '/')
    if ($normalized -notmatch '/') {
        $normalized = "**/$normalized"
    }

    $regex = [System.Text.StringBuilder]::new()
    [void]$regex.Append('^')

    $i = 0
    $len = $normalized.Length
    while ($i -lt $len) {
        $remaining = $normalized.Substring($i)
        if ($remaining.StartsWith('**/')) {
            [void]$regex.Append('(?:.*/)?')
            $i += 3
            continue
        }
        if ($remaining.StartsWith('**')) {
            [void]$regex.Append('.*')
            $i += 2
            continue
        }

        $c = $normalized[$i]
        switch ($c) {
            '*' { [void]$regex.Append('[^/]*') }
            '?' { [void]$regex.Append('[^/]') }
            default { [void]$regex.Append([regex]::Escape([string]$c)) }
        }
        $i++
    }

    [void]$regex.Append('$')
    return $regex.ToString()
}

function Test-PrLabelGlobMatch {
    <#
        Tests whether a (repo-relative) file path matches a glob Pattern.
        See ConvertTo-PrLabelGlobRegex for the supported glob syntax.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Pattern
    )

    $normalizedPath = $Path.Trim().Replace('\', '/')
    $regex = ConvertTo-PrLabelGlobRegex -Pattern $Pattern
    return [regex]::IsMatch($normalizedPath, $regex)
}

function Import-PrLabelRules {
    <#
        Loads and validates a JSON label-rules file. Each rule requires a
        'Pattern' and a 'Label'; 'Priority' (int, default 0) and 'Group'
        (string, default $null) are optional. See Resolve-PrLabels for how
        Priority/Group influence conflict resolution.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Label rules file not found: '$Path'. Provide a valid path to a JSON rules file."
    }

    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop

    try {
        $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Failed to parse label rules file '$Path' as JSON: $($_.Exception.Message)"
    }

    if ($null -eq $parsed) {
        return @()
    }

    $normalized = foreach ($rule in @($parsed)) {
        $hasPattern = $rule.PSObject.Properties['Pattern'] -and -not [string]::IsNullOrWhiteSpace([string]$rule.Pattern)
        if (-not $hasPattern) {
            throw "Invalid rule in '$Path': every rule requires a non-empty 'Pattern' property. Offending rule: $($rule | ConvertTo-Json -Compress)"
        }
        $hasLabel = $rule.PSObject.Properties['Label'] -and -not [string]::IsNullOrWhiteSpace([string]$rule.Label)
        if (-not $hasLabel) {
            throw "Invalid rule in '$Path': every rule requires a non-empty 'Label' property. Offending rule: $($rule | ConvertTo-Json -Compress)"
        }

        $priority = 0
        if ($rule.PSObject.Properties['Priority'] -and $null -ne $rule.Priority) {
            $priority = [int]$rule.Priority
        }

        $group = $null
        if ($rule.PSObject.Properties['Group'] -and -not [string]::IsNullOrWhiteSpace([string]$rule.Group)) {
            $group = [string]$rule.Group
        }

        [PSCustomObject]@{
            Pattern  = [string]$rule.Pattern
            Label    = [string]$rule.Label
            Priority = $priority
            Group    = $group
        }
    }

    return , @($normalized)
}

function Get-PrChangedFiles {
    <#
        Determines the list of changed files for a PR.

        Resolution order:
          1. If -FixturePath points to an existing file, its non-blank,
             trimmed lines are returned. This is how tests (and the 'push'
             / act-based CI path, which has no PR to diff against) mock the
             changed-file list without hitting a real GitHub API.
          2. Otherwise, if -BaseRef is supplied, the changed files are
             computed via 'git diff --name-only BaseRef...HeadRef'.
          3. Otherwise, a descriptive error is thrown.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [string]$FixturePath,

        [string]$BaseRef,

        [string]$HeadRef = 'HEAD'
    )

    if ($FixturePath -and (Test-Path -LiteralPath $FixturePath -PathType Leaf)) {
        $lines = Get-Content -LiteralPath $FixturePath
        return @($lines | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    if ($BaseRef) {
        $diffOutput = & git diff --name-only "$BaseRef...$HeadRef" 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "git diff failed while computing changed files ('$BaseRef...$HeadRef'): $diffOutput"
        }
        return @($diffOutput | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    throw "Unable to determine changed files: no fixture file found at '$FixturePath' and no BaseRef was supplied."
}

function Resolve-PrLabels {
    <#
        Computes the final label set for a PR from its changed files and a
        set of path-to-label Rules.

        Conflict resolution model (per file, then unioned across files):
          - A file may match several rules and pick up several labels; a
            file touching both 'src/api/**' and '*.test.*' gets both 'api'
            and 'tests'.
          - Rules that share a Group are mutually exclusive FOR THAT FILE:
            among the Group's rules that match the file, only the one with
            the highest Priority contributes its label. Rules without a
            Group never conflict with anything and always contribute when
            matched.
          - The final result is the union of every file's resolved labels,
            deduplicated and returned in sorted order.
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

    if (-not $Rules -or $Rules.Count -eq 0) {
        return @()
    }

    foreach ($rule in $Rules) {
        if (-not $rule.PSObject.Properties['Pattern'] -or [string]::IsNullOrWhiteSpace([string]$rule.Pattern)) {
            throw "Each rule must define a non-empty 'Pattern' property. Offending rule: $($rule | ConvertTo-Json -Compress)"
        }
        if (-not $rule.PSObject.Properties['Label'] -or [string]::IsNullOrWhiteSpace([string]$rule.Label)) {
            throw "Each rule must define a non-empty 'Label' property. Offending rule: $($rule | ConvertTo-Json -Compress)"
        }
    }

    $labelSet = [System.Collections.Generic.HashSet[string]]::new()

    foreach ($file in $ChangedFiles) {
        if ([string]::IsNullOrWhiteSpace($file)) {
            continue
        }

        $matchedRules = @($Rules | Where-Object { Test-PrLabelGlobMatch -Path $file -Pattern $_.Pattern })
        if ($matchedRules.Count -eq 0) {
            continue
        }

        $ungroupedRules = $matchedRules | Where-Object { -not $_.Group }
        foreach ($rule in $ungroupedRules) {
            [void]$labelSet.Add($rule.Label)
        }

        $groupedRules = $matchedRules | Where-Object { $_.Group }
        foreach ($groupEntry in ($groupedRules | Group-Object -Property Group)) {
            $winner = $groupEntry.Group | Sort-Object -Property Priority -Descending | Select-Object -First 1
            [void]$labelSet.Add($winner.Label)
        }
    }

    return @($labelSet | Sort-Object)
}

Export-ModuleMember -Function Test-PrLabelGlobMatch, Import-PrLabelRules, Get-PrChangedFiles, Resolve-PrLabels
