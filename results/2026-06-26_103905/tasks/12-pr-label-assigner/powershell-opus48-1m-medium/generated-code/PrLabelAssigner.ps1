#Requires -Version 7.0
<#
.SYNOPSIS
    PR Label Assigner — apply labels to a PR based on its changed files.

.DESCRIPTION
    Given a list of changed file paths (simulating a PR's changed files) and a
    set of configurable path-to-label mapping rules, this script computes the
    final set of labels that should be applied to the PR.

    Features:
      * Glob patterns ( *, **, ?, **/ ) for matching file paths to rules.
      * Multiple labels per rule, and multiple rules matching one file.
      * Priority ordering: the final label set is ordered by the highest
        priority of any rule that produced each label (highest first, ties
        broken alphabetically).
      * Exclusive rules: a rule marked `exclusive` suppresses all
        lower-priority labels for the *file* it matches, used to resolve
        conflicts (e.g. a "generated/**" rule that should win outright).

.PARAMETER ChangedFiles
    Path to a JSON file containing an array of changed file paths.

.PARAMETER Config
    Path to a JSON config file with a `rules` array.

.PARAMETER AsJson
    Emit the resulting label set as a JSON array instead of a comma list.

.EXAMPLE
    ./PrLabelAssigner.ps1 -ChangedFiles fixtures/changed-files.json -Config fixtures/config.json
#>
[CmdletBinding()]
param(
    [string] $ChangedFiles,
    [string] $Config,
    [switch] $AsJson
)

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# Convert-GlobToRegex
#   Translate a glob pattern into an anchored .NET regex string.
#   Rules:
#     **/   -> match zero or more leading path segments (any depth prefix)
#     **    -> match anything, including slashes
#     *     -> match anything except a slash (within one path segment)
#     ?     -> match a single non-slash character
#   All other characters are regex-escaped so metacharacters like '.' or '+'
#   are treated literally.
# ---------------------------------------------------------------------------
function Convert-GlobToRegex {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Glob)

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append('^')

    $i = 0
    $len = $Glob.Length
    while ($i -lt $len) {
        $c = $Glob[$i]
        switch ($c) {
            '*' {
                if ($i + 1 -lt $len -and $Glob[$i + 1] -eq '*') {
                    # We have at least '**'. If it is the '**/' prefix form,
                    # allow it to match nothing OR any number of segments.
                    if ($i + 2 -lt $len -and $Glob[$i + 2] -eq '/') {
                        [void]$sb.Append('(?:.*/)?')
                        $i += 3
                    } else {
                        # Bare '**' matches anything, including slashes.
                        [void]$sb.Append('.*')
                        $i += 2
                    }
                } else {
                    # Single '*' matches within a path segment (no slash).
                    [void]$sb.Append('[^/]*')
                    $i += 1
                }
            }
            '?' {
                [void]$sb.Append('[^/]')
                $i += 1
            }
            default {
                # Escape any single character so regex metacharacters are literal.
                [void]$sb.Append([regex]::Escape([string]$c))
                $i += 1
            }
        }
    }

    [void]$sb.Append('$')
    return $sb.ToString()
}

# ---------------------------------------------------------------------------
# Test-GlobMatch
#   Return $true when $Path matches the glob $Glob.
# ---------------------------------------------------------------------------
function Test-GlobMatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Glob
    )
    $regex = Convert-GlobToRegex -Glob $Glob
    return [regex]::IsMatch($Path, $regex)
}

