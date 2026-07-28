# Comprehensive test harness for semantic version bumper
# Runs all tests through act and generates act-result.txt

param(
    [string]$ActPath = "act"
)

$resultFile = "act-result.txt"
$allTestsPassed = $true

# Clear and initialize result file
"=== Semantic Version Bumper - Act Test Results ===" | Out-File $resultFile
"Executed at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Add-Content $resultFile
"" | Add-Content $resultFile

# Test 1: Workflow structure validation
Write-Host "`nTest 1: Validating workflow structure..." -ForegroundColor Cyan

$workflowPath = ".github/workflows/semantic-version-bumper.yml"
if (-not (Test-Path $workflowPath)) {
    Write-Host "✗ FAILED: Workflow file not found" -ForegroundColor Red
    "Workflow Structure Test: FAILED - File not found" | Add-Content $resultFile
    $allTestsPassed = $false
} else {
    Write-Host "✓ Workflow file found" -ForegroundColor Green
    "Workflow Structure Test: PASSED - File exists at $workflowPath" | Add-Content $resultFile
}

# Test 2: actionlint validation
Write-Host "`nTest 2: Running actionlint validation..." -ForegroundColor Cyan

$actionlintOutput = & actionlint .github/workflows/semantic-version-bumper.yml 2>&1
$actionlintExit = $LASTEXITCODE

if ($actionlintExit -eq 0) {
    Write-Host "✓ actionlint validation passed" -ForegroundColor Green
    "Actionlint Validation Test: PASSED" | Add-Content $resultFile
} else {
    Write-Host "✗ actionlint validation failed" -ForegroundColor Red
    "Actionlint Validation Test: FAILED`n$actionlintOutput" | Add-Content $resultFile
    $allTestsPassed = $false
}

"" | Add-Content $resultFile

# Test 3-5: Run act test job with different test scenarios
$testScenarios = @(
    @{
        Name = "Feature Commit (Minor Bump)"
        Setup = {
            param($workDir)
            @{
                name = "test-package"
                version = "1.0.0"
            } | ConvertTo-Json | Set-Content "$workDir/package.json"

            & git -C $workDir init -q 2>$null
            & git -C $workDir config user.email "test@example.com" 2>$null
            & git -C $workDir config user.name "Test User" 2>$null
            & git -C $workDir add package.json 2>$null
            & git -C $workDir commit -q -m "initial: project setup" 2>$null
            & git -C $workDir tag v1.0.0 2>$null

            "new feature" | Out-File "$workDir/feature.txt"
            & git -C $workDir add feature.txt 2>$null
            & git -C $workDir commit -q -m "feat: add new feature" 2>$null
        }
        ExpectedVersion = "1.1.0"
        TestNumber = 3
    }
    @{
        Name = "Fix Commit (Patch Bump)"
        Setup = {
            param($workDir)
            "2.0.0" | Out-File "$workDir/version.txt" -NoNewline

            & git -C $workDir init -q 2>$null
            & git -C $workDir config user.email "test@example.com" 2>$null
            & git -C $workDir config user.name "Test User" 2>$null
            & git -C $workDir add version.txt 2>$null
            & git -C $workDir commit -q -m "initial: project setup" 2>$null
            & git -C $workDir tag v2.0.0 2>$null

            "bug fix" | Out-File "$workDir/fix.txt"
            & git -C $workDir add fix.txt 2>$null
            & git -C $workDir commit -q -m "fix: resolve critical issue" 2>$null
        }
        ExpectedVersion = "2.0.1"
        TestNumber = 4
    }
    @{
        Name = "Breaking Change (Major Bump)"
        Setup = {
            param($workDir)
            @{
                name = "breaking-package"
                version = "1.0.0"
            } | ConvertTo-Json | Set-Content "$workDir/package.json"

            & git -C $workDir init -q 2>$null
            & git -C $workDir config user.email "test@example.com" 2>$null
            & git -C $workDir config user.name "Test User" 2>$null
            & git -C $workDir add package.json 2>$null
            & git -C $workDir commit -q -m "initial: project setup" 2>$null
            & git -C $workDir tag v1.0.0 2>$null

            "breaking change" | Out-File "$workDir/api.txt"
            & git -C $workDir add api.txt 2>$null
            & git -C $workDir commit -q -m "feat!: redesign API`n`nBREAKING CHANGE: old API is no longer supported" 2>$null
        }
        ExpectedVersion = "2.0.0"
        TestNumber = 5
    }
)

