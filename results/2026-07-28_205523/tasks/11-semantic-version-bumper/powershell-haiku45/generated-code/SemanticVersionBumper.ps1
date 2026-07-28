# SemanticVersionBumper - Parse, bump, and changelog semantic versions
# TDD implementation: minimum viable functions to pass tests

function Parse-SemanticVersion {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Version
    )

    if ($Version -notmatch '^\d+\.\d+\.\d+$') {
        throw "Invalid semantic version format: $Version"
    }

    $parts = $Version -split '\.'
    return @{
        Major = [int]$parts[0]
        Minor = [int]$parts[1]
        Patch = [int]$parts[2]
    }
}

function Read-VersionFromFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        throw "Version file not found: $Path"
    }

    return (Get-Content -Path $Path -Raw).Trim()
}

function Read-VersionFromPackageJson {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        throw "package.json not found: $Path"
    }

    $json = Get-Content -Path $Path -Raw | ConvertFrom-Json
    return $json.version
}

function Get-CommitType {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    # Check for breaking change first
    if ($Message -match '!\s*:' -or $Message -match 'BREAKING CHANGE') {
        return "breaking"
    }

    # Check for feat/fix
    if ($Message -match '^feat(\(.*?\))?:') {
        return "feat"
    }
    elseif ($Message -match '^fix(\(.*?\))?:') {
        return "fix"
    }

    return "other"
}

function Bump-Version {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Current,

        [Parameter(Mandatory = $true)]
        [ValidateSet("major", "minor", "patch")]
        [string]$BumpType
    )

    $major = $Current.Major
    $minor = $Current.Minor
    $patch = $Current.Patch

    switch ($BumpType) {
        "major" {
            $major++
            $minor = 0
            $patch = 0
        }
        "minor" {
            $minor++
            $patch = 0
        }
        "patch" {
            $patch++
        }
    }

    return @{
        Major = $major
        Minor = $minor
        Patch = $patch
    }
}

function Determine-BumpType {
    param(
        [Parameter(Mandatory = $true)]
        [array]$Commits
    )

    $hasBreaking = $false
    $hasFeature = $false
    $hasFix = $false

    foreach ($commit in $Commits) {
        $type = Get-CommitType -Message $commit

        switch ($type) {
            "breaking" { $hasBreaking = $true }
            "feat" { $hasFeature = $true }
            "fix" { $hasFix = $true }
        }
    }

    if ($hasBreaking) {
        return "major"
    }
    elseif ($hasFeature) {
        return "minor"
    }
    elseif ($hasFix) {
        return "patch"
    }
    else {
        return "patch"
    }
}

function Get-ConventionalCommits {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Since
    )

    $commits = @()

    # Get commit messages since the specified point
    # If Since ends with ..HEAD, don't add ..HEAD again
    if ($Since -like "*..HEAD") {
        $logOutput = & git log $Since --format='%B%n---SEP---' 2>$null
    } else {
        $logOutput = & git log "$Since..HEAD" --format='%B%n---SEP---' 2>$null
    }

    if ($LASTEXITCODE -ne 0) {
        return $commits
    }

    $messages = $logOutput -split '---SEP---' | Where-Object { $_.Trim() }

    foreach ($message in $messages) {
        $trimmed = $message.Trim()
        if ($trimmed) {
            $commits += $trimmed
        }
    }

    return $commits
}

function Generate-Changelog {
    param(
        [Parameter(Mandatory = $true)]
        [array]$Commits,

        [Parameter(Mandatory = $true)]
        [string]$Version
    )

    $changelog = "## [$Version] - $(Get-Date -Format 'yyyy-MM-dd')`n`n"

    $features = @()
    $fixes = @()
    $others = @()

    foreach ($commit in $Commits) {
        $message = $commit.Message
        $hash = $commit.Hash
        $shortHashLength = [Math]::Min(7, $hash.Length)
        $shortHash = $hash.Substring(0, $shortHashLength)

        $type = Get-CommitType -Message $message

        $entry = "- $message ($shortHash)"

        switch ($type) {
            "feat" { $features += $entry }
            "fix" { $fixes += $entry }
            default { $others += $entry }
        }
    }

    if ($features.Count -gt 0) {
        $changelog += "### Features`n`n"
        $changelog += ($features -join "`n") + "`n`n"
    }

    if ($fixes.Count -gt 0) {
        $changelog += "### Fixes`n`n"
        $changelog += ($fixes -join "`n") + "`n`n"
    }

    if ($others.Count -gt 0) {
        $changelog += "### Other`n`n"
        $changelog += ($others -join "`n") + "`n`n"
    }

    return $changelog
}

