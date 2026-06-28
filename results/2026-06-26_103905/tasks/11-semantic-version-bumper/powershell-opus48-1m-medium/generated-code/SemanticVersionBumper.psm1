# SemanticVersionBumper.psm1
# A small library that:
#   * reads a semantic version from a version file or package.json
#   * inspects conventional-commit messages to decide the bump (major/minor/patch)
#   * computes the next version
#   * writes the new version back
#   * generates a Keep-a-Changelog style entry
#
# Built incrementally with red/green TDD (see tests/SemanticVersionBumper.Tests.ps1).

Set-StrictMode -Version Latest

function Get-CurrentVersion {
    <#
    .SYNOPSIS
        Reads the current semantic version from a version file or package.json.
    .DESCRIPTION
        If the file is JSON containing a "version" field (e.g. package.json) the
        version is read from that property. Otherwise the file is treated as a
        plain text file whose trimmed contents are the version string.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Version file not found: '$Path'"
    }

    $raw = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "Version file '$Path' is empty."
    }

    # Detect package.json (or any JSON object exposing a "version" field).
    $isJson = ([System.IO.Path]::GetFileName($Path) -eq 'package.json') -or
              ($raw.TrimStart().StartsWith('{'))
    if ($isJson) {
        try {
            $obj = $raw | ConvertFrom-Json
        } catch {
            throw "Could not parse JSON in '$Path': $($_.Exception.Message)"
        }
        if (-not $obj.PSObject.Properties.Name.Contains('version')) {
            throw "JSON file '$Path' has no 'version' field."
        }
        return [string]$obj.version
    }

    return $raw.Trim()
}

function Get-VersionBumpType {
    <#
    .SYNOPSIS
        Determines the semantic bump (major/minor/patch/none) implied by a set
        of conventional-commit messages.
    .DESCRIPTION
        Precedence (highest wins):
          major - a "BREAKING CHANGE" footer, or a "!" before the colon (feat!:)
          minor - a "feat" commit
          patch - a "fix" commit
          none  - anything else (chore, docs, style, refactor, test, ...)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Commits
    )

    $bump = 'none'
    foreach ($commit in $Commits) {
        if ([string]::IsNullOrWhiteSpace($commit)) { continue }

        # The conventional-commit "type" lives on the first line (the subject).
        $subject = ($commit -split "`r?`n")[0]

        # Breaking change: "type!:" / "type(scope)!:" in the subject, or a
        # "BREAKING CHANGE" / "BREAKING-CHANGE" footer anywhere in the body.
        if ($subject -match '^\s*[a-zA-Z]+(\([^)]*\))?!\s*:' -or
            $commit  -match '(?m)^\s*BREAKING[ -]CHANGE') {
            return 'major'  # nothing outranks major; short-circuit.
        }

        if ($subject -match '^\s*feat(\([^)]*\))?\s*:') {
            $bump = 'minor'
            continue
        }

        if ($subject -match '^\s*fix(\([^)]*\))?\s*:') {
            if ($bump -ne 'minor') { $bump = 'patch' }
        }
    }

    return $bump
}

function Get-NextVersion {
    <#
    .SYNOPSIS
        Computes the next semantic version given a current version and bump type.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$CurrentVersion,
        [Parameter(Mandatory)] [ValidateSet('major', 'minor', 'patch', 'none')]
        [string]$BumpType
    )

    # Tolerate an optional leading "v".
    $clean = $CurrentVersion.Trim().TrimStart('v', 'V')

    if ($clean -notmatch '^(\d+)\.(\d+)\.(\d+)$') {
        throw "'$CurrentVersion' is not a valid semantic version (expected MAJOR.MINOR.PATCH)."
    }

    $major = [int]$Matches[1]
    $minor = [int]$Matches[2]
    $patch = [int]$Matches[3]

    switch ($BumpType) {
        'major' { $major++; $minor = 0; $patch = 0 }
        'minor' { $minor++; $patch = 0 }
        'patch' { $patch++ }
        'none'  { } # unchanged
    }

    return "$major.$minor.$patch"
}

function Update-VersionFile {
    <#
    .SYNOPSIS
        Writes the new version back to the version file.
    .DESCRIPTION
        For package.json the "version" field is replaced in place while keeping
        all other content/formatting via a targeted regex substitution. For a
        plain version file the contents are simply overwritten.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$NewVersion
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Version file not found: '$Path'"
    }

    $raw = Get-Content -LiteralPath $Path -Raw
    $isJson = ([System.IO.Path]::GetFileName($Path) -eq 'package.json') -or
              ($raw.TrimStart().StartsWith('{'))

    if ($isJson) {
        # Replace just the version value, preserving the rest of the JSON text.
        $updated = [regex]::Replace(
            $raw,
            '("version"\s*:\s*")[^"]*(")',
            "`${1}$NewVersion`${2}",
            [System.Text.RegularExpressions.RegexOptions]::None)
        if ($updated -eq $raw) {
            throw "Could not find a 'version' field to update in '$Path'."
        }
        Set-Content -LiteralPath $Path -Value $updated -NoNewline
    } else {
        Set-Content -LiteralPath $Path -Value $NewVersion
    }
}

