#!/usr/bin/env pwsh
<#
    PrLabelAssigner.ps1

    Assigns PR labels to a list of changed file paths based on a configurable
    set of glob-pattern -> label rules (with optional priority-based conflict
    resolution). Designed to be dot-sourced by tests, or invoked directly as a
    CLI script (e.g. from a GitHub Actions workflow step).

    Rule schema (JSON array):
      [
        { "Pattern": "docs/**", "Label": "documentation" },
        { "Pattern": "src/**", "Label": "code", "Priority": 10, "ConflictGroup": "area" },
        { "Pattern": "src/legacy/**", "Label": "legacy", "Priority": 1, "ConflictGroup": "area" }
      ]

    - Pattern (required): a glob. Patterns containing '/' are matched against
      the full relative file path; patterns without '/' are matched against
      just the file's base name (like a .gitignore single-segment pattern),
      so "*.test.*" matches "src/api/foo.test.js" regardless of directory.
    - Label (required): the label to apply when the pattern matches.
    - Priority (optional, default 0): lower number = higher priority.
    - ConflictGroup (optional): rules sharing the same ConflictGroup are
      mutually exclusive per file -- only the matching rule with the lowest
      Priority contributes its label for that file. Rules without a
      ConflictGroup never conflict, which is how a single file can pick up
      multiple independent labels.
#>

param(
    [string]$ChangedFilesPath,
    [string]$RulesPath = "$PSScriptRoot/rules.json",
    [ValidateSet('text', 'json')]
    [string]$OutputFormat = 'text'
)

# --- Glob matching -----------------------------------------------------

function Convert-GlobToRegex {
    <#
        Converts a shell-style glob into an anchored .NET regex string.
        '**' matches any sequence of characters, including '/'.
        '*'  matches any sequence of characters except '/'.
        '?'  matches any single character except '/'.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Glob
    )

    $escaped = [regex]::Escape($Glob)
    # [regex]::Escape turns '*' into '\*' and '?' into '\?'; substitute in an
    # order-safe way so '**' isn't first converted into two single '*'s.
    $escaped = $escaped -replace '\\\*\\\*', "`0DOUBLESTAR`0"
    $escaped = $escaped -replace '\\\*', '[^/]*'
    $escaped = $escaped -replace "`0DOUBLESTAR`0", '.*'
    $escaped = $escaped -replace '\\\?', '[^/]'

    return "^$escaped`$"
}

function Test-PathMatchesGlob {
    <#
        Tests whether a relative file path matches a glob pattern.
        Path-based globs (containing '/') match against the full path.
        Name-based globs (no '/') match against just the file's base name.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Glob
    )

    if ([string]::IsNullOrWhiteSpace($Glob)) {
        throw "Test-PathMatchesGlob: glob pattern must not be null or empty."
    }

    $normalizedPath = $Path -replace '\\', '/'
    $target = if ($Glob.Contains('/')) {
        $normalizedPath
    }
    else {
        Split-Path -Path $normalizedPath -Leaf
    }

    $regex = Convert-GlobToRegex -Glob $Glob
    return $target -match $regex
}

# --- Rule loading --------------------------------------------------------

function Import-LabelRules {
    <#
        Loads and validates a JSON rules file, returning an array of rule
        objects. Throws a descriptive error if the file is missing or a rule
        is malformed.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$RulesPath
    )

    if (-not (Test-Path -Path $RulesPath -PathType Leaf)) {
        throw "Rules file not found: $RulesPath"
    }

    try {
        $raw = Get-Content -Path $RulesPath -Raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Rules file at '$RulesPath' is not valid JSON: $($_.Exception.Message)"
    }

    $rules = @($raw)
    for ($i = 0; $i -lt $rules.Count; $i++) {
        $rule = $rules[$i]
        if (-not $rule.PSObject.Properties['Pattern'] -or [string]::IsNullOrWhiteSpace($rule.Pattern)) {
            throw "Invalid rule at index $i in '$RulesPath': missing required field 'Pattern'."
        }
        if (-not $rule.PSObject.Properties['Label'] -or [string]::IsNullOrWhiteSpace($rule.Label)) {
            throw "Invalid rule at index $i in '$RulesPath': missing required field 'Label'."
        }
        if (-not $rule.PSObject.Properties['Priority'] -or $null -eq $rule.Priority) {
            $rule | Add-Member -MemberType NoteProperty -Name Priority -Value 0 -Force
        }
        if (-not $rule.PSObject.Properties['ConflictGroup']) {
            $rule | Add-Member -MemberType NoteProperty -Name ConflictGroup -Value $null -Force
        }
    }

    return $rules
}