# ---------------------------------------------------------------------------
# Get-PrLabels
#   Core engine. Given the changed files and the rules, compute the ordered,
#   de-duplicated label set.
#
#   Algorithm:
#     1. For each file, find every matching rule.
#     2. If any matching rule is `exclusive`, keep only the labels of the
#        highest-priority exclusive rule for that file (conflict resolution).
#        Otherwise keep labels from all matching rules.
#     3. Record, per label, the highest priority that produced it.
#     4. Output unique labels ordered by priority desc, then alphabetically.
# ---------------------------------------------------------------------------
function Get-PrLabels {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $ChangedFiles,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Rules
    )

    # Map of label -> highest priority seen for that label.
    $labelPriority = @{}

    foreach ($file in $ChangedFiles) {
        # Collect all rules that match this file.
        $matched = foreach ($rule in $Rules) {
            if (Test-GlobMatch -Path $file -Glob $rule.pattern) { $rule }
        }
        if (-not $matched) { continue }

        # Conflict resolution: if any matched rule is exclusive, the highest
        # priority exclusive rule wins outright for this file.
        $exclusive = $matched | Where-Object { ($_.PSObject.Properties.Name -contains 'exclusive') -and $_.exclusive } |
            Sort-Object -Property priority -Descending | Select-Object -First 1
        if ($exclusive) {
            $matched = @($exclusive)
        }

        foreach ($rule in $matched) {
            foreach ($label in $rule.labels) {
                if (-not $labelPriority.ContainsKey($label) -or $rule.priority -gt $labelPriority[$label]) {
                    $labelPriority[$label] = [int]$rule.priority
                }
            }
        }
    }

    # Order by priority (highest first), then alphabetically for stable ties.
    $ordered = $labelPriority.Keys |
        Sort-Object -Property @{ Expression = { $labelPriority[$_] }; Descending = $true }, @{ Expression = { $_ }; Descending = $false }

    return @($ordered)
}

# ---------------------------------------------------------------------------
# Get-RuleConfig
#   Load and validate the rules config JSON.
# ---------------------------------------------------------------------------
function Get-RuleConfig {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Config file not found: '$Path'"
    }

    $raw = Get-Content -LiteralPath $Path -Raw
    try {
        $cfg = $raw | ConvertFrom-Json
    } catch {
        throw "Failed to parse config JSON '$Path': $($_.Exception.Message)"
    }

    if (-not ($cfg.PSObject.Properties.Name -contains 'rules')) {
        throw "Config '$Path' is missing the required 'rules' array."
    }

    return @($cfg.rules)
}

# ---------------------------------------------------------------------------
# Get-ChangedFileList
#   Load the changed-files JSON (a plain array of path strings).
# ---------------------------------------------------------------------------
function Get-ChangedFileList {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Changed files list not found: '$Path'"
    }

    $raw = Get-Content -LiteralPath $Path -Raw
    try {
        $files = $raw | ConvertFrom-Json
    } catch {
        throw "Failed to parse changed-files JSON '$Path': $($_.Exception.Message)"
    }

    return @($files)
}

# ---------------------------------------------------------------------------
# Main execution guard.
#   When this file is dot-sourced (e.g. by the Pester tests), $MyInvocation.
#   InvocationName is '.', so the main block is skipped and only the functions
#   are exported. When run directly it parses inputs and prints the labels.
# ---------------------------------------------------------------------------
if ($MyInvocation.InvocationName -ne '.') {
    try {
        if (-not $ChangedFiles) { throw "The -ChangedFiles parameter is required." }
        if (-not $Config)       { throw "The -Config parameter is required." }

        $rules = Get-RuleConfig -Path $Config
        $files = Get-ChangedFileList -Path $ChangedFiles
        $labels = Get-PrLabels -ChangedFiles $files -Rules $rules

        if ($AsJson) {
            # ConvertTo-Json on a single-element array collapses to a scalar,
            # so force an array wrapper for predictable output.
            Write-Output (,$labels | ConvertTo-Json -Compress)
        } else {
            # Human / CI friendly single line. The workflow asserts on this.
            Write-Output ("Labels: " + ($labels -join ', '))
        }

        # When running inside GitHub Actions, also expose the labels as a step
        # output so downstream steps/jobs (e.g. the labeler API) can consume it.
        if ($env:GITHUB_OUTPUT) {
            "labels=$($labels -join ',')" | Add-Content -Path $env:GITHUB_OUTPUT
        }
    } catch {
        Write-Error "PR Label Assigner failed: $($_.Exception.Message)"
        exit 1
    }
}
