# ActHarness.psm1
#
# Helpers that drive the Secret Rotation Validator workflow through nektos/act.
#
# Each test case is run in a *fresh, isolated* temporary git repository that
# contains only the project files the workflow needs plus that case's fixture
# data (written to fixtures/config.json — the path the workflow reads). This
# mirrors how the workflow would behave on a real checkout and keeps cases from
# contaminating one another.

Set-StrictMode -Version Latest

function Invoke-ActCase {
    <#
    .SYNOPSIS
        Stage one fixture into a throwaway git repo, run `act push --rm`, capture
        the output, append it (clearly delimited) to the result log, and return
        the exit code + output for assertions.

    .PARAMETER CaseName
        Short identifier for the case (used in the log header and temp dir name).

    .PARAMETER FixturePath
        Absolute path to the fixture JSON to use as the active config.

    .PARAMETER ProjectRoot
        Absolute path to the project root (where SecretRotationValidator.ps1,
        the workflow, and .actrc live).

    .PARAMETER ResultLog
        Absolute path to act-result.txt; this case's output is appended to it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$CaseName,
        [Parameter(Mandatory)] [string]$FixturePath,
        [Parameter(Mandatory)] [string]$ProjectRoot,
        [Parameter(Mandatory)] [string]$ResultLog
    )

    if (-not (Test-Path -LiteralPath $FixturePath)) {
        throw "Fixture not found for case '$CaseName': $FixturePath"
    }

    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("act-secrot-$CaseName-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null

    try {
        # --- Stage the minimal project the workflow consumes -----------------
        Copy-Item (Join-Path $ProjectRoot 'SecretRotationValidator.ps1')       (Join-Path $tmp 'SecretRotationValidator.ps1')
        Copy-Item (Join-Path $ProjectRoot 'SecretRotationValidator.Tests.ps1') (Join-Path $tmp 'SecretRotationValidator.Tests.ps1')
        Copy-Item (Join-Path $ProjectRoot '.actrc')                            (Join-Path $tmp '.actrc')

        New-Item -ItemType Directory -Path (Join-Path $tmp '.github/workflows') -Force | Out-Null
        Copy-Item (Join-Path $ProjectRoot '.github/workflows/secret-rotation-validator.yml') `
                  (Join-Path $tmp '.github/workflows/secret-rotation-validator.yml')

        New-Item -ItemType Directory -Path (Join-Path $tmp 'fixtures') -Force | Out-Null
        # This case's fixture becomes the active config the workflow reads.
        Copy-Item $FixturePath (Join-Path $tmp 'fixtures/config.json')

        # --- Turn it into a git repo on a branch the push filter accepts -----
        Push-Location $tmp
        try {
            git init -q
            # Point the (unborn) branch at 'master' so the workflow's
            # `on.push.branches: [main, master]` filter matches under act.
            git symbolic-ref HEAD refs/heads/master
            git config user.email 'act@example.com'
            git config user.name  'act runner'
            git config commit.gpgsign false
            git add -A
            git commit -q -m "act case: $CaseName"

            # --- Run the workflow in an isolated container -------------------
            # --pull=false: use the locally pre-built act-ubuntu-pwsh image
            # (it is not in a registry, so a pull would fail).
            $actOutput = (& act push --rm --pull=false 2>&1 | Out-String)
            $actExit = $LASTEXITCODE
        }
        finally {
            Pop-Location
        }

        # --- Append to the shared result log, clearly delimited --------------
        $delim = '=' * 100
        $header = @"
$delim
TEST CASE : $CaseName
FIXTURE   : $FixturePath
ACT EXIT  : $actExit
TIMESTAMP : $((Get-Date).ToString('u'))
$delim
"@
        Add-Content -LiteralPath $ResultLog -Value $header
        Add-Content -LiteralPath $ResultLog -Value $actOutput
        Add-Content -LiteralPath $ResultLog -Value ''

        return [pscustomobject]@{
            CaseName = $CaseName
            ExitCode = $actExit
            Output   = $actOutput
        }
    }
    finally {
        Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    }
}

Export-ModuleMember -Function Invoke-ActCase
