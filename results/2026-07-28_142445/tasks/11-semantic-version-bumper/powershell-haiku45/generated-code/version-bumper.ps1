<#
.SYNOPSIS
Semantic version bumper with conventional commit parsing.
Parses version files, determines next version based on commits,
and generates changelog entries.
#>

function Parse-SemanticVersion {
    <#
    .SYNOPSIS
    Parses a semantic version string (e.g., "1.2.3" or "v1.2.3")
    .PARAMETER Version
    The version string to parse
    .RETURNS
    PSCustomObject with Major, Minor, Patch properties
    #>
    param([string]$Version)

    # Remove leading 'v' if present
    $cleanVersion = $Version -replace '^v', ''

    # Match semantic version pattern
    if ($cleanVersion -match '^(\d+)\.(\d+)\.(\d+)$') {
        return [PSCustomObject]@{
            Major = [int]$matches[1]
            Minor = [int]$matches[2]
            Patch = [int]$matches[3]
        }
    }

    throw "Invalid semantic version format: $Version"
}

function Get-NextVersion {
    <#
    .SYNOPSIS
    Determines the next version based on commit type
    .PARAMETER CurrentVersion
    Current version as a PSCustomObject with Major, Minor, Patch
    .PARAMETER CommitType
    Type of commit: 'fix' (patch), 'feat' (minor), 'breaking' (major)
    .RETURNS
    Next version as a PSCustomObject
    #>
    param(
        [PSCustomObject]$CurrentVersion,
        [ValidateSet('fix', 'feat', 'breaking')]
        [string]$CommitType
    )

    $next = $CurrentVersion.PSObject.Copy()

    switch ($CommitType) {
        'fix' {
            $next.Patch += 1
        }
        'feat' {
            $next.Minor += 1
            $next.Patch = 0
        }
        'breaking' {
            $next.Major += 1
            $next.Minor = 0
            $next.Patch = 0
        }
    }

    return $next
}

function Format-Version {
    <#
    .SYNOPSIS
    Formats a version object as a string
    .PARAMETER Version
    Version object with Major, Minor, Patch properties
    .RETURNS
    Formatted version string (e.g., "1.2.3")
    #>
    param([PSCustomObject]$Version)

    return "$($Version.Major).$($Version.Minor).$($Version.Patch)"
}

function Parse-ConventionalCommits {
    <#
    .SYNOPSIS
    Analyzes commit messages to determine version bump type
    Follows conventional commits specification
    .PARAMETER CommitMessages
    Array of commit message strings
    .RETURNS
    Commit type: 'breaking', 'feat', or 'fix'
    #>
    param([string[]]$CommitMessages)

    $hasBreaking = $false
    $hasFeat = $false
    $hasFix = $false

    foreach ($msg in $CommitMessages) {
        # Check for breaking changes (highest priority)
        if ($msg -match 'BREAKING\s+CHANGE' -or $msg -match '^feat.*!\s*:') {
            $hasBreaking = $true
        }
        # Check for features
        elseif ($msg -match '^feat(\(.+\))?:') {
            $hasFeat = $true
        }
        # Check for fixes
        elseif ($msg -match '^fix(\(.+\))?:') {
            $hasFix = $true
        }
    }

    # Priority: breaking > feat > fix
    if ($hasBreaking) { return 'breaking' }
    if ($hasFeat) { return 'feat' }
    if ($hasFix) { return 'fix' }

    return 'fix' # Default to patch bump
}

function Generate-ChangelogEntry {
    <#
    .SYNOPSIS
    Generates a changelog entry from commit messages
    .PARAMETER CommitMessages
    Array of commit message strings
    .PARAMETER Version
    The new version number
    .RETURNS
    Formatted changelog entry string
    #>
    param(
        [string[]]$CommitMessages,
        [string]$Version
    )

    $entry = "## [$Version] - $(Get-Date -Format 'yyyy-MM-dd')`n`n"

    $features = @()
    $fixes = @()

    foreach ($msg in $CommitMessages) {
        $msg = $msg.Trim()
        if ($msg -match '^feat(\(.+\))?:\s*(.+)$') {
            $features += "- feat: $($matches[2])"
        }
        elseif ($msg -match '^fix(\(.+\))?:\s*(.+)$') {
            $fixes += "- fix: $($matches[2])"
        }
    }

    if ($features.Count -gt 0) {
        $entry += "### Features`n"
        $entry += ($features -join "`n") + "`n`n"
    }

    if ($fixes.Count -gt 0) {
        $entry += "### Bug Fixes`n"
        $entry += ($fixes -join "`n") + "`n`n"
    }

    return $entry.Trim()
}

