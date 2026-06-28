#Requires -Version 7.0
<#
    Helpers for tests/ActAcceptance.Tests.ps1.

    Kept in a standalone file and dot-sourced from BOTH Pester phases (top-level
    for discovery's -ForEach, and inside BeforeAll for the run phase), because
    functions defined at a Pester test file's top level are visible during
    discovery only — not during the run phase.
#>

# The acceptance test cases: each is a self-contained fixture plus its
# hand-computed, exact expected summary. These same fixtures were verified
# directly against the CLI before being locked in here.
function Get-AcceptanceCases {
    @(
        @{
            Name    = 'A-all-policies'
            Fixture = @'
{
  "referenceDate": "2026-06-28T00:00:00Z",
  "dryRun": true,
  "policies": { "maxAgeDays": 30, "keepLatestN": 2, "maxTotalSizeBytes": 10000 },
  "artifacts": [
    { "name": "r1001-coverage", "sizeBytes": 1500, "createdAt": "2026-06-27T00:00:00Z", "workflowRunId": "1001" },
    { "name": "r1001-logs",     "sizeBytes": 1000, "createdAt": "2026-06-26T00:00:00Z", "workflowRunId": "1001" },
    { "name": "r1001-binaries", "sizeBytes": 4000, "createdAt": "2026-06-25T00:00:00Z", "workflowRunId": "1001" },
    { "name": "r1002-logs",     "sizeBytes": 800,  "createdAt": "2026-06-20T00:00:00Z", "workflowRunId": "1002" },
    { "name": "r1002-coverage", "sizeBytes": 1200, "createdAt": "2026-06-19T00:00:00Z", "workflowRunId": "1002" },
    { "name": "r0999-logs",     "sizeBytes": 700,  "createdAt": "2026-05-01T00:00:00Z", "workflowRunId": "0999" },
    { "name": "r0999-binaries", "sizeBytes": 9000, "createdAt": "2026-04-15T00:00:00Z", "workflowRunId": "0999" }
  ]
}
'@
            Expected = @{
                TotalArtifacts = 7; DeletedCount = 3; RetainedCount = 4
                SpaceReclaimedBytes = 13700; RetainedSizeBytes = 4500; TotalSizeBytes = 18200
            }
            ExpectDelete = 'DELETE name=r0999-binaries.*reasons=MaxAge'
        },
        @{
            Name    = 'B-size-cap'
            Fixture = @'
{
  "referenceDate": "2026-06-28T00:00:00Z",
  "dryRun": true,
  "policies": { "maxTotalSizeBytes": 5000 },
  "artifacts": [
    { "name": "big-old",   "sizeBytes": 4000, "createdAt": "2026-06-10T00:00:00Z", "workflowRunId": "2001" },
    { "name": "mid",       "sizeBytes": 3000, "createdAt": "2026-06-15T00:00:00Z", "workflowRunId": "2001" },
    { "name": "small-new", "sizeBytes": 1000, "createdAt": "2026-06-20T00:00:00Z", "workflowRunId": "2001" }
  ]
}
'@
            Expected = @{
                TotalArtifacts = 3; DeletedCount = 1; RetainedCount = 2
                SpaceReclaimedBytes = 4000; RetainedSizeBytes = 4000; TotalSizeBytes = 8000
            }
            ExpectDelete = 'DELETE name=big-old.*reasons=MaxTotalSize'
        },
        @{
            Name    = 'C-keep-latest'
            Fixture = @'
{
  "referenceDate": "2026-06-28T00:00:00Z",
  "dryRun": true,
  "policies": { "keepLatestN": 1 },
  "artifacts": [
    { "name": "c-new", "sizeBytes": 100, "createdAt": "2026-06-27T00:00:00Z", "workflowRunId": "3001" },
    { "name": "c-old", "sizeBytes": 200, "createdAt": "2026-06-26T00:00:00Z", "workflowRunId": "3001" },
    { "name": "d-new", "sizeBytes": 300, "createdAt": "2026-06-27T00:00:00Z", "workflowRunId": "3002" },
    { "name": "d-mid", "sizeBytes": 400, "createdAt": "2026-06-26T00:00:00Z", "workflowRunId": "3002" },
    { "name": "d-old", "sizeBytes": 500, "createdAt": "2026-06-25T00:00:00Z", "workflowRunId": "3002" }
  ]
}
'@
            Expected = @{
                TotalArtifacts = 5; DeletedCount = 3; RetainedCount = 2
                SpaceReclaimedBytes = 1100; RetainedSizeBytes = 400; TotalSizeBytes = 1500
            }
            ExpectDelete = 'DELETE name=d-old.*reasons=KeepLatestN'
        }
    )
}

# Pull a numeric summary value out of the (act-prefixed) workflow output.
function Get-SummaryValue {
    param([string] $Output, [string] $Key)
    $m = [regex]::Match($Output, "$([regex]::Escape($Key)):\s*(\d+)")
    if (-not $m.Success) { return $null }
    return [long]$m.Groups[1].Value
}

# Build an isolated temp git repo for one case and run the workflow through act.
# Returns @{ Exit = <int>; Output = <string> }.
function Invoke-ActCase {
    param([string] $Root, [hashtable] $Case)

    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("actcase-$($Case.Name)-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    $prev = Get-Location
    try {
        # Copy exactly the files the workflow needs into the temp repo.
        foreach ($f in 'ArtifactCleanup.psm1', 'Invoke-Cleanup.ps1', '.actrc') {
            Copy-Item -LiteralPath (Join-Path $Root $f) -Destination (Join-Path $tmp $f) -Force
        }
        Copy-Item -LiteralPath (Join-Path $Root 'tools')   -Destination (Join-Path $tmp 'tools')   -Recurse -Force
        Copy-Item -LiteralPath (Join-Path $Root '.github') -Destination (Join-Path $tmp '.github') -Recurse -Force
        New-Item -ItemType Directory -Path (Join-Path $tmp 'tests') -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $Root 'tests/ArtifactCleanup.Tests.ps1') `
                  -Destination (Join-Path $tmp 'tests/ArtifactCleanup.Tests.ps1') -Force
        New-Item -ItemType Directory -Path (Join-Path $tmp 'fixtures') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $tmp 'fixtures/artifacts.json') -Value $Case.Fixture -Encoding utf8

        Set-Location $tmp
        git init -q                              2>&1 | Out-Null
        git config user.email 'test@example.com' 2>&1 | Out-Null
        git config user.name  'acceptance'       2>&1 | Out-Null
        git add -A                               2>&1 | Out-Null
        git commit -q -m "acceptance $($Case.Name)" 2>&1 | Out-Null

        # --pull=false: use the local pre-baked image; --action-offline-mode:
        # use the cached actions/checkout. Explicit -P mirrors the injected .actrc.
        $out = & act push --rm --pull=false --action-offline-mode `
            -P ubuntu-latest=act-ubuntu-pwsh:latest 2>&1 | Out-String
        $code = $LASTEXITCODE
        return @{ Exit = $code; Output = $out }
    }
    finally {
        Set-Location $prev
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
