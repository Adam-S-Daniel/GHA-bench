<#
.SYNOPSIS
    PR Label Assigner - assigns labels to a pull request based on which files
    it changed, using configurable glob path -> label mapping rules.

.DESCRIPTION
    Given a list of changed file paths and a set of rules, this module decides
    which labels apply. It supports:
      * glob patterns (*, **, ?) with proper directory-boundary semantics
      * multiple labels per rule (and therefore per file)
      * priority ordering so the final label set is deterministic and the most
        important labels surface first when several rules contribute labels

    The module is intentionally side-effect free: it reads inputs, computes a
    label set, and returns it. The thin CLI wrappers in ../scripts call into it
    and the GitHub Actions workflow calls those wrappers.
#>

Set-StrictMode -Version Latest

function ConvertTo-GlobRegex {
    <#
    .SYNOPSIS
        Convert a glob pattern into an anchored .NET regular expression string.

    .DESCRIPTION
        Glob semantics (modelled on the common GitHub "labeler" conventions):
          **/   -> zero or more leading path segments   => (?:.*/)?
          **    -> any characters, including '/'         => .*
          *     -> any characters except '/'             => [^/]*
          ?     -> exactly one character except '/'      => [^/]
        Every other character is treated literally and regex-escaped.

        The returned pattern is anchored with ^...$ so it matches a whole path.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Glob
    )

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append('^')

    $i = 0
    $len = $Glob.Length
    while ($i -lt $len) {
        $c = $Glob[$i]
        if ($c -eq '*') {
            $isDouble = ($i + 1 -lt $len) -and ($Glob[$i + 1] -eq '*')
            if ($isDouble) {
                # Is this a "**/" segment (globstar followed by a separator)?
                if ($i + 2 -lt $len -and $Glob[$i + 2] -eq '/') {
                    # Match zero or more leading directory segments. The '?' makes
                    # the whole "dir/" optional so "**/foo" also matches "foo".
                    [void]$sb.Append('(?:.*/)?')
                    $i += 3
                }
                else {
                    # Bare "**": match anything, crossing directory boundaries.
                    [void]$sb.Append('.*')
                    $i += 2
                }
            }
            else {
                # Single "*": match within a single path segment only.
                [void]$sb.Append('[^/]*')
                $i += 1
            }
        }
        elseif ($c -eq '?') {
            [void]$sb.Append('[^/]')
            $i += 1
        }
        else {
            # Escape any character that is special in regex so it matches literally.
            [void]$sb.Append([regex]::Escape([string]$c))
            $i += 1
        }
    }

    [void]$sb.Append('$')
    return $sb.ToString()
}

function Test-GlobMatch {
    <#
    .SYNOPSIS
        Return $true if the given path matches the given glob pattern.

    .DESCRIPTION
        Matching is case-sensitive on purpose: file paths in git are
        case-sensitive, and we do not want "*.test.*" to accidentally also
        match "Foo.Tests.ps1". The .NET regex engine is case-sensitive by
        default, which gives us exactly that behaviour.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Path,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Glob
    )

    $regex = ConvertTo-GlobRegex -Glob $Glob
    return [regex]::IsMatch($Path, $regex)
}

