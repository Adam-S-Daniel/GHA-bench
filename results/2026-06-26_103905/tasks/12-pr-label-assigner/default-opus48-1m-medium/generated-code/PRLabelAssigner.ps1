function Convert-GlobToRegex {
    <#
    .SYNOPSIS
        Translate a glob pattern into an anchored .NET regex.
    .DESCRIPTION
        Supported glob syntax (gitignore / labeler-style):
          **  matches any number of characters INCLUDING path separators
          *   matches any number of characters EXCEPT the path separator '/'
          ?   matches exactly one character except '/'
        All other characters are treated literally (regex-escaped).
        The returned regex is anchored with ^...$ so it matches a whole path.
    #>
    param([Parameter(Mandatory)] [string] $Glob)

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('^')

    for ($i = 0; $i -lt $Glob.Length; $i++) {
        $c = $Glob[$i]
        switch ($c) {
            '*' {
                if ($i + 1 -lt $Glob.Length -and $Glob[$i + 1] -eq '*') {
                    # '**' -> match anything, including '/'
                    [void]$sb.Append('.*')
                    $i++  # consume the second '*'
                }
                else {
                    # single '*' -> match anything except '/'
                    [void]$sb.Append('[^/]*')
                }
            }
            '?' { [void]$sb.Append('[^/]') }
            default {
                # Escape any regex metacharacter so it is matched literally.
                [void]$sb.Append([System.Text.RegularExpressions.Regex]::Escape([string]$c))
            }
        }
    }

    [void]$sb.Append('$')
    return $sb.ToString()
}

function Test-GlobMatch {
    <#
    .SYNOPSIS
        Return $true if a file path matches a glob pattern.
    .DESCRIPTION
        If the pattern contains no '/', it is matched against the file's
        basename (e.g. '*.test.*' matches 'src/foo.test.js'). Otherwise it is
        matched against the full path. Matching is case-sensitive, which is the
        safe default for POSIX-style repository paths.
    #>
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Pattern
    )

    $target = if ($Pattern.Contains('/')) { $Path } else { Split-Path -Path $Path -Leaf }
    $regex = Convert-GlobToRegex -Glob $Pattern
    return [System.Text.RegularExpressions.Regex]::IsMatch($target, $regex)
}

function Get-PRLabels {
    <#
    .SYNOPSIS
        Compute the set of labels to apply to a PR given its changed files.
    .PARAMETER ChangedFiles
        The list of file paths changed in the PR (the "mock" file list).
    .PARAMETER Rules
        An array of hashtables, each with keys: Pattern (glob), Label (string),
        and optionally Priority (int, default 0).
    .OUTPUTS
        The de-duplicated set of labels, ordered by descending rule priority
        then alphabetically.
    #>
    param(
        [string[]] $ChangedFiles,
        [hashtable[]] $Rules
    )

    # Validate every rule up front so we fail fast with a clear message.
    foreach ($rule in $Rules) {
        if (-not $rule.ContainsKey('Pattern') -or [string]::IsNullOrWhiteSpace([string]$rule.Pattern)) {
            throw "Invalid rule: each rule must define a non-empty 'Pattern'. Got: $($rule | ConvertTo-Json -Compress)"
        }
        if (-not $rule.ContainsKey('Label') -or [string]::IsNullOrWhiteSpace([string]$rule.Label)) {
            throw "Invalid rule for pattern '$($rule.Pattern)': each rule must define a non-empty 'Label'."
        }
    }

    # Map of label -> highest priority seen for that label (for ordering).
    $best = @{}
    foreach ($file in $ChangedFiles) {
        foreach ($rule in $Rules) {
            if (Test-GlobMatch -Path $file -Pattern $rule.Pattern) {
                $priority = if ($rule.ContainsKey('Priority')) { [int]$rule.Priority } else { 0 }
                if (-not $best.ContainsKey($rule.Label) -or $priority -gt $best[$rule.Label]) {
                    $best[$rule.Label] = $priority
                }
            }
        }
    }

    # Order labels by priority (desc) then name (asc) for deterministic output.
    return $best.Keys |
        Sort-Object -Property @{ Expression = { $best[$_] }; Descending = $true }, @{ Expression = { $_ }; Descending = $false }
}

function Import-LabelRules {
    <#
    .SYNOPSIS
        Load path-to-label rules from a JSON config file.
    .DESCRIPTION
        Expected JSON shape:
          { "rules": [ { "pattern": "docs/**", "label": "documentation", "priority": 1 }, ... ] }
        Returns an array of hashtables with Pattern/Label/Priority keys suitable
        for Get-PRLabels.
    #>
    param([Parameter(Mandatory)] [string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Config file not found: '$Path'"
    }

    try {
        $config = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    }
    catch {
        throw "Failed to parse JSON config '$Path': $($_.Exception.Message)"
    }

    if ($null -eq $config.rules) {
        throw "Config '$Path' must contain a top-level 'rules' array."
    }

    $rules = foreach ($r in $config.rules) {
        @{
            Pattern  = [string]$r.pattern
            Label    = [string]$r.label
            Priority = if ($null -ne $r.priority) { [int]$r.priority } else { 0 }
        }
    }
    return ,@($rules)
}

function Import-ChangedFiles {
    <#
    .SYNOPSIS
        Read a newline-delimited list of changed file paths from a file.
        Blank lines and surrounding whitespace are ignored.
    #>
    param([Parameter(Mandatory)] [string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Changed-files list not found: '$Path'"
    }

    return @(
        Get-Content -LiteralPath $Path |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -ne '' }
    )
}

function Invoke-PRLabelAssigner {
    <#
    .SYNOPSIS
        CLI glue: load rules + changed files, compute labels, and print them.
    .DESCRIPTION
        Prints a human-readable summary plus two machine-parseable lines that
        the CI harness asserts on:
            FINAL_LABELS=<comma-separated, ordered>
            LABEL_COUNT=<n>
    #>
    param(
        [Parameter(Mandatory)] [string] $RulesPath,
        [Parameter(Mandatory)] [string] $ChangedFilesPath
    )

    $rules = Import-LabelRules    -Path $RulesPath
    $files = Import-ChangedFiles  -Path $ChangedFilesPath

    Write-Host "Loaded $($rules.Count) rule(s) and $($files.Count) changed file(s)."
    $labels = @(Get-PRLabels -ChangedFiles $files -Rules $rules)

    Write-Host "FINAL_LABELS=$($labels -join ',')"
    Write-Host "LABEL_COUNT=$($labels.Count)"
    return $labels
}

