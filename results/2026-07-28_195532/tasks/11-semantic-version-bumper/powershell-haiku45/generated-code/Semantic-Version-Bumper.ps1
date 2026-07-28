# Semantic Version Bumper - PowerShell Implementation
# Parses semantic versions, determines bumps from conventional commits, and generates changelog entries

# Parse semantic version from package.json or version.txt files
function Parse-SemanticVersion {
    param([string]$FilePath)
    if (-not (Test-Path -LiteralPath $FilePath)) { throw "Version file not found: $FilePath" }
    $content = Get-Content -LiteralPath $FilePath -Raw
    $ext = [System.IO.Path]::GetExtension($FilePath).ToLower()
    if ($ext -eq ".json") { return ($content | ConvertFrom-Json).version }
    else { return $content.Trim() }
}

# Get version bump type from commits (major, minor, patch, or none)
function Get-VersionBumpType {
    param([string]$CommitLogPath)
    if (-not (Test-Path -LiteralPath $CommitLogPath)) { throw "Commit log file not found" }
    $commits = @(Get-Content -LiteralPath $CommitLogPath -Encoding UTF8 | Where-Object { $_.Trim() })
    $bump = "none"
    foreach ($commit in $commits) {
        $lower = $commit.ToLower()
        if ($lower -match "^breaking change" -or $lower -match "breaking change:") { $bump = "major" }
        elseif ($lower -match "^feat:" -and $bump -ne "major") { $bump = "minor" }
        elseif ($lower -match "^fix:" -and $bump -eq "none") { $bump = "patch" }
    }
    return $bump
}

# Get next semantic version based on bump type
function Get-NextSemanticVersion {
    param(
        [string]$CurrentVersion,
        [ValidateSet("major", "minor", "patch", "none")][string]$BumpType
    )
    if ($BumpType -eq "none") { return $CurrentVersion }
    $parts = $CurrentVersion -split "\."
    [int]$maj = $parts[0]; [int]$min = $parts[1]; [int]$pat = $parts[2]
    switch ($BumpType) {
        "major" { $maj++; $min = 0; $pat = 0 }
        "minor" { $min++; $pat = 0 }
        "patch" { $pat++ }
    }
    return "$maj.$min.$pat"
}

# Update version in file
function Update-VersionInFile {
    param([string]$FilePath, [string]$NewVersion)
    if (-not (Test-Path -LiteralPath $FilePath)) { throw "File not found" }
    $backup = "$FilePath.bak"
    Copy-Item -LiteralPath $FilePath -Destination $backup -Force
    try {
        $ext = [System.IO.Path]::GetExtension($FilePath).ToLower()
        if ($ext -eq ".json") {
            $json = Get-Content -LiteralPath $FilePath | ConvertFrom-Json
            $json.version = $NewVersion
            $json | ConvertTo-Json | Set-Content -LiteralPath $FilePath -Encoding UTF8
        } else {
            Set-Content -LiteralPath $FilePath -Value $NewVersion -Encoding UTF8 -NoNewline
        }
    } catch {
        Remove-Item -LiteralPath $backup -Force
        throw $_
    }
}

# Generate changelog from commits
function Generate-ChangelogEntry {
    param([string]$CommitLogPath, [string]$NewVersion, [datetime]$Date)
    if (-not (Test-Path -LiteralPath $CommitLogPath)) { throw "File not found" }
    $commits = @(Get-Content -LiteralPath $CommitLogPath -Encoding UTF8 | Where-Object { $_.Trim() })
    $changelog = @("## [$NewVersion] - $($Date.ToString('yyyy-MM-dd'))", "")
    $feats = @(); $fixes = @()
    foreach ($commit in $commits) {
        $lower = $commit.ToLower()
        if ($lower -match "^feat:") { $feats += ("- " + ($commit -replace "^feat:\s*", "")) }
        elseif ($lower -match "^fix:") { $fixes += ("- " + ($commit -replace "^fix:\s*", "")) }
    }
    if ($feats.Count -gt 0) { $changelog += "### Features"; $changelog += $feats; $changelog += "" }
    if ($fixes.Count -gt 0) { $changelog += "### Fixes"; $changelog += $fixes }
    return $changelog -join "`n"
}

# Main orchestration function
function Invoke-SemanticVersionBump {
    param([string]$VersionFilePath, [string]$CommitLogPath)
    $oldVersion = Parse-SemanticVersion -FilePath $VersionFilePath
    $bumpType = Get-VersionBumpType -CommitLogPath $CommitLogPath
    $newVersion = Get-NextSemanticVersion -CurrentVersion $oldVersion -BumpType $bumpType
    Update-VersionInFile -FilePath $VersionFilePath -NewVersion $newVersion
    $changelog = Generate-ChangelogEntry -CommitLogPath $CommitLogPath -NewVersion $newVersion -Date (Get-Date)
    return @{ OldVersion = $oldVersion; NewVersion = $newVersion; BumpType = $bumpType; Changelog = $changelog }
}
