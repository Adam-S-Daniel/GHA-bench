// ACT integration test harness
// Runs the GitHub Actions workflow through act and validates output

import { execSync } from "child_process";
import { writeFileSync, appendFileSync, existsSync, unlinkSync } from "fs";
import { mkdtempSync, rmSync } from "fs";
import { join } from "path";

interface TestCase {
  name: string;
  commits: Array<{ message: string }>;
  expectedVersion: string;
  previousTag: string;
}

const testCases: TestCase[] = [
  {
    name: "Feature commit bumps minor version",
    commits: [{ message: "feat: add new feature" }],
    expectedVersion: "1.1.0",
    previousTag: "v1.0.0",
  },
  {
    name: "Fix commit bumps patch version",
    commits: [{ message: "fix: resolve bug" }],
    expectedVersion: "1.0.1",
    previousTag: "v1.0.0",
  },
  {
    name: "Breaking change bumps major version",
    commits: [{ message: "feat!: remove deprecated API" }],
    expectedVersion: "2.0.0",
    previousTag: "v1.0.0",
  },
  {
    name: "Multiple commits prioritizes highest bump",
    commits: [
      { message: "fix: fix bug" },
      { message: "feat: add feature" },
    ],
    expectedVersion: "1.1.0",
    previousTag: "v1.0.0",
  },
];

function setupTestRepo(testDir: string, commits: Array<{ message: string }>) {
  // Initialize git repo
  execSync("git init", { cwd: testDir, stdio: "ignore" });
  execSync("git config user.email test@test.com", { cwd: testDir });
  execSync("git config user.name Test", { cwd: testDir });

  // Create initial commit and tag
  writeFileSync(join(testDir, "README.md"), "# Test Project\n");
  execSync("git add README.md", { cwd: testDir });
  execSync("git commit -m 'initial: setup'", { cwd: testDir });
  execSync("git tag v1.0.0", { cwd: testDir });

  // Add test commits
  for (let i = 0; i < commits.length; i++) {
    const filePath = join(testDir, `file${i}.txt`);
    writeFileSync(filePath, `content ${i}`);
    execSync(`git add file${i}.txt`, { cwd: testDir });
    execSync(`git commit -m "${commits[i].message}"`, { cwd: testDir });
  }
}

function runActTest(
  testDir: string,
  testName: string
): { success: boolean; output: string } {
  try {
    const output = execSync(
      `cd "${testDir}" && act push --rm --quiet 2>&1`,
      { encoding: "utf-8", maxBuffer: 10 * 1024 * 1024 }
    );

    return { success: output.includes("Job succeeded"), output };
  } catch (error) {
    const output = error instanceof Error ? error.message : String(error);
    return {
      success: false,
      output,
    };
  }
}

async function main() {
  console.log("Starting ACT integration tests...\n");

  const resultFile = join(process.cwd(), "act-result.txt");

  // Clear result file if it exists
  if (existsSync(resultFile)) {
    unlinkSync(resultFile);
  }

  let allPassed = true;

  for (const testCase of testCases) {
    console.log(`Running test: ${testCase.name}`);

    const tempDir = mkdtempSync("/tmp/act-test-");

    try {
      // Setup test repository
      setupTestRepo(tempDir, testCase.commits);

      // Run act
      const { success, output } = runActTest(tempDir, testCase.name);

      // Write to result file
      const resultEntry = `
================================================================================
Test: ${testCase.name}
Expected Version: ${testCase.expectedVersion}
Status: ${success ? "PASS" : "FAIL"}
================================================================================
${output}
`;

      appendFileSync(resultFile, resultEntry);

      if (!success) {
        allPassed = false;
        console.error(`✗ ${testCase.name}`);
      } else {
        // Verify the expected version is in the output
        if (output.includes(testCase.expectedVersion)) {
          console.log(`✓ ${testCase.name}`);
        } else {
          console.error(`✗ ${testCase.name} - Version not found in output`);
          allPassed = false;
        }
      }
    } catch (error) {
      allPassed = false;
      const errorOutput = error instanceof Error ? error.message : String(error);
      console.error(
        `✗ ${testCase.name} - Error: ${errorOutput.substring(0, 100)}`
      );
      appendFileSync(
        resultFile,
        `\nTest: ${testCase.name}\nError: ${errorOutput}\n`
      );
    } finally {
      rmSync(tempDir, { recursive: true, force: true });
    }
  }

  console.log("\n" + "=".repeat(80));
  console.log(`Results written to ${resultFile}`);

  if (allPassed) {
    console.log("All tests passed!");
    process.exit(0);
  } else {
    console.error("Some tests failed.");
    process.exit(1);
  }
}

main().catch((error) => {
  console.error("Fatal error:", error);
  process.exit(1);
});
