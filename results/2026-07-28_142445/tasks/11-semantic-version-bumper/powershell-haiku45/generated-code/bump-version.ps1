<#
.SYNOPSIS
Main entry point for semantic version bumper CLI
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$PackageJsonPath,

    [Parameter(Mandatory = $false)]
    [string]$CommitBase = "HEAD~10",

    [switch]$GenerateChangelog,

    [string]$Output = ""
)

# Import the module functions
. $PSScriptRoot/version-bumper.ps1

try {
    # Get commits from git
    $commits = Get-GitCommitsSince -Since $CommitBase

    if ($commits.Count -eq 0) {
        Write-Warning "No commits found since $CommitBase"
        $commits = @()
    }

    # Bump version and optionally generate changelog
    $result = Invoke-SemanticVersionBump `
        -PackageJsonPath $PackageJsonPath `
        -CommitMessages $commits `
        -GenerateChangelog:$GenerateChangelog

    # Output results
    Write-Host "✓ Version bumped: $($result.OldVersion) → $($result.NewVersion)"
    Write-Host "  Bump type: $($result.BumpType) ($($result.CommitType))"

    if ($GenerateChangelog) {
        Write-Host "✓ Changelog updated: $($result.ChangelogPath)"
    }

    if (-not [string]::IsNullOrEmpty($Output)) {
        $result | ConvertTo-Json | Set-Content -Path $Output
        Write-Host "✓ Result exported to: $Output"
    }

    # Exit with success
    exit 0
}
catch {
    Write-Error "Error: $_"
    exit 1
}
