#requires -Version 7.0
<#
    LicenseChecker.psm1

    Core library for the dependency-license compliance checker.

    The module is split into small, independently testable functions:

        Get-DependencyList    - parse a manifest into name/version records
        Get-DependencyLicense - look up a dependency's license (mockable)
        Test-LicenseStatus    - classify a license as Approved/Denied/Unknown
        New-ComplianceReport  - orchestrate the above into a report object
        Format-ComplianceReport - render the report as human/CI friendly text

    Everything is offline by design: the "license lookup" is backed by a
    caller-supplied database (a hashtable / JSON file). This keeps the code
    deterministic, mockable in Pester, and safe to run in an isolated CI
    container with no network access or secrets.
#>

Set-StrictMode -Version Latest

function Get-DependencyList {
    <#
        .SYNOPSIS
            Parse a dependency manifest into a flat list of name/version records.

        .DESCRIPTION
            Supports npm 'package.json' and pip 'requirements.txt' style
            manifests. The manifest type is detected from the file name /
            extension. Each returned object exposes 'Name' and 'Version'.

        .PARAMETER ManifestPath
            Path to the manifest file on disk.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ManifestPath
    )

    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        throw "Manifest file not found: '$ManifestPath'"
    }

    $fileName  = Split-Path -Path $ManifestPath -Leaf
    $extension = [System.IO.Path]::GetExtension($fileName).ToLowerInvariant()

    # Detect the manifest flavour from the extension so the checker also works
    # with copies placed at arbitrary paths (e.g. a CI temp file). '.json' is
    # treated as npm-style; '.txt' as pip requirements-style.
    switch ($extension) {
        '.json' {
            return ConvertFrom-PackageJson -ManifestPath $ManifestPath
        }
        '.txt' {
            return ConvertFrom-RequirementsTxt -ManifestPath $ManifestPath
        }
        default {
            throw "Unsupported manifest type: '$fileName'. Supported manifests: package.json (*.json), requirements.txt (*.txt)"
        }
    }
}

function ConvertFrom-PackageJson {
    # Internal helper: read an npm package.json and emit name/version records
    # drawn from dependencies, devDependencies, peerDependencies and
    # optionalDependencies (whichever are present).
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ManifestPath
    )

    try {
        $json = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
    }
    catch {
        throw "Failed to parse package.json '$ManifestPath': $($_.Exception.Message)"
    }

    $sections = 'dependencies', 'devDependencies', 'peerDependencies', 'optionalDependencies'
    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($section in $sections) {
        if ($json.PSObject.Properties.Name -notcontains $section) { continue }
        $node = $json.$section
        if ($null -eq $node) { continue }

        foreach ($prop in $node.PSObject.Properties) {
            $results.Add([pscustomobject]@{
                Name    = $prop.Name
                Version = [string]$prop.Value
            })
        }
    }

    return $results.ToArray()
}

function ConvertFrom-RequirementsTxt {
    # Internal helper: read a pip requirements.txt and emit name/version
    # records. Handles pinned (==), ranged (>=, <=, ~=, !=, >, <) specs,
    # "extras" qualifiers (pkg[extra]), inline '#' comments and PEP 508
    # environment markers (after ';'). Comment-only and blank lines are
    # skipped, as are '-r'/'-c'/'--option' directive lines.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ManifestPath
    )

    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($rawLine in (Get-Content -LiteralPath $ManifestPath)) {
        $line = $rawLine.Trim()

        # Skip blanks, full-line comments and pip directives (-r, -c, --hash...)
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line.StartsWith('#')) { continue }
        if ($line.StartsWith('-')) { continue }

        # Drop any PEP 508 environment marker (everything after ';')
        $line = ($line -split ';', 2)[0]
        # Drop any inline comment (everything after '#')
        $line = ($line -split '#', 2)[0].Trim()
        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        # Strip "extras" qualifiers, e.g. pkg[extra1,extra2] -> pkg
        $line = $line -replace '\[[^\]]*\]', ''

        # Split name and version-spec on the first version operator.
        if ($line -match '^(?<name>[A-Za-z0-9_.\-]+)\s*(?<op>==|>=|<=|~=|!=|>|<)?\s*(?<ver>.*)$') {
            $name = $Matches['name'].Trim()
            $version = $Matches['ver'].Trim()
            if ([string]::IsNullOrWhiteSpace($version)) { $version = '*' }

            $results.Add([pscustomobject]@{
                Name    = $name
                Version = $version
            })
        }
    }

    return $results.ToArray()
}

