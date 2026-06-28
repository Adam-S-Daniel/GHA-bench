<#
.SYNOPSIS
    Semantic Version Bumper module.

.DESCRIPTION
    Provides functions to:
      * read a current semantic version from a plain version file or package.json,
      * classify conventional-commit messages and determine the required bump,
      * compute the next semantic version,
      * persist the new version back to the source file,
      * render a Markdown changelog entry from the commits.

    The design keeps each concern in a small, pure-ish function so it can be unit
    tested in isolation (red/green TDD), while Invoke-VersionBump orchestrates them
    for real CLI / CI use.
#>

Set-StrictMode -Version Latest

# A semantic version "core": MAJOR.MINOR.PATCH (we intentionally keep scope to the
# release-relevant core; pre-release/build metadata is out of scope for the bump).
$script:SemVerRegex = '^(\d+)\.(\d+)\.(\d+)$'

function Get-CurrentVersion {
    <#
    .SYNOPSIS
        Reads the current semantic version from a version file or package.json.
    .PARAMETER Path
        Path to a plain text version file or a package.json file. The file type is
        detected by extension (*.json => parsed as JSON and the .version field used).
    .OUTPUTS
        [string] the MAJOR.MINOR.PATCH version with any leading 'v' stripped.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Version file not found: '$Path'."
    }

    if ([System.IO.Path]::GetExtension($Path) -ieq '.json') {
        # package.json (or any JSON carrying a top-level .version field).
        try {
            $json = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
        }
        catch {
            throw "Failed to parse JSON version file '$Path': $($_.Exception.Message)"
        }
        if (-not $json.PSObject.Properties.Name.Contains('version')) {
            throw "JSON version file '$Path' has no 'version' field."
        }
        $raw = [string] $json.version
    }
    else {
        $raw = (Get-Content -LiteralPath $Path -Raw)
    }

    # Normalise: trim whitespace and an optional leading 'v'.
    $version = $raw.Trim()
    if ($version -match '^[vV]') { $version = $version.Substring(1) }
    $version = $version.Trim()

    if ($version -notmatch $script:SemVerRegex) {
        throw "Value '$version' in '$Path' is not a valid semantic version (expected MAJOR.MINOR.PATCH)."
    }

    return $version
}

function Get-CommitClassification {
    <#
    .SYNOPSIS
        Classifies a single conventional-commit message.
    .OUTPUTS
        [pscustomobject] with Type (feat/fix/other), Breaking (bool), Description.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Message)

    # Only the subject line carries the type/scope; the body may carry BREAKING CHANGE.
    $lines   = $Message -split "`r?`n"
    $subject = $lines[0].Trim()

    # Conventional commit subject: type(scope)!: description
    $breaking = $false
    $type = 'other'
    $description = $subject

    if ($subject -match '^(?<type>[a-zA-Z]+)(?:\((?<scope>[^)]*)\))?(?<bang>!)?:\s*(?<desc>.*)$') {
        $type        = $Matches['type'].ToLowerInvariant()
        $description = $Matches['desc'].Trim()
        if ($Matches['bang']) { $breaking = $true }
    }

    # A "BREAKING CHANGE:" / "BREAKING-CHANGE:" footer anywhere also marks a breaking change.
    if ($Message -match '(?m)^BREAKING[ -]CHANGE:') { $breaking = $true }

    [pscustomobject]@{
        Type        = $type
        Breaking    = $breaking
        Description = $description
    }
}

function Get-BumpType {
    <#
    .SYNOPSIS
        Determines the required version bump from a set of conventional commits.
    .DESCRIPTION
        Precedence (highest wins): breaking => major, feat => minor, fix => patch,
        anything else => none.
    .OUTPUTS
        [string] one of 'major','minor','patch','none'.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][string[]] $Commits)

    $bump = 'none'
    # Rank lets us keep the highest-precedence bump seen so far.
    $rank = @{ none = 0; patch = 1; minor = 2; major = 3 }

    foreach ($commit in $Commits) {
        if ([string]::IsNullOrWhiteSpace($commit)) { continue }
        $c = Get-CommitClassification -Message $commit

        $thisBump = 'none'
        if     ($c.Breaking)      { $thisBump = 'major' }
        elseif ($c.Type -eq 'feat') { $thisBump = 'minor' }
        elseif ($c.Type -eq 'fix')  { $thisBump = 'patch' }

        if ($rank[$thisBump] -gt $rank[$bump]) { $bump = $thisBump }
    }

    return $bump
}