function Update-VersionFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$NewVersion
    )

    if (-not (Test-Path $Path)) {
        throw "Version file not found: $Path"
    }

    if ($Path -like "*.json") {
        $json = Get-Content -Path $Path -Raw | ConvertFrom-Json
        $json.version = $NewVersion
        $json | ConvertTo-Json | Set-Content -Path $Path
    }
    else {
        Set-Content -Path $Path -Value $NewVersion -NoNewline
    }
}

function Invoke-SemanticVersionBump {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VersionFile,

        [string]$ChangelogFile = "CHANGELOG.md"
    )

    # Read current version
    if ($VersionFile -like "*.json") {
        $currentVersionStr = Read-VersionFromPackageJson -Path $VersionFile
    }
    else {
        $currentVersionStr = Read-VersionFromFile -Path $VersionFile
    }

    $currentVersion = Parse-SemanticVersion -Version $currentVersionStr

    # Get conventional commits since last version tag
    $lastTag = & git describe --tags --abbrev=0 2>/dev/null
    if ($LASTEXITCODE -ne 0) {
        # No tags found, get all commits
        $logOutput = & git log --format='%B%n---SEP---' 2>/dev/null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "No conventional commits found. No version bump."
            return $currentVersionStr
        }
    }
    else {
        # Get commits since last tag
        $logOutput = & git log "$lastTag..HEAD" --format='%B%n---SEP---' 2>/dev/null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "No conventional commits found. No version bump."
            return $currentVersionStr
        }
    }

    # Parse commits from log output
    $commits = @()
    $messages = $logOutput -split '---SEP---' | Where-Object { $_.Trim() }
    foreach ($message in $messages) {
        $trimmed = $message.Trim()
        if ($trimmed) {
            $commits += $trimmed
        }
    }

    if ($commits.Count -eq 0) {
        Write-Host "No conventional commits found. No version bump."
        return $currentVersionStr
    }

    # Determine bump type
    $bumpType = Determine-BumpType -Commits $commits

    # Bump version
    $newVersion = Bump-Version -Current $currentVersion -BumpType $bumpType
    $newVersionStr = "$($newVersion.Major).$($newVersion.Minor).$($newVersion.Patch)"

    # Update version file
    Update-VersionFile -Path $VersionFile -NewVersion $newVersionStr

    # Generate changelog
    $commitObjects = @()
    foreach ($msg in $commits) {
        $firstLine = $msg.Split("`n")[0]
        $hash = & git log -n 1 --format='%H' --all-match --grep="$firstLine" 2>/dev/null
        if ($hash) {
            $commitObjects += @{ Message = $firstLine; Hash = $hash }
        } else {
            # Fallback: just use a placeholder hash if we can't find the commit
            $commitObjects += @{ Message = $firstLine; Hash = "unknown" }
        }
    }

    if ($commitObjects.Count -gt 0) {
        $changelogEntry = Generate-Changelog -Commits $commitObjects -Version $newVersionStr

        # Append to changelog if file exists
        if (Test-Path $ChangelogFile) {
            $existing = Get-Content -Path $ChangelogFile -Raw
            Set-Content -Path $ChangelogFile -Value "$changelogEntry`n$existing"
        }
        else {
            Set-Content -Path $ChangelogFile -Value $changelogEntry
        }
    }

    Write-Host "Version bumped from $currentVersionStr to $newVersionStr"
    Write-Host "Changelog updated in $ChangelogFile"

    return $newVersionStr
}