function Update-PackageJsonVersion {
    <#
    .SYNOPSIS
    Updates the version field in a package.json file
    .PARAMETER FilePath
    Path to package.json
    .PARAMETER NewVersion
    New version string
    #>
    param(
        [string]$FilePath,
        [string]$NewVersion
    )

    if (-not (Test-Path $FilePath)) {
        throw "File not found: $FilePath"
    }

    $content = Get-Content $FilePath -Raw
    $json = $content | ConvertFrom-Json
    $json.version = $NewVersion

    $json | ConvertTo-Json -Depth 10 | Set-Content -Path $FilePath
}

function Get-GitCommitsSince {
    <#
    .SYNOPSIS
    Retrieves git commit messages since a specific commit
    .PARAMETER Since
    Git reference (commit SHA, tag, branch, etc.)
    .RETURNS
    Array of commit message strings
    #>
    param(
        [string]$Since = "HEAD~10"
    )

    try {
        $commits = git log "$Since..HEAD" --format='%B' --no-merges 2>$null

        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Failed to retrieve commits from git"
            return @()
        }

        if ($null -eq $commits) {
            return @()
        }

        # Split by double newline to separate commits
        if ($commits -is [string]) {
            return @($commits)
        }

        return @($commits)
    }
    catch {
        Write-Warning "Error getting git commits: $_"
        return @()
    }
}

function Invoke-SemanticVersionBump {
    <#
    .SYNOPSIS
    Main orchestration function: bumps version and optionally generates changelog
    .PARAMETER PackageJsonPath
    Path to package.json file
    .PARAMETER CommitMessages
    Array of commit messages to analyze
    .PARAMETER GenerateChangelog
    Whether to generate/update CHANGELOG.md
    .PARAMETER ChangelogPath
    Path to CHANGELOG.md (default: same directory as package.json)
    .RETURNS
    PSCustomObject with bumped version information
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageJsonPath,

        [string[]]$CommitMessages = @(),

        [switch]$GenerateChangelog,

        [string]$ChangelogPath = ""
    )

    if (-not (Test-Path $PackageJsonPath)) {
        throw "Package.json not found: $PackageJsonPath"
    }

    # Read current version
    $packageJson = Get-Content $PackageJsonPath -Raw | ConvertFrom-Json
    $currentVersionString = $packageJson.version
    $currentVersion = Parse-SemanticVersion $currentVersionString

    # Determine commit type
    if ($CommitMessages.Count -eq 0) {
        Write-Verbose "No commits provided, defaulting to patch bump"
        $commitType = "fix"
    }
    else {
        $commitType = Parse-ConventionalCommits -CommitMessages $CommitMessages
    }

    # Calculate next version
    $nextVersion = Get-NextVersion -CurrentVersion $currentVersion -CommitType $commitType
    $nextVersionString = Format-Version $nextVersion

    # Update package.json
    Update-PackageJsonVersion -FilePath $PackageJsonPath -NewVersion $nextVersionString

    # Generate changelog if requested
    if ($GenerateChangelog) {
        if ([string]::IsNullOrEmpty($ChangelogPath)) {
            $ChangelogPath = Join-Path (Split-Path $PackageJsonPath) "CHANGELOG.md"
        }

        $changelogEntry = Generate-ChangelogEntry -CommitMessages $CommitMessages -Version $nextVersionString

        if (Test-Path $ChangelogPath) {
            $existing = Get-Content $ChangelogPath -Raw
            $updated = $changelogEntry + "`n`n" + $existing
        }
        else {
            $updated = $changelogEntry
        }

        Set-Content -Path $ChangelogPath -Value $updated
    }

    return [PSCustomObject]@{
        OldVersion     = $currentVersionString
        NewVersion     = $nextVersionString
        CommitType     = $commitType
        BumpType       = @{ fix = "patch"; feat = "minor"; breaking = "major" }[$commitType]
        ChangelogPath  = if ($GenerateChangelog) { $ChangelogPath } else { $null }
    }
}
