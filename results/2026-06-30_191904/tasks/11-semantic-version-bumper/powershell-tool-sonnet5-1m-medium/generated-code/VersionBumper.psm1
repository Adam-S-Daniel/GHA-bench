# VersionBumper.psm1
#
# A small semantic-version bumping toolkit driven by Conventional Commits.
# Each function below was implemented to satisfy a failing Pester test in
# tests/VersionBumper.Tests.ps1 (red -> green -> refactor).

Set-StrictMode -Version Latest

$script:SemVerPattern = '^\d+\.\d+\.\d+$'

function Get-CurrentVersion {
    <#
    .SYNOPSIS
        Reads the current semantic version from a plain VERSION file or a
        package.json file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -Path $Path)) {
        throw "Version file not found: '$Path'"
    }

    $raw = Get-Content -Path $Path -Raw

    if ((Split-Path -Path $Path -Extension) -eq '.json') {
        try {
            $json = $raw | ConvertFrom-Json
        } catch {
            throw "Failed to parse package.json at '$Path': $($_.Exception.Message)"
        }

        if (-not $json.PSObject.Properties.Match('version') -or [string]::IsNullOrWhiteSpace($json.version)) {
            throw "package.json at '$Path' does not contain a 'version' field"
        }

        $version = $json.version
    } else {
        $version = $raw.Trim()
    }

    if ($version -notmatch $script:SemVerPattern) {
        throw "'$version' in '$Path' is not a valid semantic version (expected MAJOR.MINOR.PATCH)"
    }

    return $version
}

function Get-CommitBumpType {
    <#
    .SYNOPSIS
        Inspects an array of conventional-commit messages and returns the
        highest-impact bump type: 'major', 'minor', 'patch', or 'none'.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Commits
    )

    if ($Commits.Count -eq 0) {
        throw 'At least one commit message is required to determine the bump type'
    }

    $highest = 'none'
    $rank = @{ none = 0; patch = 1; minor = 2; major = 3 }

    foreach ($commit in $Commits) {
        $bump = 'none'

        # Breaking changes: a '!' before the ':' in the header, or a
        # 'BREAKING CHANGE:' footer anywhere in the commit message.
        if ($commit -match '^\w+(\([^)]*\))?!:' -or $commit -match 'BREAKING CHANGE:') {
            $bump = 'major'
        } elseif ($commit -match '^feat(\([^)]*\))?:') {
            $bump = 'minor'
        } elseif ($commit -match '^fix(\([^)]*\))?:') {
            $bump = 'patch'
        }

        if ($rank[$bump] -gt $rank[$highest]) {
            $highest = $bump
        }
    }

    return $highest
}

function Get-NextVersion {
    <#
    .SYNOPSIS
        Computes the next semantic version given a current version and a
        bump type ('major', 'minor', 'patch', or 'none').
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^\d+\.\d+\.\d+$')]
        [string]$Version,

        [Parameter(Mandatory)]
        [string]$BumpType
    )

    $parts = $Version.Split('.')
    [int]$major = $parts[0]
    [int]$minor = $parts[1]
    [int]$patch = $parts[2]

    switch ($BumpType) {
        'major' { $major++; $minor = 0; $patch = 0 }
        'minor' { $minor++; $patch = 0 }
        'patch' { $patch++ }
        'none'  { }
        default { throw "Invalid bump type: '$BumpType'. Expected 'major', 'minor', 'patch', or 'none'." }
    }

    return "$major.$minor.$patch"
}

function Update-VersionFile {
    <#
    .SYNOPSIS
        Writes a new version into a plain VERSION file or a package.json
        file, preserving all other fields in package.json.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [ValidatePattern('^\d+\.\d+\.\d+$')]
        [string]$NewVersion
    )

    if (-not (Test-Path -Path $Path)) {
        throw "Version file not found: '$Path'"
    }

    if ((Split-Path -Path $Path -Extension) -eq '.json') {
        $json = Get-Content -Path $Path -Raw | ConvertFrom-Json
        $json.version = $NewVersion
        ($json | ConvertTo-Json -Depth 10) | Set-Content -Path $Path -NoNewline
    } else {
        Set-Content -Path $Path -Value $NewVersion -NoNewline
    }
}

