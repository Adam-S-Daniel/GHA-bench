<#
.SYNOPSIS
    Dependency License Checker — core library.

.DESCRIPTION
    Parses a dependency manifest (package.json or requirements.txt), looks up each
    dependency's license, classifies it against an allow/deny policy, and assembles
    a compliance report.

    The license lookup is isolated behind Resolve-DependencyLicense so it can be
    mocked in tests (Pester) and swapped for a real registry call in production. In
    this implementation the "lookup" reads from a local license database file, which
    doubles as the deterministic, offline data source used by the CI workflow.

    Design notes:
      * Pure functions only — no function writes to the console or to files. The CLI
        entry-point (Invoke-DependencyLicenseCheck.ps1) owns all I/O so these
        functions stay testable and side-effect free.
      * Verbs are PSScriptAnalyzer-approved and nouns are singular.
#>

Set-StrictMode -Version Latest

function Get-LicenseStatus {
    <#
    .SYNOPSIS
        Classifies a license string against an allow/deny policy.
    .DESCRIPTION
        Returns 'approved', 'denied', or 'unknown'. The deny-list takes precedence
        over the allow-list so an explicitly forbidden license can never be approved
        by accident. A null/empty/unrecognised license is 'unknown'. Matching is
        case-insensitive (PowerShell's -contains is case-insensitive for strings).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$License,

        [Parameter(Mandatory)]
        $Policy
    )

    if ([string]::IsNullOrWhiteSpace($License)) { return 'unknown' }

    if ($Policy.Deny -contains $License) { return 'denied' }
    if ($Policy.Allow -contains $License) { return 'approved' }

    return 'unknown'
}

function Get-DependencyList {
    <#
    .SYNOPSIS
        Parses a dependency manifest into normalised dependency records.
    .DESCRIPTION
        Supports package.json (npm) and requirements.txt (pip). Returns an ordered
        array of objects with Name, Version, and Type. Version range operators
        (^, ~, >=, ==, ~=, ...) and pip extras ([security]) are stripped so the
        Version field is a clean version string (or '' when unpinned).
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [string]$ManifestPath
    )

    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        throw "Manifest file not found: '$ManifestPath'"
    }

    $fileName = Split-Path -Leaf $ManifestPath
    $raw = Get-Content -LiteralPath $ManifestPath -Raw

    # Decide the manifest type from the file name.
    if ($fileName -ieq 'package.json') {
        return Get-NpmDependency -Raw $raw -ManifestPath $ManifestPath
    }
    elseif ($fileName -ieq 'requirements.txt') {
        return Get-PipDependency -Raw $raw
    }
    else {
        throw "Unsupported manifest type: '$fileName'. Supported: package.json, requirements.txt."
    }
}

function Get-NpmDependency {
    # Internal helper: parse package.json dependencies + devDependencies in order.
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][string]$Raw,
        [Parameter(Mandatory)][string]$ManifestPath
    )

    try {
        $json = $Raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Failed to parse package.json '$ManifestPath': $($_.Exception.Message)"
    }

    $result = [System.Collections.Generic.List[object]]::new()

    foreach ($section in 'dependencies', 'devDependencies') {
        if ($json.PSObject.Properties.Name -notcontains $section) { continue }
        $node = $json.$section
        if ($null -eq $node) { continue }
        # ConvertFrom-Json preserves JSON key insertion order, giving deterministic output.
        foreach ($prop in $node.PSObject.Properties) {
            $result.Add([pscustomobject]@{
                Name    = $prop.Name
                Version = Get-CleanVersion -RawVersion ([string]$prop.Value)
                Type    = 'npm'
            })
        }
    }

    return , $result.ToArray()
}