function Get-DependencyLicense {
    <#
        .SYNOPSIS
            Resolve the SPDX license identifier for a single dependency.

        .DESCRIPTION
            The lookup is intentionally backed by a caller-supplied database
            (a hashtable mapping package name -> license id). This is the
            seam that is "mocked" for testing: production code would populate
            the database from a package registry, while tests pass an
            in-memory database or Mock this function directly.

            Returns 'Unknown' when the package is absent or no database is
            supplied, so the caller never has to deal with $null.

        .PARAMETER Name
            The dependency / package name.

        .PARAMETER LicenseDatabase
            Optional hashtable mapping (case-insensitive) package name to
            license identifier.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [hashtable]$LicenseDatabase
    )

    if (-not $LicenseDatabase) {
        return 'Unknown'
    }

    # PowerShell hashtable key lookups are case-insensitive by default, but
    # the database may have been built from JSON with a case-sensitive
    # comparer, so match defensively/case-insensitively.
    foreach ($key in $LicenseDatabase.Keys) {
        if ($key -ieq $Name) {
            $value = $LicenseDatabase[$key]
            if ([string]::IsNullOrWhiteSpace([string]$value)) { return 'Unknown' }
            return [string]$value
        }
    }

    return 'Unknown'
}

function Test-LicenseStatus {
    <#
        .SYNOPSIS
            Classify a license as 'Approved', 'Denied' or 'Unknown'.

        .DESCRIPTION
            Resolution order (deny wins ties, for safety):
              1. empty / 'Unknown' license          -> Unknown
              2. license on the deny list           -> Denied
              3. license on the allow list          -> Approved
              4. anything else (known but unlisted)  -> Unknown

        .PARAMETER License
            The license identifier to classify.

        .PARAMETER Config
            An object exposing 'AllowList' and 'DenyList' string collections.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [AllowNull()]
        [string]$License,

        [Parameter(Mandatory)]
        $Config
    )

    if ([string]::IsNullOrWhiteSpace($License) -or $License -ieq 'Unknown') {
        return 'Unknown'
    }

    $denyList  = @($Config.DenyList)
    $allowList = @($Config.AllowList)

    if ($denyList  | Where-Object { $_ -ieq $License }) { return 'Denied' }
    if ($allowList | Where-Object { $_ -ieq $License }) { return 'Approved' }

    return 'Unknown'
}

function New-ComplianceReport {
    <#
        .SYNOPSIS
            Build a license-compliance report for an entire manifest.

        .DESCRIPTION
            Parses the manifest, resolves each dependency's license, classifies
            it against the supplied policy config, and returns a structured
            report object:

                .Manifest  - the manifest path that was analysed
                .Items     - one record per dependency (Name/Version/License/Status)
                .Summary   - Total / Approved / Denied / Unknown counts

        .PARAMETER ManifestPath
            Path to the dependency manifest.

        .PARAMETER Config
            Policy object exposing AllowList and DenyList.

        .PARAMETER LicenseDatabase
            Optional license-lookup database (see Get-DependencyLicense).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ManifestPath,

        [Parameter(Mandatory)]
        $Config,

        [hashtable]$LicenseDatabase
    )

    $dependencies = Get-DependencyList -ManifestPath $ManifestPath

    $items = foreach ($dep in $dependencies) {
        $license = Get-DependencyLicense -Name $dep.Name -LicenseDatabase $LicenseDatabase
        $status  = Test-LicenseStatus -License $license -Config $Config

        [pscustomobject]@{
            Name    = $dep.Name
            Version = $dep.Version
            License = $license
            Status  = $status
        }
    }

    # @() guards the single-item case so .Count / Where-Object behave.
    $items = @($items)

    $summary = [pscustomobject]@{
        Total    = $items.Count
        Approved = @($items | Where-Object Status -eq 'Approved').Count
        Denied   = @($items | Where-Object Status -eq 'Denied').Count
        Unknown  = @($items | Where-Object Status -eq 'Unknown').Count
    }

    return [pscustomobject]@{
        Manifest = $ManifestPath
        Items    = $items
        Summary  = $summary
    }
}

function Format-ComplianceReport {
    <#
        .SYNOPSIS
            Render a compliance report object as a list of text lines.

        .DESCRIPTION
            Produces a deliberately machine-parseable, stable text format so
            both humans and CI assertions can consume it:

                === Dependency License Compliance Report ===
                Manifest: <path>
                DEP | <name> | <version> | <license> | <status>
                ...
                SUMMARY | Total: N | Approved: A | Denied: D | Unknown: U
                RESULT: PASS|FAIL

            RESULT is FAIL when any dependency is Denied, otherwise PASS.

        .PARAMETER Report
            A report object as returned by New-ComplianceReport.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        $Report
    )

    $lines = [System.Collections.Generic.List[string]]::new()

    $lines.Add('=== Dependency License Compliance Report ===')
    $lines.Add("Manifest: $($Report.Manifest)")

    foreach ($item in $Report.Items) {
        $lines.Add("DEP | $($item.Name) | $($item.Version) | $($item.License) | $($item.Status)")
    }

    $s = $Report.Summary
    $lines.Add("SUMMARY | Total: $($s.Total) | Approved: $($s.Approved) | Denied: $($s.Denied) | Unknown: $($s.Unknown)")

    $result = if ($s.Denied -gt 0) { 'FAIL' } else { 'PASS' }
    $lines.Add("RESULT: $result")

    return $lines.ToArray()
}

Export-ModuleMember -Function Get-DependencyList, Get-DependencyLicense, Test-LicenseStatus, New-ComplianceReport, Format-ComplianceReport
