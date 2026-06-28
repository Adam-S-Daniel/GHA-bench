#Requires -Version 7.0

<#
.SYNOPSIS
    PR Label Assigner — applies labels to a set of changed files using a
    configurable list of glob-pattern -> label(s) rules.

.DESCRIPTION
    Given a list of changed file paths (e.g. a pull request's modified files)
    and a list of rules, this module computes the final set of labels that
    should be applied.

    Features
        - Glob patterns ( *  ?  **  and gitignore-style basename matching )
        - Multiple labels per rule, and multiple matching rules per file
        - Priority ordering: higher-priority rules win and order the output
        - Conflict resolution: a matching rule may "stop" lower-priority
          rules from being evaluated for the same file

    The module is intentionally side-effect free (pure functions). The thin
    CLI wrapper lives in Invoke-PrLabelAssigner.ps1 so the logic stays easy
    to unit-test with Pester.
#>

Set-StrictMode -Version Latest

function ConvertTo-LabelGlobRegex {
    <#
    .SYNOPSIS
        Convert a glob pattern into an anchored .NET regular expression.

    .DESCRIPTION
        Translation rules (POSIX/minimatch-ish, gitignore-flavoured):
            **/     -> zero or more leading directory segments
            /**     -> everything beneath a directory (handled by trailing **)
            **      -> any characters, including '/'
            *       -> any characters except '/'  (stays within one segment)
            ?       -> exactly one character except '/'
            other   -> matched literally (regex-escaped)

        The returned pattern is anchored with ^...$ so it must match the whole
        candidate string.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Pattern
    )

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append('^')

    $i = 0
    $len = $Pattern.Length
    while ($i -lt $len) {
        $c = $Pattern[$i]
        if ($c -eq '*') {
            $isDouble = ($i + 1 -lt $len) -and ($Pattern[$i + 1] -eq '*')
            if ($isDouble) {
                $followedBySlash = ($i + 2 -lt $len) -and ($Pattern[$i + 2] -eq '/')
                if ($followedBySlash) {
                    # '**/'  ->  optional run of complete directory segments
                    [void]$sb.Append('(?:.*/)?')
                    $i += 3
                }
                else {
                    # '**'   ->  anything, crossing directory boundaries
                    [void]$sb.Append('.*')
                    $i += 2
                }
            }
            else {
                # '*'    ->  anything within a single path segment
                [void]$sb.Append('[^/]*')
                $i += 1
            }
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

function Test-LabelGlob {
    <#
    .SYNOPSIS
        Test whether a file path matches a glob pattern.

    .DESCRIPTION
        Slash-free patterns (e.g. '*.test.*') are matched against the file's
        basename at any depth — the same convenient convention used by
        .gitignore. Patterns containing a '/' are matched against the full
        relative path.

    .EXAMPLE
        Test-LabelGlob -Path 'src/api/users.js' -Pattern 'src/api/**'   # True
        Test-LabelGlob -Path 'src/x.test.js'    -Pattern '*.test.*'     # True
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Path,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Pattern
    )

    if ([string]::IsNullOrWhiteSpace($Pattern)) {
        throw "Test-LabelGlob: Pattern must not be empty or whitespace."
    }

    # Normalise Windows-style separators so rules are OS-agnostic.
    $normalisedPath = $Path -replace '\\', '/'
    $normalisedPattern = $Pattern -replace '\\', '/'

    # gitignore semantics: a pattern with no '/' matches the basename only.
    $candidate = $normalisedPath
    if ($normalisedPattern -notmatch '/') {
        $candidate = ($normalisedPath -split '/')[-1]
    }

    $regex = ConvertTo-LabelGlobRegex -Pattern $normalisedPattern
    return [regex]::IsMatch($candidate, $regex)
}

function Import-PrLabelRule {
    <#
    .SYNOPSIS
        Load and validate label rules from a JSON configuration file.

    .DESCRIPTION
        Expected JSON shape:
            {
              "rules": [
                { "pattern": "docs/**", "labels": ["documentation"], "priority": 10 },
                { "pattern": "package.json", "labels": "dependencies",
                  "priority": 50, "stop": true }
              ]
            }

        Each rule is normalised into a PSCustomObject with these properties:
            Pattern  [string]   (required, non-empty)
            Labels   [string[]] (required, a lone string is wrapped to an array)
            Priority [int]      (optional, default 0)
            Stop     [bool]     (optional, default $false)

    .OUTPUTS
        System.Management.Automation.PSCustomObject[]
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Import-PrLabelRule: configuration file not found at '$Path'."
    }

    $raw = Get-Content -LiteralPath $Path -Raw

    try {
        $config = $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Import-PrLabelRule: failed to parse JSON in '$Path'. $($_.Exception.Message)"
    }

    if (-not $config.PSObject.Properties['rules']) {
        throw "Import-PrLabelRule: configuration in '$Path' is missing a top-level 'rules' array."
    }

    $rules = @()
    $index = 0
    foreach ($rule in @($config.rules)) {
        $index++

        # --- pattern (required) ---
        if (-not $rule.PSObject.Properties['pattern'] -or
            [string]::IsNullOrWhiteSpace([string]$rule.pattern)) {
            throw "Import-PrLabelRule: rule #$index in '$Path' is missing a non-empty 'pattern'."
        }

        # --- labels (required, normalised to a string[]) ---
        if (-not $rule.PSObject.Properties['labels']) {
            throw "Import-PrLabelRule: rule #$index ('$($rule.pattern)') in '$Path' is missing 'labels'."
        }
        $labels = @($rule.labels | ForEach-Object { [string]$_ })
        if ($labels.Count -eq 0) {
            throw "Import-PrLabelRule: rule #$index ('$($rule.pattern)') in '$Path' has an empty 'labels' list."
        }

        # --- priority (optional, default 0) ---
        $priority = 0
        if ($rule.PSObject.Properties['priority']) {
            $priority = [int]$rule.priority
        }

        # --- stop (optional, default $false) ---
        $stop = $false
        if ($rule.PSObject.Properties['stop']) {
            $stop = [bool]$rule.stop
        }

        $rules += [PSCustomObject]@{
            Pattern  = [string]$rule.pattern
            Labels   = $labels
            Priority = $priority
            Stop     = $stop
        }
    }

    return $rules
}