function Get-PipDependency {
    # Internal helper: parse requirements.txt one dependency per non-comment line.
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][string]$Raw
    )

    $result = [System.Collections.Generic.List[object]]::new()

    foreach ($line in ($Raw -split "\r?\n")) {
        $trimmed = $line.Trim()
        if ($trimmed -eq '' -or $trimmed.StartsWith('#')) { continue }

        # Drop inline comments and pip environment markers (e.g. "; python_version<'3.8'").
        $trimmed = ($trimmed -split '\s+#')[0].Trim()
        $trimmed = ($trimmed -split ';')[0].Trim()
        if ($trimmed -eq '') { continue }

        # Split name from version on the first specifier operator.
        if ($trimmed -match '^(?<name>[^=<>!~ ]+)\s*(?<op>===|==|>=|<=|~=|!=|>|<)\s*(?<ver>.+)$') {
            $name = $Matches['name']
            $ver  = $Matches['ver'].Trim()
        }
        else {
            $name = $trimmed
            $ver  = ''
        }

        # Strip pip extras such as package[security].
        $name = ($name -replace '\[.*\]', '').Trim()

        $result.Add([pscustomobject]@{
            Name    = $name
            Version = $ver
            Type    = 'pip'
        })
    }

    return , $result.ToArray()
}

function Get-CleanVersion {
    # Internal helper: strip leading semver range operators (^, ~, >=, <=, =, v, space).
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$RawVersion)

    return ($RawVersion -replace '^[\^~>=<v\s]+', '').Trim()
}

function Read-LicensePolicy {
    <#
    .SYNOPSIS
        Reads the license allow/deny policy from a JSON config file.
    .DESCRIPTION
        Expects { "allow": [...], "deny": [...] }. Missing keys default to empty
        arrays. Returns an object with .Allow and .Deny string arrays.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PolicyPath
    )

    if (-not (Test-Path -LiteralPath $PolicyPath -PathType Leaf)) {
        throw "Policy file not found: '$PolicyPath'"
    }

    try {
        $json = Get-Content -LiteralPath $PolicyPath -Raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Failed to parse policy file '$PolicyPath': $($_.Exception.Message)"
    }

    $allow = @()
    $deny = @()
    if ($json.PSObject.Properties.Name -contains 'allow' -and $null -ne $json.allow) { $allow = @($json.allow) }
    if ($json.PSObject.Properties.Name -contains 'deny'  -and $null -ne $json.deny)  { $deny  = @($json.deny) }

    return [pscustomobject]@{
        Allow = $allow
        Deny  = $deny
    }
}

function Read-LicenseDatabase {
    <#
    .SYNOPSIS
        Loads the mock license database (name -> license) into a lookup hashtable.
    .DESCRIPTION
        This stands in for an external license service / SBOM scanner. Keeping it as
        a local JSON file makes the pipeline deterministic and offline-friendly.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "License database file not found: '$Path'"
    }

    try {
        $json = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Failed to parse license database '$Path': $($_.Exception.Message)"
    }

    $db = @{}
    foreach ($prop in $json.PSObject.Properties) {
        $db[$prop.Name] = [string]$prop.Value
    }
    return $db
}

function Resolve-DependencyLicense {
    <#
    .SYNOPSIS
        Looks up the license for a single dependency (the mockable seam).
    .DESCRIPTION
        In production this would query a package registry or SBOM service. Here it
        reads from the in-memory license database hashtable. Tests replace this with
        a Pester Mock so report logic can be exercised without any real lookup.
        Returns the license string, or $null when the package is unknown.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Version,
        [Parameter(Mandatory)][hashtable]$Database
    )

    # Prefer an exact name@version match, then fall back to a name-only match.
    $versioned = "$Name@$Version"
    if ($Database.ContainsKey($versioned)) { return $Database[$versioned] }
    if ($Database.ContainsKey($Name))      { return $Database[$Name] }
    return $null
}

function Get-ComplianceReport {
    <#
    .SYNOPSIS
        Builds the per-dependency compliance report.
    .DESCRIPTION
        For each dependency, resolves the license (via the mockable seam) and
        classifies it. Returns ordered objects: Name, Version, License, Status.
        Pure: no console/file output.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Dependencies,
        [Parameter(Mandatory)]$Policy,
        [Parameter(Mandatory)][hashtable]$Database
    )

    $report = [System.Collections.Generic.List[object]]::new()

    foreach ($dep in $Dependencies) {
        $license = Resolve-DependencyLicense -Name $dep.Name -Version $dep.Version -Database $Database
        $status = Get-LicenseStatus -License $license -Policy $Policy
        $display = if ([string]::IsNullOrWhiteSpace($license)) { 'UNKNOWN' } else { $license }

        $report.Add([pscustomobject]@{
            Name    = $dep.Name
            Version = $dep.Version
            License = $display
            Status  = $status
        })
    }

    return , $report.ToArray()
}