function New-ChangelogEntry {
    <#
    .SYNOPSIS
        Builds a Markdown changelog entry from a list of conventional-commit
        messages, grouped under Breaking Changes / Features / Fixes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Version,

        [Parameter(Mandatory)]
        [string[]]$Commits,

        [Parameter(Mandatory)]
        [string]$Date
    )

    $breaking = [System.Collections.Generic.List[string]]::new()
    $features = [System.Collections.Generic.List[string]]::new()
    $fixes = [System.Collections.Generic.List[string]]::new()

    foreach ($commit in $Commits) {
        $header = ($commit -split "`n")[0]
        $description = $header -replace '^\w+(\([^)]*\))?!?:\s*', ''

        if ($header -match '^\w+(\([^)]*\))?!:' -or $commit -match 'BREAKING CHANGE:') {
            $breaking.Add($description)
        } elseif ($header -match '^feat(\([^)]*\))?:') {
            $features.Add($description)
        } elseif ($header -match '^fix(\([^)]*\))?:') {
            $fixes.Add($description)
        }
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("## [$Version] - $Date")
    $lines.Add('')

    if ($breaking.Count -gt 0) {
        $lines.Add('### Breaking Changes')
        foreach ($item in $breaking) { $lines.Add("- $item") }
        $lines.Add('')
    }

    if ($features.Count -gt 0) {
        $lines.Add('### Features')
        foreach ($item in $features) { $lines.Add("- $item") }
        $lines.Add('')
    }

    if ($fixes.Count -gt 0) {
        $lines.Add('### Fixes')
        foreach ($item in $fixes) { $lines.Add("- $item") }
        $lines.Add('')
    }

    return ($lines -join "`n")
}

function Invoke-SemanticVersionBump {
    <#
    .SYNOPSIS
        End-to-end orchestration: reads the current version, determines the
        bump type from a commit log file, computes and writes the new
        version, and prepends a changelog entry.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$VersionFilePath,

        [Parameter(Mandatory)]
        [string]$CommitLogPath,

        [Parameter(Mandatory)]
        [string]$ChangelogPath,

        [string]$Date = (Get-Date -Format 'yyyy-MM-dd')
    )

    if (-not (Test-Path -Path $CommitLogPath)) {
        throw "Commit log file not found: '$CommitLogPath'"
    }

    $commits = Get-Content -Path $CommitLogPath | Where-Object { $_.Trim() -ne '' }
    if (@($commits).Count -eq 0) {
        throw "Commit log file '$CommitLogPath' contains no commit messages"
    }

    $previousVersion = Get-CurrentVersion -Path $VersionFilePath
    $bumpType = Get-CommitBumpType -Commits $commits
    $newVersion = Get-NextVersion -Version $previousVersion -BumpType $bumpType

    Update-VersionFile -Path $VersionFilePath -NewVersion $newVersion

    $entry = New-ChangelogEntry -Version $newVersion -Commits $commits -Date $Date

    if (Test-Path -Path $ChangelogPath) {
        $existing = Get-Content -Path $ChangelogPath -Raw
    } else {
        $existing = "# Changelog`n"
    }

    # Insert the new entry right after the top-level "# Changelog" heading.
    $headingMatch = [regex]::Match($existing, '^#\s+Changelog\s*\n')
    if ($headingMatch.Success) {
        $insertAt = $headingMatch.Index + $headingMatch.Length
        $updated = $existing.Substring(0, $insertAt) + "`n$entry`n" + $existing.Substring($insertAt)
    } else {
        $updated = "$entry`n`n$existing"
    }

    Set-Content -Path $ChangelogPath -Value $updated -NoNewline

    return [PSCustomObject]@{
        PreviousVersion = $previousVersion
        NewVersion      = $newVersion
        BumpType        = $bumpType
        ChangelogEntry  = $entry
    }
}

Export-ModuleMember -Function Get-CurrentVersion, Get-CommitBumpType, Get-NextVersion, Update-VersionFile, New-ChangelogEntry, Invoke-SemanticVersionBump