function Get-PrLabel {
    <#
    .SYNOPSIS
        Resolve the final set of labels for a list of changed files.

    .DESCRIPTION
        Algorithm:
            1. Rules are evaluated in descending Priority order (ties keep the
               original config order — a stable sort).
            2. For each changed file, every matching rule contributes its
               labels. A label's "rank" is the highest priority of any rule
               that contributed it.
            3. A matching rule whose Stop flag is set short-circuits the
               remaining (lower-priority) rules for that file only — this is
               how higher-priority rules win a conflict.
            4. The union of labels is returned, ordered by descending rank and
               then alphabetically, with duplicates removed.

    .PARAMETER ChangedFile
        The changed file paths (e.g. a PR's modified files). May be empty.

    .PARAMETER Rule
        Normalised rule objects (see Import-PrLabelRule). Each needs Pattern,
        Labels, Priority and Stop.

    .OUTPUTS
        System.String[] — the ordered, de-duplicated label set.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$ChangedFile,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [PSCustomObject[]]$Rule
    )

    # Highest priority at which each label was assigned -> used for ordering.
    $labelRank = [ordered]@{}

    # Stable, highest-priority-first evaluation order.
    $orderedRules = @($Rule | Sort-Object -Property Priority -Descending -Stable)

    foreach ($file in $ChangedFile) {
        if ([string]::IsNullOrWhiteSpace($file)) { continue }

        foreach ($r in $orderedRules) {
            if (Test-LabelGlob -Path $file -Pattern $r.Pattern) {
                foreach ($label in $r.Labels) {
                    if (-not $labelRank.Contains($label) -or $labelRank[$label] -lt $r.Priority) {
                        $labelRank[$label] = $r.Priority
                    }
                }
                if ($r.Stop) { break }  # higher-priority rule wins; skip the rest for this file
            }
        }
    }

    $ordered = $labelRank.Keys |
        Sort-Object -Property `
            @{ Expression = { $labelRank[$_] }; Descending = $true },
            @{ Expression = { $_ }; Descending = $false }

    return @($ordered)
}

function Import-PrChangedFile {
    <#
    .SYNOPSIS
        Read a mock list of changed file paths, one per line.

    .DESCRIPTION
        This is the "mock the file list for testing" hook: instead of calling
        the GitHub API, the changed files are supplied as a simple text file
        (one path per line). Blank lines and lines beginning with '#' (after
        trimming) are ignored, and each path is trimmed of surrounding
        whitespace.

    .OUTPUTS
        System.String[]
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Import-PrChangedFile: changed-file list not found at '$Path'."
    }

    $lines = Get-Content -LiteralPath $Path
    $result = foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ($trimmed -eq '' -or $trimmed.StartsWith('#')) { continue }
        $trimmed
    }

    return @($result)
}

function Resolve-PrLabel {
    <#
    .SYNOPSIS
        End-to-end entry point: read the changed-file list + rule config and
        return the resolved label set.

    .DESCRIPTION
        Glue around Import-PrChangedFile, Import-PrLabelRule and Get-PrLabel.
        Kept separate from the pure Get-PrLabel resolver so the file I/O can be
        tested independently of the matching logic.

    .OUTPUTS
        System.String[] — the ordered, de-duplicated label set.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [string]$ChangedFilesPath,

        [Parameter(Mandatory)]
        [string]$ConfigPath
    )

    $changedFiles = Import-PrChangedFile -Path $ChangedFilesPath
    $rules = Import-PrLabelRule -Path $ConfigPath
    return @(Get-PrLabel -ChangedFile $changedFiles -Rule $rules)
}

Export-ModuleMember -Function @(
    'ConvertTo-LabelGlobRegex'
    'Test-LabelGlob'
    'Import-PrLabelRule'
    'Get-PrLabel'
    'Import-PrChangedFile'
    'Resolve-PrLabel'
)