function Get-ComplianceSummary {
    <#
    .SYNOPSIS
        Aggregates a compliance report into status counts + an overall verdict.
    .DESCRIPTION
        Compliant only when there are zero denied AND zero unknown dependencies —
        you cannot vouch for a license you could not verify.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Report
    )

    $approved = @($Report | Where-Object { $_.Status -eq 'approved' }).Count
    $denied   = @($Report | Where-Object { $_.Status -eq 'denied' }).Count
    $unknown  = @($Report | Where-Object { $_.Status -eq 'unknown' }).Count

    return [pscustomobject]@{
        Approved  = [int]$approved
        Denied    = [int]$denied
        Unknown   = [int]$unknown
        Total     = [int]$Report.Count
        Compliant = ($denied -eq 0 -and $unknown -eq 0)
    }
}

function Format-ComplianceReport {
    <#
    .SYNOPSIS
        Renders a compliance report + summary as text, markdown, or JSON.
    .DESCRIPTION
        'text'     -> deterministic, machine-parseable lines (used for CI assertions)
        'markdown' -> a GitHub-flavoured table (used for the job step summary)
        'json'     -> { summary, dependencies } object for downstream tooling
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Report,
        [Parameter(Mandatory)]$Summary,
        [ValidateSet('text', 'markdown', 'json')]
        [string]$Format = 'text'
    )

    $verdict = if ($Summary.Compliant) { 'COMPLIANT' } else { 'NON-COMPLIANT' }

    switch ($Format) {
        'json' {
            $payload = [ordered]@{
                summary = [ordered]@{
                    approved  = $Summary.Approved
                    denied    = $Summary.Denied
                    unknown   = $Summary.Unknown
                    total     = $Summary.Total
                    compliant = $Summary.Compliant
                }
                dependencies = @(
                    foreach ($r in $Report) {
                        [ordered]@{
                            name    = $r.Name
                            version = $r.Version
                            license = $r.License
                            status  = $r.Status
                        }
                    }
                )
            }
            return ($payload | ConvertTo-Json -Depth 5)
        }

        'markdown' {
            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add('## Dependency License Compliance Report')
            $lines.Add('')
            $lines.Add('| Dependency | Version | License | Status |')
            $lines.Add('| --- | --- | --- | --- |')
            foreach ($r in $Report) {
                $lines.Add("| $($r.Name) | $($r.Version) | $($r.License) | $($r.Status) |")
            }
            $lines.Add('')
            $lines.Add("**Summary:** approved=$($Summary.Approved), denied=$($Summary.Denied), unknown=$($Summary.Unknown), total=$($Summary.Total)")
            $lines.Add('')
            $lines.Add("**Overall: $verdict**")
            return ($lines -join "`n")
        }

        default {
            # 'text'
            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add('=== Dependency License Compliance Report ===')
            $lines.Add("Dependencies: $($Summary.Total)")
            $lines.Add('---')
            foreach ($r in $Report) {
                $lines.Add("DEP name=$($r.Name) version=$($r.Version) license=$($r.License) status=$($r.Status)")
            }
            $lines.Add('---')
            $lines.Add("RESULT approved=$($Summary.Approved) denied=$($Summary.Denied) unknown=$($Summary.Unknown) total=$($Summary.Total)")
            $lines.Add("COMPLIANCE: $verdict")
            return ($lines -join "`n")
        }
    }
}

Export-ModuleMember -Function @(
    'Get-LicenseStatus'
    'Get-DependencyList'
    'Read-LicensePolicy'
    'Read-LicenseDatabase'
    'Resolve-DependencyLicense'
    'Get-ComplianceReport'
    'Get-ComplianceSummary'
    'Format-ComplianceReport'
)