# --- Label resolution ------------------------------------------------------

function Get-FileLabels {
    <#
        Returns the array of labels that apply to a single changed file,
        resolving same-ConflictGroup rule conflicts by Priority (lowest wins).
    #>
    param(
        [Parameter(Mandatory)]
        [string]$File,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [array]$Rules
    )

    $matched = @($Rules | Where-Object { Test-PathMatchesGlob -Path $File -Glob $_.Pattern })
    if ($matched.Count -eq 0) {
        return @()
    }

    $labels = New-Object System.Collections.Generic.List[string]

    # Rules without a ConflictGroup always contribute their label independently.
    foreach ($rule in ($matched | Where-Object { [string]::IsNullOrEmpty($_.ConflictGroup) })) {
        $labels.Add($rule.Label)
    }

    # Rules sharing a ConflictGroup are mutually exclusive: only the
    # lowest-Priority match in each group contributes.
    $grouped = $matched | Where-Object { -not [string]::IsNullOrEmpty($_.ConflictGroup) } |
        Group-Object -Property ConflictGroup
    foreach ($group in $grouped) {
        $winner = $group.Group | Sort-Object -Property Priority | Select-Object -First 1
        $labels.Add($winner.Label)
    }

    return , @($labels)
}

function Get-PrLabels {
    <#
        Computes the final, de-duplicated, sorted set of labels for an entire
        set of changed files.
    #>
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [array]$ChangedFiles,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [array]$Rules
    )

    $allLabels = New-Object System.Collections.Generic.List[string]
    foreach ($file in $ChangedFiles) {
        foreach ($label in (Get-FileLabels -File $file -Rules $Rules)) {
            $allLabels.Add($label)
        }
    }

    $unique = @($allLabels | Select-Object -Unique | Sort-Object)
    return , $unique
}

# --- CLI entrypoint --------------------------------------------------------
# Only runs when the script is executed directly (not dot-sourced by tests).

if ($MyInvocation.InvocationName -ne '.' -and $PSCommandPath -eq $MyInvocation.MyCommand.Path -and $ChangedFilesPath) {
    if (-not (Test-Path -Path $ChangedFilesPath -PathType Leaf)) {
        throw "Changed files list not found: $ChangedFilesPath"
    }

    $changedFiles = @(Get-Content -Path $ChangedFilesPath -Raw | ConvertFrom-Json -ErrorAction Stop)
    $rules = Import-LabelRules -RulesPath $RulesPath
    $labels = Get-PrLabels -ChangedFiles $changedFiles -Rules $rules

    if ($OutputFormat -eq 'json') {
        $labelsJson = ($labels | ConvertTo-Json -Compress -AsArray)
        Write-Output $labelsJson
    }
    else {
        Write-Output "Labels: $($labels -join ',')"
    }

    if ($env:GITHUB_OUTPUT) {
        $labelsJson = ($labels | ConvertTo-Json -Compress -AsArray)
        Add-Content -Path $env:GITHUB_OUTPUT -Value "labels=$($labels -join ',')"
        Add-Content -Path $env:GITHUB_OUTPUT -Value "labels_json=$labelsJson"
    }

    if ($env:GITHUB_STEP_SUMMARY) {
        $summaryLines = @("### PR Label Assigner", "")
        if ($labels.Count -eq 0) {
            $summaryLines += "No labels matched."
        }
        else {
            $summaryLines += ($labels | ForEach-Object { "- ``$_``" })
        }
        Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value ($summaryLines -join "`n")
    }
}