function New-ChangelogEntry {
    <#
    .SYNOPSIS
        Produces a Keep-a-Changelog style markdown entry from commit messages.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Version,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]]$Commits,
        [Parameter(Mandatory)] [string]$Date
    )

    $features = [System.Collections.Generic.List[string]]::new()
    $fixes    = [System.Collections.Generic.List[string]]::new()
    $breaking = [System.Collections.Generic.List[string]]::new()

    foreach ($commit in $Commits) {
        if ([string]::IsNullOrWhiteSpace($commit)) { continue }
        $subject = ($commit -split "`r?`n")[0].Trim()

        # Strip the "type(scope)!:" prefix to get a clean human description.
        $desc = [regex]::Replace($subject, '^\s*[a-zA-Z]+(\([^)]*\))?!?\s*:\s*', '')

        if ($subject -match '^\s*[a-zA-Z]+(\([^)]*\))?!\s*:' -or
            $commit  -match '(?m)^\s*BREAKING[ -]CHANGE') {
            $breaking.Add($desc)
        } elseif ($subject -match '^\s*feat(\([^)]*\))?\s*:') {
            $features.Add($desc)
        } elseif ($subject -match '^\s*fix(\([^)]*\))?\s*:') {
            $fixes.Add($desc)
        }
    }

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("## [$Version] - $Date")

    if ($breaking.Count) {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('### BREAKING CHANGES')
        foreach ($b in $breaking) { [void]$sb.AppendLine("- $b") }
    }
    if ($features.Count) {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('### Features')
        foreach ($f in $features) { [void]$sb.AppendLine("- $f") }
    }
    if ($fixes.Count) {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('### Bug Fixes')
        foreach ($x in $fixes) { [void]$sb.AppendLine("- $x") }
    }

    return $sb.ToString().TrimEnd()
}

function Get-CommitsFromLog {
    <#
    .SYNOPSIS
        Reads commit messages from a fixture log file.
    .DESCRIPTION
        Two formats are supported:
          * Simple: one commit subject per line (blank lines ignored).
          * Multi-line: commits separated by a literal "---COMMIT---" delimiter,
            so commit bodies (e.g. BREAKING CHANGE footers) survive intact.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Commit log file not found: '$Path'"
    }

    $raw = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) { return @() }

    if ($raw -match '---COMMIT---') {
        return $raw -split '---COMMIT---' |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -ne '' }
    }

    return $raw -split "`r?`n" |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -ne '' }
}

function Invoke-VersionBump {
    <#
    .SYNOPSIS
        End-to-end orchestration: read version + commits, compute next version,
        update the version file and prepend a changelog entry.
    .OUTPUTS
        A PSCustomObject with OldVersion, NewVersion, BumpType and ChangelogEntry.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$VersionFilePath,
        [Parameter(Mandatory)] [string]$CommitLogPath,
        [Parameter()] [string]$ChangelogPath,
        [Parameter()] [string]$Date
    )

    $oldVersion = Get-CurrentVersion -Path $VersionFilePath
    $commits    = Get-CommitsFromLog -Path $CommitLogPath
    $bumpType   = Get-VersionBumpType -Commits $commits
    $newVersion = Get-NextVersion -CurrentVersion $oldVersion -BumpType $bumpType

    # Default the date here rather than in the param block so it stays
    # deterministic when callers (and tests) supply an explicit date.
    if ([string]::IsNullOrWhiteSpace($Date)) {
        $Date = (Get-Date -Format 'yyyy-MM-dd')
    }

    $entry = New-ChangelogEntry -Version $newVersion -Commits $commits -Date $Date

    # Only mutate files when there is actually a bump to apply.
    if ($bumpType -ne 'none') {
        Update-VersionFile -Path $VersionFilePath -NewVersion $newVersion

        if ($ChangelogPath) {
            $existing = ''
            if (Test-Path -LiteralPath $ChangelogPath) {
                $existing = Get-Content -LiteralPath $ChangelogPath -Raw
            }
            if ([string]::IsNullOrWhiteSpace($existing)) {
                $header = "# Changelog`n`nAll notable changes to this project are documented here.`n`n"
                Set-Content -LiteralPath $ChangelogPath -Value ($header + $entry + "`n")
            } else {
                # Prepend the new entry above older entries (newest first).
                Set-Content -LiteralPath $ChangelogPath -Value ($entry + "`n`n" + $existing)
            }
        }
    }

    return [PSCustomObject]@{
        OldVersion     = $oldVersion
        NewVersion     = $newVersion
        BumpType       = $bumpType
        ChangelogEntry = $entry
    }
}

Export-ModuleMember -Function Get-CurrentVersion, Get-VersionBumpType, Get-NextVersion,
    Update-VersionFile, New-ChangelogEntry, Get-CommitsFromLog, Invoke-VersionBump
