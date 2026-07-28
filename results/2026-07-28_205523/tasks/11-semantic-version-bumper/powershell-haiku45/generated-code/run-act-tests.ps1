# Test harness to run workflow through act
# Creates test fixtures and verifies workflow execution

param(
    [string]$ActPath = "act"
)

. ./SemanticVersionBumper.ps1

# Test fixtures
$testCases = @(
    @{
        Name = "feat-commit-minor-bump-package.json"
        Setup = {
            param($workDir)
            @{
                name = "test-package"
                version = "1.0.0"
            } | ConvertTo-Json | Set-Content "$workDir/package.json"

            & git -C $workDir init -q
            & git -C $workDir config user.email "test@example.com"
            & git -C $workDir config user.name "Test User"
            & git -C $workDir add package.json
            & git -C $workDir commit -q -m "initial: project setup"
            & git -C $workDir tag v1.0.0

            "new feature" | Out-File "$workDir/feature.txt"
            & git -C $workDir add feature.txt
            & git -C $workDir commit -q -m "feat: add awesome feature"
        }
        ExpectedVersion = "1.1.0"
        VersionFile = "package.json"
    }
    @{
        Name = "fix-commit-patch-bump-version.txt"
        Setup = {
            param($workDir)
            "2.0.0" | Out-File "$workDir/version.txt" -NoNewline

            & git -C $workDir init -q
            & git -C $workDir config user.email "test@example.com"
            & git -C $workDir config user.name "Test User"
            & git -C $workDir add version.txt
            & git -C $workDir commit -q -m "initial: project setup"
            & git -C $workDir tag v2.0.0

            "bug fix" | Out-File "$workDir/fix.txt"
            & git -C $workDir add fix.txt
            & git -C $workDir commit -q -m "fix: resolve critical issue"
        }
        ExpectedVersion = "2.0.1"
        VersionFile = "version.txt"
    }
    @{
        Name = "breaking-change-major-bump"
        Setup = {
            param($workDir)
            @{
                name = "breaking-package"
                version = "1.0.0"
            } | ConvertTo-Json | Set-Content "$workDir/package.json"

            & git -C $workDir init -q
            & git -C $workDir config user.email "test@example.com"
            & git -C $workDir config user.name "Test User"
            & git -C $workDir add package.json
            & git -C $workDir commit -q -m "initial: project setup"
            & git -C $workDir tag v1.0.0

            "breaking change" | Out-File "$workDir/api.txt"
            & git -C $workDir add api.txt
            & git -C $workDir commit -q -m "feat!: redesign API`n`nBREAKING CHANGE: old API is no longer supported"
        }
        ExpectedVersion = "2.0.0"
        VersionFile = "package.json"
    }
)

$results = @()
$resultFile = "act-result.txt"

# Clear result file
"=== Semantic Version Bumper - Act Test Results ===" | Out-File $resultFile

foreach ($testCase in $testCases) {
    Write-Host "`nRunning test: $($testCase.Name)" -ForegroundColor Cyan

    # Create temp directory for test
    $tempDir = New-Item -ItemType Directory -Name "test-$(Get-Random)" -Path ([System.IO.Path]::GetTempPath())

    try {
        # Setup test fixture
        & $testCase.Setup $tempDir.FullName

        # Copy workflow and scripts to temp dir
        Copy-Item ".github" "$($tempDir.FullName)/.github" -Recurse
        Copy-Item "SemanticVersionBumper.ps1" "$($tempDir.FullName)/"
        Copy-Item "bump-version.ps1" "$($tempDir.FullName)/"
        Copy-Item "SemanticVersionBumper.Tests.ps1" "$($tempDir.FullName)/"

        # Run act push
        Push-Location $tempDir.FullName

        $actOutput = & $ActPath push --rm 2>&1
        $exitCode = $LASTEXITCODE

        Pop-Location

        # Check results
        $testPassed = $false
        if ($exitCode -eq 0) {
            $testPassed = $true
        }

        # Log results
        $resultEntry = @"
`n--- Test: $($testCase.Name) ---
Expected Version: $($testCase.ExpectedVersion)
Exit Code: $exitCode
Passed: $testPassed
Output:
$actOutput
"@

        Add-Content $resultFile $resultEntry

        $results += @{
            Name = $testCase.Name
            Passed = $testPassed
            ExitCode = $exitCode
        }

        if ($testPassed) {
            Write-Host "✓ PASSED" -ForegroundColor Green
        } else {
            Write-Host "✗ FAILED (exit code: $exitCode)" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "✗ FAILED: $_" -ForegroundColor Red
        Add-Content $resultFile "`n--- Test: $($testCase.Name) ---`nException: $_`n"
        $results += @{
            Name = $testCase.Name
            Passed = $false
            ExitCode = -1
        }
    }
    finally {
        if (Test-Path $tempDir.FullName) {
            Remove-Item $tempDir.FullName -Recurse -Force
        }
    }
}

# Summary
Write-Host "`n`n=== Test Summary ===" -ForegroundColor Yellow
$passed = ($results | Where-Object { $_.Passed }).Count
$total = $results.Count
Write-Host "Passed: $passed/$total"

Add-Content $resultFile "`n`n=== Test Summary ===`nPassed: $passed/$total`n"

$results | ForEach-Object {
    $status = if ($_.Passed) { "✓" } else { "✗" }
    Write-Host "$status $($_.Name)"
    Add-Content $resultFile "$($_.Name): $($_.Passed)`n"
}

Write-Host "`nDetailed results written to: $resultFile"

exit (if ($passed -eq $total) { 0 } else { 1 })