function Step-Version {
    <#
    .SYNOPSIS
        Computes the next semantic version given a bump type.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Version,
        [Parameter(Mandatory)][ValidateSet('major','minor','patch','none')][string] $BumpType
    )

    if ($Version -notmatch $script:SemVerRegex) {
        throw "Cannot bump '$Version': not a valid semantic version."
    }
    $major = [int]$Matches[1]; $minor = [int]$Matches[2]; $patch = [int]$Matches[3]

    switch ($BumpType) {
        'major' { $major++; $minor = 0; $patch = 0 }
        'minor' { $minor++; $patch = 0 }
        'patch' { $patch++ }
        'none'  { } # no change
    }

    return "$major.$minor.$patch"
}

function Set-CurrentVersion {
    <#
    .SYNOPSIS
        Writes a new semantic version back to the source file.
    .DESCRIPTION
        For package.json the .version field is replaced and other fields preserved;
        for a plain file the whole content is overwritten with the version.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $Version
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Version file not found: '$Path'."
    }
    if ($Version -notmatch $script:SemVerRegex) {
        throw "Refusing to write invalid version '$Version'."
    }

    if ([System.IO.Path]::GetExtension($Path) -ieq '.json') {
        $json = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
        $json.version = $Version
        # Depth 32 keeps nested config (e.g. scripts, dependencies) intact.
        ($json | ConvertTo-Json -Depth 32) | Set-Content -LiteralPath $Path
    }
    else {
        Set-Content -LiteralPath $Path -Value $Version
    }
}

function New-ChangelogEntry {
    <#
    .SYNOPSIS
        Renders a Markdown changelog entry for a release from its commits.
    .OUTPUTS
        [string] a Markdown block grouping commits into Breaking Changes / Features /
        Bug Fixes / Other.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Version,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]] $Commits,
        [string] $Date
    )

    $breaking = New-Object System.Collections.Generic.List[string]
    $features = New-Object System.Collections.Generic.List[string]
    $fixes    = New-Object System.Collections.Generic.List[string]
    $other    = New-Object System.Collections.Generic.List[string]

    foreach ($commit in $Commits) {
        if ([string]::IsNullOrWhiteSpace($commit)) { continue }
        $c = Get-CommitClassification -Message $commit
        if ($c.Breaking) { $breaking.Add($c.Description) }
        switch ($c.Type) {
            'feat'  { $features.Add($c.Description) }
            'fix'   { $fixes.Add($c.Description) }
            default { if (-not $c.Breaking) { $other.Add($c.Description) } }
        }
    }

    $sb = New-Object System.Text.StringBuilder
    $header = if ($Date) { "## $Version - $Date" } else { "## $Version" }
    [void]$sb.AppendLine($header)
    [void]$sb.AppendLine()

    function Add-Section {
        param($Title, $Items, $Builder)
        if ($Items.Count -gt 0) {
            [void]$Builder.AppendLine("### $Title")
            foreach ($i in $Items) { [void]$Builder.AppendLine("- $i") }
            [void]$Builder.AppendLine()
        }
    }

    Add-Section -Title 'Breaking Changes' -Items $breaking -Builder $sb
    Add-Section -Title 'Features'         -Items $features -Builder $sb
    Add-Section -Title 'Bug Fixes'        -Items $fixes    -Builder $sb
    Add-Section -Title 'Other'            -Items $other    -Builder $sb

    return $sb.ToString().TrimEnd() + "`n"
}

Export-ModuleMember -Function Get-CurrentVersion, Get-CommitClassification, Get-BumpType,
    Step-Version, Set-CurrentVersion, New-ChangelogEntry
