# Sets up an isolated temp git repo containing this project, runs the
# GitHub Actions workflow locally via `act push --rm`, and saves the full
# output to act-result.txt in the current working directory.
#
# This is the mandatory "workflow execution test" -- it proves the workflow
# actually runs (not just that the script's unit tests pass locally).

$ErrorActionPreference = 'Stop'

$projectRoot = $PSScriptRoot
$resultPath = Join-Path (Get-Location) 'act-result.txt'
$tempRepo = Join-Path ([System.IO.Path]::GetTempPath()) "trs-act-$([Guid]::NewGuid())"

New-Item -ItemType Directory -Path $tempRepo | Out-Null

try {
    Write-Host "Copying project files to temp repo: $tempRepo"
    Copy-Item -Path (Join-Path $projectRoot '*') -Destination $tempRepo -Recurse -Force -Exclude @('act-result.txt')
    # Copy hidden .github directory explicitly since '*' skips dotfiles/dirs.
    Copy-Item -Path (Join-Path $projectRoot '.github') -Destination $tempRepo -Recurse -Force

    Push-Location $tempRepo
    try {
        git init -q
        git config user.email 'act-test@example.com'
        git config user.name 'act-test'
        git add -A
        git commit -q -m 'test'

        Write-Host 'Running: act push --rm --pull=false'
        $output = & act push --rm --pull=false 2>&1 | Out-String
        $exitCode = $LASTEXITCODE

        $delimitedOutput = @"
===== act push --rm : exit code $exitCode =====
$output
===== end of run =====
"@
        Set-Content -LiteralPath $resultPath -Value $delimitedOutput

        Write-Host "Saved act output to $resultPath (exit code $exitCode)"
        if ($exitCode -ne 0) {
            throw "act push exited with code $exitCode"
        }
    } finally {
        Pop-Location
    }
} finally {
    Remove-Item -LiteralPath $tempRepo -Recurse -Force -ErrorAction SilentlyContinue
}