function Get-PRLabels {
    <#
    .SYNOPSIS
        Resolve the final, ordered set of labels for a list of changed files.

    .DESCRIPTION
        For every changed file we test every rule. Each rule that matches
        contributes all of its labels. A label may be contributed by several
        rules (across one or more files); when that happens the label keeps the
        HIGHEST priority of any rule that produced it.

        The returned set is de-duplicated and ordered:
          1. priority, descending  (most important labels first)
          2. label name, ascending (deterministic tie-break)

    .OUTPUTS
        [string[]] - the ordered label set (empty array when nothing matches).
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

    # Map of label -> highest priority seen for that label.
    $labelPriority = @{}

    foreach ($file in $ChangedFiles) {
        foreach ($rule in $Rules) {
            if (-not (Test-GlobMatch -Path $file -Glob $rule.pattern)) { continue }

            # A missing/blank priority is treated as 0 (lowest).
            $priority = 0
            if ($rule.PSObject.Properties.Match('priority').Count -gt 0 -and $null -ne $rule.priority) {
                $priority = [int]$rule.priority
            }

            foreach ($label in $rule.labels) {
                if (-not $labelPriority.ContainsKey($label) -or $labelPriority[$label] -lt $priority) {
                    $labelPriority[$label] = $priority
                }
            }
        }
    }

    if ($labelPriority.Count -eq 0) { return , [string[]]@() }

    $ordered = $labelPriority.GetEnumerator() |
        Sort-Object `
            @{ Expression = { $_.Value }; Descending = $true }, `
            @{ Expression = { $_.Key };   Descending = $false } |
        ForEach-Object { $_.Key }

    # The unary comma stops PowerShell from unwrapping a single-element result.
    return , [string[]]$ordered
}

function Import-LabelConfig {
    <#
    .SYNOPSIS
        Load and validate a labeler config JSON file, returning its rules.

    .DESCRIPTION
        The config file is JSON of the form:
            { "rules": [ { "pattern": "...", "labels": ["..."], "priority": N }, ... ] }
        'priority' is optional (defaults to 0). Every error condition produces a
        clear, actionable message rather than a raw parser exception.

    .OUTPUTS
        [object[]] - normalised rule objects (pattern, labels, priority).
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Config file not found: '$Path'"
    }

    $raw = Get-Content -LiteralPath $Path -Raw

    try {
        $config = $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Invalid JSON in config file '$Path': $($_.Exception.Message)"
    }

    if ($null -eq $config -or $config.PSObject.Properties.Match('rules').Count -eq 0) {
        throw "Config file '$Path' must contain a 'rules' array."
    }

    $rules = @($config.rules)

    # Normalise and validate each rule, reporting the offending index on failure.
    $normalised = for ($idx = 0; $idx -lt $rules.Count; $idx++) {
        $rule = $rules[$idx]

        if ($rule.PSObject.Properties.Match('pattern').Count -eq 0 -or
            [string]::IsNullOrWhiteSpace([string]$rule.pattern)) {
            throw "Config file '$Path' rule $idx is missing a non-empty 'pattern'."
        }

        if ($rule.PSObject.Properties.Match('labels').Count -eq 0 -or
            $null -eq $rule.labels -or @($rule.labels).Count -eq 0) {
            throw "Config file '$Path' rule $idx is missing a non-empty 'labels' array."
        }

        $priority = 0
        if ($rule.PSObject.Properties.Match('priority').Count -gt 0 -and $null -ne $rule.priority) {
            $priority = [int]$rule.priority
        }

        [pscustomobject]@{
            pattern  = [string]$rule.pattern
            labels   = [string[]]@($rule.labels)
            priority = $priority
        }
    }

    return , [object[]]@($normalised)
}

function Get-ChangedFileList {
    <#
    .SYNOPSIS
        Read a "changed files" list (one path per line) from disk.

    .DESCRIPTION
        Blank lines and lines beginning with '#' (after trimming) are ignored,
        and each remaining path is trimmed of surrounding whitespace. This is the
        mock "PR changed files" input used by the tests and the CI workflow.

    .OUTPUTS
        [string[]] - the cleaned list of changed file paths.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Changed-files list not found: '$Path'"
    }

    $lines = Get-Content -LiteralPath $Path

    $files = foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ($trimmed -eq '' -or $trimmed.StartsWith('#')) { continue }
        $trimmed
    }

    return , [string[]]@($files)
}

Export-ModuleMember -Function ConvertTo-GlobRegex, Test-GlobMatch, Get-PRLabels,
    Import-LabelConfig, Get-ChangedFileList
