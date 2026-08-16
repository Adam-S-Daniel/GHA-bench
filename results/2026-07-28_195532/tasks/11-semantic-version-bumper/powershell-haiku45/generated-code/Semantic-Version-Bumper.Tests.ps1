# Semantic Version Bumper - Pester Tests
# Tests using TDD: failing test first, implement to pass

BeforeAll {
    # Parse semantic version from package.json or version.txt files
    function Parse-SemanticVersion {
    param([string]$FilePath)
    if (-not (Test-Path -LiteralPath $FilePath)) { throw "Version file not found: $FilePath" }
    $content = Get-Content -LiteralPath $FilePath -Raw
    $ext = [System.IO.Path]::GetExtension($FilePath).ToLower()
    if ($ext -eq ".json") { return ($content | ConvertFrom-Json).version }
    else { return $content.Trim() }
}

# Get version bump type from commits
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

# Get next semantic version
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

# Generate changelog
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

# Main function
function Invoke-SemanticVersionBump {
    param([string]$VersionFilePath, [string]$CommitLogPath)
    $oldVersion = Parse-SemanticVersion -FilePath $VersionFilePath
    $bumpType = Get-VersionBumpType -CommitLogPath $CommitLogPath
    $newVersion = Get-NextSemanticVersion -CurrentVersion $oldVersion -BumpType $bumpType
    Update-VersionInFile -FilePath $VersionFilePath -NewVersion $newVersion
    $changelog = Generate-ChangelogEntry -CommitLogPath $CommitLogPath -NewVersion $newVersion -Date (Get-Date)
    return @{ OldVersion = $oldVersion; NewVersion = $newVersion; BumpType = $bumpType; Changelog = $changelog }
}

# Get test directory
$testDir = Join-Path $PSScriptRoot "test-fixtures"
if (Test-Path $testDir) { Remove-Item $testDir -Recurse -Force }
$null = New-Item -ItemType Directory -Path $testDir

# Helper
    function New-Fixture {
        param([string]$Name, [string]$Content = "")
        $path = Join-Path $testDir $Name
        Set-Content -Path $path -Value $Content -Encoding UTF8
        return $path
    }
}

# Tests
Describe "Parse-SemanticVersion" {
    It "should parse version from package.json" {
        $pkg = @{ version = "1.0.0"; name = "app" } | ConvertTo-Json
        $f = New-Fixture "pkg1.json" $pkg
        Parse-SemanticVersion -FilePath $f | Should -Be "1.0.0"
    }

    It "should parse version from version.txt" {
        $f = New-Fixture "ver1.txt" "2.3.4"
        Parse-SemanticVersion -FilePath $f | Should -Be "2.3.4"
    }

    It "should throw on missing file" {
        { Parse-SemanticVersion -FilePath "/nonexistent/version.json" } | Should -Throw
    }
}

Describe "Get-VersionBumpType" {
    It "should detect patch for fix commit" {
        $f = New-Fixture "commits1.txt" "fix: bug"
        Get-VersionBumpType -CommitLogPath $f | Should -Be "patch"
    }

    It "should detect minor for feat commit" {
        $f = New-Fixture "commits2.txt" "feat: feature"
        Get-VersionBumpType -CommitLogPath $f | Should -Be "minor"
    }

    It "should detect major for breaking change" {
        $f = New-Fixture "commits3.txt" ("feat: change`nBREAKING CHANGE: removed")
        Get-VersionBumpType -CommitLogPath $f | Should -Be "major"
    }

    It "should prefer major over minor and patch" {
        $f = New-Fixture "commits4.txt" ("fix: bug`nfeat: feature`nBREAKING CHANGE: removed")
        Get-VersionBumpType -CommitLogPath $f | Should -Be "major"
    }

    It "should return none for non-conventional commits" {
        $f = New-Fixture "commits5.txt" ("random commit`nupdate readme")
        Get-VersionBumpType -CommitLogPath $f | Should -Be "none"
    }
}

Describe "Get-NextSemanticVersion" {
    It "should bump patch" {
        Get-NextSemanticVersion -CurrentVersion "1.2.3" -BumpType "patch" | Should -Be "1.2.4"
    }

    It "should bump minor and reset patch" {
        Get-NextSemanticVersion -CurrentVersion "1.2.3" -BumpType "minor" | Should -Be "1.3.0"
    }

    It "should bump major and reset minor/patch" {
        Get-NextSemanticVersion -CurrentVersion "1.2.3" -BumpType "major" | Should -Be "2.0.0"
    }

    It "should handle 0.x.x versions" {
        Get-NextSemanticVersion -CurrentVersion "0.1.2" -BumpType "minor" | Should -Be "0.2.0"
        Get-NextSemanticVersion -CurrentVersion "0.1.2" -BumpType "major" | Should -Be "1.0.0"
    }

    It "should not change for none" {
        Get-NextSemanticVersion -CurrentVersion "1.2.3" -BumpType "none" | Should -Be "1.2.3"
    }
}

Describe "Update-VersionInFile" {
    It "should update package.json" {
        $pkg = @{ version = "1.0.0"; name = "app" } | ConvertTo-Json
        $f = New-Fixture "pkg_upd.json" $pkg
        Update-VersionInFile -FilePath $f -NewVersion "1.1.0"
        $updated = Get-Content -Path $f | ConvertFrom-Json
        $updated.version | Should -Be "1.1.0"
    }

    It "should update version.txt" {
        $f = New-Fixture "ver_upd.txt" "1.0.0"
        Update-VersionInFile -FilePath $f -NewVersion "1.1.0"
        (Get-Content -Path $f) | Should -Be "1.1.0"
    }

    It "should create backup" {
        $f = New-Fixture "ver_bak.txt" "1.0.0"
        Update-VersionInFile -FilePath $f -NewVersion "1.1.0"
        Test-Path "$f.bak" | Should -Be $true
        (Get-Content -Path "$f.bak") | Should -Be "1.0.0"
    }
}

Describe "Generate-ChangelogEntry" {
    It "should generate changelog with version" {
        $f = New-Fixture "commits_chg.txt" ("feat: add feature`nfix: resolve bug")
        $changelog = Generate-ChangelogEntry -CommitLogPath $f -NewVersion "1.1.0" -Date (Get-Date)
        $changelog | Should -Match "1.1.0"
        $changelog | Should -Match "add feature"
        $changelog | Should -Match "resolve bug"
    }

    It "should categorize by type" {
        $f = New-Fixture "commits_cat.txt" ("feat: feature 1`nfeat: feature 2`nfix: bug 1")
        $changelog = Generate-ChangelogEntry -CommitLogPath $f -NewVersion "1.1.0" -Date (Get-Date)
        $changelog | Should -Match "### Features"
        $changelog | Should -Match "### Fixes"
    }
}

Describe "Invoke-SemanticVersionBump" {
    It "should complete full workflow" {
        $pkg = @{ version = "1.0.0"; name = "app" } | ConvertTo-Json
        $vf = New-Fixture "wf_pkg.json" $pkg
        $cf = New-Fixture "wf_commits.txt" "feat: new feature"

        $result = Invoke-SemanticVersionBump -VersionFilePath $vf -CommitLogPath $cf

        $result.OldVersion | Should -Be "1.0.0"
        $result.NewVersion | Should -Be "1.1.0"
        $result.BumpType | Should -Be "minor"

        $updated = Get-Content -Path $vf | ConvertFrom-Json
        $updated.version | Should -Be "1.1.0"
    }
}