foreach ($scenario in $testScenarios) {
    Write-Host "`nTest $($scenario.TestNumber): $($scenario.Name)..." -ForegroundColor Cyan

    $tempDir = New-Item -ItemType Directory -Name "test-$(Get-Random)" -Path ([System.IO.Path]::GetTempPath()) -Force

    try {
        # Setup test fixture
        & $scenario.Setup $tempDir.FullName

        # Copy necessary files
        Copy-Item ".github" "$($tempDir.FullName)/.github" -Recurse -Force
        Copy-Item "SemanticVersionBumper.ps1" "$($tempDir.FullName)/" -Force
        Copy-Item "bump-version.ps1" "$($tempDir.FullName)/" -Force
        Copy-Item "SemanticVersionBumper.Tests.ps1" "$($tempDir.FullName)/" -Force

        Push-Location $tempDir.FullName

        # Run act push
        $actOutput = & $ActPath push --rm 2>&1
        $exitCode = $LASTEXITCODE

        Pop-Location

        # Check results
        $passed = ($exitCode -eq 0)

        if ($passed) {
            Write-Host "✓ PASSED (exit code: $exitCode)" -ForegroundColor Green
        } else {
            Write-Host "✗ FAILED (exit code: $exitCode)" -ForegroundColor Red
            $allTestsPassed = $false
        }

        # Log results
        "" | Add-Content $resultFile
        "Test $($scenario.TestNumber): $($scenario.Name)" | Add-Content $resultFile
        "Expected Version: $($scenario.ExpectedVersion)" | Add-Content $resultFile
        "Exit Code: $exitCode" | Add-Content $resultFile
        "Passed: $passed" | Add-Content $resultFile
        "Output (last 100 lines):" | Add-Content $resultFile
        "-" * 80 | Add-Content $resultFile
        ($actOutput | Select-Object -Last 100) | Add-Content $resultFile
        "" | Add-Content $resultFile
    }
    catch {
        Write-Host "✗ EXCEPTION: $_" -ForegroundColor Red
        "Test $($scenario.TestNumber): $($scenario.Name) - EXCEPTION" | Add-Content $resultFile
        "Exception: $_" | Add-Content $resultFile
        "" | Add-Content $resultFile
        $allTestsPassed = $false
    }
    finally {
        if (Test-Path $tempDir.FullName) {
            Remove-Item $tempDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# Test 6: Workflow reference validation
Write-Host "`nTest 6: Validating workflow script references..." -ForegroundColor Cyan

$workflowContent = Get-Content -Path $workflowPath -Raw
$requiredFiles = @("SemanticVersionBumper.Tests.ps1", "SemanticVersionBumper.ps1", "bump-version.ps1")
$referencesValid = $true

foreach ($file in $requiredFiles) {
    if (Test-Path $file) {
        Write-Host "✓ $file found" -ForegroundColor Green
        "Workflow Reference Validation: $file - PASSED" | Add-Content $resultFile
    } else {
        Write-Host "✗ $file not found" -ForegroundColor Red
        "Workflow Reference Validation: $file - FAILED" | Add-Content $resultFile
        $referencesValid = $false
        $allTestsPassed = $false
    }
}

"" | Add-Content $resultFile

# Summary
Write-Host "`n`n=== Test Summary ===" -ForegroundColor Yellow

"=== SUMMARY ===" | Add-Content $resultFile
if ($allTestsPassed) {
    Write-Host "✓ All tests PASSED" -ForegroundColor Green
    "Result: ALL TESTS PASSED" | Add-Content $resultFile
} else {
    Write-Host "✗ Some tests FAILED" -ForegroundColor Red
    "Result: SOME TESTS FAILED" | Add-Content $resultFile
}

Write-Host "`nDetailed results written to: $resultFile"

if ($allTestsPassed) { exit 0 } else { exit 1 }
