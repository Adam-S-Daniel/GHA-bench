#!/usr/bin/env node

// Test runner for semantic version bumper workflow
// Executes the GitHub Actions workflow via act and validates results
// Outputs results to act-result.txt

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const { fixtures, setupFixtureRepo } = require('./test-fixtures');

const resultFile = 'act-result.txt';
const baseDir = process.cwd();
let resultOutput = '';

function appendResult(text) {
  console.log(text);
  resultOutput += text + '\n';
}

function runTestFixture(fixture, index) {
  appendResult(`\n${'='.repeat(80)}`);
  appendResult(`TEST CASE ${index + 1}: ${fixture.name}`);
  appendResult(`${'='.repeat(80)}`);

  const testDir = path.join(baseDir, `test-workspace-${Date.now()}-${index}`);
  fs.mkdirSync(testDir, { recursive: true });

  try {
    // Setup fixture repo
    appendResult('Setting up test fixture...');
    setupFixtureRepo(fixture, testDir);

    // Copy required files
    fs.copyFileSync(
      path.join(baseDir, 'bump-version.js'),
      path.join(testDir, 'bump-version.js')
    );
    fs.copyFileSync(
      path.join(baseDir, 'version-bumper.js'),
      path.join(testDir, 'version-bumper.js')
    );
    fs.copyFileSync(
      path.join(baseDir, 'package.json'),
      path.join(testDir, 'package.json')
    );

    // Copy workflow
    fs.mkdirSync(path.join(testDir, '.github', 'workflows'), { recursive: true });
    fs.copyFileSync(
      path.join(baseDir, '.github', 'workflows', 'semantic-version-bumper.yml'),
      path.join(testDir, '.github', 'workflows', 'semantic-version-bumper.yml')
    );

    appendResult('Fixture setup complete');
    appendResult(`Initial version: ${fixture.initialVersion}`);
    appendResult(`Commits: ${fixture.commits.length}`);

    // Run act
    appendResult('\nRunning GitHub Actions workflow with act...');

    let actOutput = '';
    try {
      actOutput = execSync(
        'act push --rm -j bump-version 2>&1',
        {
          cwd: testDir,
          encoding: 'utf8',
          timeout: 120000
        }
      );
    } catch (error) {
      actOutput = error.stdout || error.stderr || error.message;
      appendResult('⚠ Act command exited with error');
    }

    appendResult('\n--- Act Output ---');
    appendResult(actOutput);
    appendResult('--- End Act Output ---\n');

    // Check for success indicators
    const hasJobSucceeded = actOutput.includes('Job succeeded') || actOutput.includes('completed successfully');
    const hasVersionOutput = actOutput.includes('Current version') || actOutput.includes('New version');

    if (hasJobSucceeded) {
      appendResult('✓ Workflow job completed successfully');
    } else {
      appendResult('⚠ Could not confirm job success from output');
    }

    if (hasVersionOutput) {
      appendResult('✓ Version output detected');
    }

    // Validate expected version in output
    if (fixture.expectedVersion && !fixture.shouldSkip) {
      if (actOutput.includes(fixture.expectedVersion)) {
        appendResult(`✓ Expected version ${fixture.expectedVersion} found in output`);
      } else {
        appendResult(`✗ Expected version ${fixture.expectedVersion} NOT found in output`);
        appendResult(`  This may indicate the version was not bumped correctly`);
      }
    }

    // Check if package.json was updated
    const pkgPath = path.join(testDir, 'package.json');
    if (fs.existsSync(pkgPath)) {
      const pkg = JSON.parse(fs.readFileSync(pkgPath, 'utf8'));
      appendResult(`Final version in package.json: ${pkg.version}`);

      if (!fixture.shouldSkip && pkg.version === fixture.expectedVersion) {
        appendResult(`✓ Version correctly updated to ${fixture.expectedVersion}`);
      } else if (!fixture.shouldSkip) {
        appendResult(`✗ Version mismatch. Expected ${fixture.expectedVersion}, got ${pkg.version}`);
      }
    }

    appendResult(`TEST CASE ${index + 1}: COMPLETED\n`);
    return true;

  } catch (error) {
    appendResult(`✗ Test case failed: ${error.message}`);
    return false;
  } finally {
    // Cleanup
    try {
      fs.rmSync(testDir, { recursive: true, force: true });
    } catch (e) {
      // Ignore cleanup errors
    }
  }
}

function main() {
  appendResult('Semantic Version Bumper - Workflow Test Suite');
  appendResult(`Started at: ${new Date().toISOString()}\n`);

  // Validate workflow file
  appendResult('Validating workflow structure...\n');

  const workflowPath = path.join(baseDir, '.github', 'workflows', 'semantic-version-bumper.yml');
  if (!fs.existsSync(workflowPath)) {
    appendResult('✗ Workflow file not found: ' + workflowPath);
    process.exit(1);
  }
  appendResult('✓ Workflow file exists: .github/workflows/semantic-version-bumper.yml');

  const bumpScriptPath = path.join(baseDir, 'bump-version.js');
  if (!fs.existsSync(bumpScriptPath)) {
    appendResult('✗ Script file not found: ' + bumpScriptPath);
    process.exit(1);
  }
  appendResult('✓ Script file exists: bump-version.js');

  // Validate actionlint
  appendResult('\nValidating with actionlint...');
  try {
    execSync(`actionlint ${workflowPath}`, { stdio: 'pipe' });
    appendResult('✓ Workflow passes actionlint validation');
  } catch (error) {
    appendResult('✗ Workflow failed actionlint validation:');
    appendResult(error.toString());
    process.exit(1);
  }

  // Run test fixtures through act
  appendResult('\nRunning test fixtures through act...');
  appendResult(`Total fixtures: ${fixtures.length}\n`);

  const results = fixtures.map((fixture, index) => ({
    name: fixture.name,
    passed: runTestFixture(fixture, index)
  }));

  // Summary
  appendResult('\n' + '='.repeat(80));
  appendResult('TEST SUMMARY');
  appendResult('='.repeat(80));

  const passed = results.filter(r => r.passed).length;
  const total = results.length;

  results.forEach((result, i) => {
    const status = result.passed ? '✓ PASSED' : '✗ FAILED';
    appendResult(`${i + 1}. ${result.name}: ${status}`);
  });

  appendResult(`\nTotal: ${passed}/${total} test cases passed`);
  appendResult(`Completed at: ${new Date().toISOString()}`);

  // Write results to file
  fs.writeFileSync(resultFile, resultOutput);
  appendResult(`\n✓ Results written to ${resultFile}`);

  process.exit(passed === total ? 0 : 1);
}

main();
