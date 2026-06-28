<#
.SYNOPSIS
    Helpers for running the workflow end-to-end through `act` (nektos/act).

.DESCRIPTION
    These functions are dot-sourced by Workflow.Tests.ps1. They are kept in a
    separate file so the exact same temp-repo construction can be reused for a
    one-off calibration run without duplicating logic.

    The flow per test case:
      1. Create a temp git repo containing the project files (scripts + workflow
         + .actrc) and that case's fixtures copied into fixtures/.
      2. Commit, then run `act push --rm` from inside the repo.
      3. Append the (ANSI-stripped) output, clearly delimited, to act-result.txt.
      4. Return the exit code and cleaned output for assertions.
#>

# NOTE: deliberately NO `Set-StrictMode` here. This file is dot-sourced into the
# Pester test session, where strict mode would make accessing absent keys on the
# Hashtables produced by ConvertFrom-Yaml (e.g. a step without an `id`) throw.

# Strip ANSI/VT color escape sequences so assertions match the raw payload text.
function Remove-AnsiCode {
    param([string]$Text)
    if ($null -eq $Text) { return '' }
    return ($Text -replace "`e\[[0-9;]*[A-Za-z]", '')
}

# Build an isolated temp git repo: project files + this case's fixtures.
function New-TempActRepo {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$FixtureSource
    )

    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("act-trag-" + [System.Guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $tmp | Out-Null

    # Copy the files the workflow needs at the repo root.
    foreach ($f in 'Invoke-Aggregator.ps1', 'TestResultsAggregator.ps1', '.actrc') {
        $src = Join-Path $RepoRoot $f
        if (Test-Path -LiteralPath $src) {
            Copy-Item -LiteralPath $src -Destination (Join-Path $tmp $f)
        }
    }
    # Copy the workflow tree.
    Copy-Item -LiteralPath (Join-Path $RepoRoot '.github') -Destination (Join-Path $tmp '.github') -Recurse

    # Copy this case's fixtures into fixtures/ (the dir the workflow reads).
    $fixturesDst = Join-Path $tmp 'fixtures'
    New-Item -ItemType Directory -Path $fixturesDst | Out-Null
    Get-ChildItem -LiteralPath $FixtureSource -File | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $fixturesDst $_.Name)
    }

    # Initialize a git repo and make a commit (act/checkout require one).
    git -C $tmp init -b main --quiet 2>&1 | Out-Null
    git -C $tmp config user.email 'ci@example.com' 2>&1 | Out-Null
    git -C $tmp config user.name  'CI' 2>&1 | Out-Null
    git -C $tmp config commit.gpgsign false 2>&1 | Out-Null
    git -C $tmp add -A 2>&1 | Out-Null
    git -C $tmp commit -m 'test fixtures' --quiet 2>&1 | Out-Null

    return $tmp
}

# Run one act test case end-to-end and append its output to the result log.
function Invoke-ActCase {
    param(
        [Parameter(Mandatory)][string]$CaseName,
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$FixtureSource,
        [Parameter(Mandatory)][string]$ActResultFile
    )

    $tmp = New-TempActRepo -RepoRoot $RepoRoot -FixtureSource $FixtureSource
    $raw  = ''
    $code = -1
    try {
        Push-Location $tmp
        try {
            # --pull=false: the runner image (act-ubuntu-pwsh) is built locally and
            #   has no registry to pull from; act force-pulls by default.
            # --action-offline-mode: use the cached actions/checkout instead of
            #   re-fetching (and it also disables the force pull).
            # Merge stderr into stdout; capture everything act prints.
            $raw  = (& act push --rm --pull=false --action-offline-mode 2>&1 | Out-String)
            $code = $LASTEXITCODE
        } finally {
            Pop-Location
        }
    } finally {
        $clean = Remove-AnsiCode $raw

        $delimiter = ('=' * 78)
        $block = @(
            $delimiter
            "ACT TEST CASE: $CaseName"
            "Command: act push --rm   (cwd: $tmp)"
            "Exit code: $code"
            ('-' * 78)
            $clean.TrimEnd()
            $delimiter
            ''
        ) -join "`n"
        Add-Content -LiteralPath $ActResultFile -Value $block

        # Best-effort cleanup of the temp repo.
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }

    return [pscustomobject]@{
        CaseName = $CaseName
        ExitCode = $code
        Output   = (Remove-AnsiCode $raw)
    }
}
