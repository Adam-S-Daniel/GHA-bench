# Main entry point for semantic version bumper
# Usage: ./bump-version.ps1 -VersionFile <path> [-ChangelogFile <path>] [-OutputVersion]

param(
    [Parameter(Mandatory = $true)]
    [string]$VersionFile,

    [string]$ChangelogFile = "CHANGELOG.md",

    [switch]$OutputVersion
)

# Import the module functions
. "$PSScriptRoot/SemanticVersionBumper.ps1"

# Run the version bump
try {
    $newVersion = Invoke-SemanticVersionBump -VersionFile $VersionFile -ChangelogFile $ChangelogFile

    if ($OutputVersion) {
        Write-Output $newVersion
    }

    exit 0
}
catch {
    Write-Error "Error: $_"
    exit 1
}
