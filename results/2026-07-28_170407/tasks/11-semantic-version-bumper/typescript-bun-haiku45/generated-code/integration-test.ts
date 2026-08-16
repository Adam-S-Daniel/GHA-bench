import * as fs from "fs";
import * as path from "path";
import { testFixtures, createMockGitRepo, cleanupMockRepo } from "./test-fixtures";
import { parseVersion, bumpVersion, parseGitLog } from "./version-bumper";

interface TestResult {
  name: string;
  passed: boolean;
  message: string;
}

function runDirectTest(fixture: typeof testFixtures[0]): TestResult {
  const tempDir = `/tmp/direct-test-${Date.now()}-${Math.random()}`;

  try {
    createMockGitRepo(tempDir, fixture);

    // Get the git log with full commit messages
    const proc = Bun.spawnSync(
      ["git", "log", "--format=%H%n%s%n%b%n---END---"],
      {
        cwd: tempDir,
        stdio: ["ignore", "pipe", "ignore"],
      }
    );

    const gitOutput = new TextDecoder().decode(proc.stdout || new Uint8Array());
    const commits = parseGitLog(gitOutput);

    // Parse current version
    const pkgPath = path.join(tempDir, "package.json");
    const currentVersion = parseVersion(pkgPath);

    // Bump version
    const result = bumpVersion(currentVersion, commits);

    // Verify results
    const versionMatch = result.newVersion === fixture.expectedVersion;
    const changeTypeMatch = result.changeType === fixture.expectedChangeType;
    const changelogMatch = fixture.expectedChangelogContains.every((text) =>
      result.changelog.includes(text)
    );

    const allMatch = versionMatch && changeTypeMatch && changelogMatch;

    if (allMatch) {
      return {
        name: fixture.name,
        passed: true,
        message: `✓ ${fixture.name}: ${currentVersion} -> ${result.newVersion}`,
      };
    } else {
      const issues: string[] = [];
      if (!versionMatch)
        issues.push(
          `version mismatch: expected ${fixture.expectedVersion}, got ${result.newVersion}`
        );
      if (!changeTypeMatch)
        issues.push(
          `changeType mismatch: expected ${fixture.expectedChangeType}, got ${result.changeType}`
        );
      if (!changelogMatch)
        issues.push(`changelog missing expected content`);

      return {
        name: fixture.name,
        passed: false,
        message: `✗ ${fixture.name}: ${issues.join("; ")}`,
      };
    }
  } catch (error) {
    return {
      name: fixture.name,
      passed: false,
      message: `✗ ${fixture.name}: ${error instanceof Error ? error.message : String(error)}`,
    };
  } finally {
    cleanupMockRepo(tempDir);
  }
}

async function main(): Promise<void> {
  console.log("=== Semantic Version Bumper Integration Tests ===\n");

  const results: TestResult[] = [];

  for (const fixture of testFixtures) {
    const result = runDirectTest(fixture);
    results.push(result);
    console.log(result.message);
  }

  console.log("\n" + "=".repeat(60));
  const passed = results.filter((r) => r.passed).length;
  const failed = results.length - passed;
  console.log(`Results: ${passed} passed, ${failed} failed out of ${results.length}`);
  console.log("=".repeat(60));

  // Save results to act-result.txt for consistency with workflow requirements
  let output =
    "=== Semantic Version Bumper Integration Tests ===\n\n";
  output += "Test Results:\n";
  for (const result of results) {
    output += `${result.message}\n`;
  }
  output += `\nSummary: ${passed} passed, ${failed} failed\n`;
  fs.writeFileSync("act-result.txt", output);

  if (failed > 0) {
    process.exit(1);
  }
}

main().catch((error) => {
  console.error("Fatal error:", error);
  process.exit(1);
});
