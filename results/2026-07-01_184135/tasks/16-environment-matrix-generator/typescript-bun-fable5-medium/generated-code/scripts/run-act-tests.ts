/**
 * End-to-end act test harness.
 *
 * Every test case is executed THROUGH the GitHub Actions workflow via
 * `act push --rm`, never by calling the script directly:
 *
 *   1. For each case: build a temp git repo containing the project files
 *      plus that case's fixture as config.json (and an EXPECT_FAILURE
 *      marker for the error-path case), commit, and run `act push --rm`.
 *   2. Append each case's full act output, clearly delimited, to
 *      act-result.txt in the project root.
 *   3. Assert act exited 0 for every case.
 *   4. Assert the output contains the EXACT expected matrix JSON (or the
 *      exact validation error) for that case's input — known-good values
 *      hardcoded below, not merely "some output appeared".
 *   5. Assert both jobs ("Unit tests" and "Generate build matrix")
 *      report "Job succeeded".
 *
 * Run with: bun run scripts/run-act-tests.ts
 */
import { appendFileSync, cpSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const ROOT = join(import.meta.dir, "..");
const RESULT_FILE = join(ROOT, "act-result.txt");

/** Files/dirs that make up the project inside each temp repo. */
const PROJECT_FILES = [
  ".github",
  ".actrc",
  "src",
  "tests",
  "fixtures",
  "package.json",
  "tsconfig.json",
];

interface TestCase {
  name: string;
  fixture: string;
  /** Create the EXPECT_FAILURE marker consumed by the workflow. */
  expectFailure?: boolean;
  /** Exact substrings that MUST appear in the act output. */
  expectedInOutput: string[];
}

// Known-good expected values, derived from each fixture's input by hand:
// case 1: 2 OS x 2 versions x 1 feature = exactly these 4 combinations.
// case 2: 4 base combos - 1 excluded (macos/18) + 1 included (ubuntu/22/flagB) = 4.
// case 3: 3 x 4 x 3 = 36 combos > max-size 10 -> exact validation error.
const CASES: TestCase[] = [
  {
    name: "case1-basic",
    fixture: "fixtures/case1-basic.json",
    expectedInOutput: [
      'MATRIX_JSON={"strategy":{"fail-fast":true,"max-parallel":2,"matrix":{"os":["ubuntu-latest","macos-latest"],"version":["18","20"],"feature":["stable"]}},"combinations":[{"os":"ubuntu-latest","version":"18","feature":"stable"},{"os":"ubuntu-latest","version":"20","feature":"stable"},{"os":"macos-latest","version":"18","feature":"stable"},{"os":"macos-latest","version":"20","feature":"stable"}],"count":4}',
    ],
  },
  {
    name: "case2-include-exclude",
    fixture: "fixtures/case2-include-exclude.json",
    expectedInOutput: [
      'MATRIX_JSON={"strategy":{"fail-fast":false,"matrix":{"os":["ubuntu-latest","macos-latest"],"version":["18","20"],"feature":["flagA"],"include":[{"os":"ubuntu-latest","version":"22","feature":"flagB"}],"exclude":[{"os":"macos-latest","version":"18"}]}},"combinations":[{"os":"ubuntu-latest","version":"18","feature":"flagA"},{"os":"ubuntu-latest","version":"20","feature":"flagA"},{"os":"macos-latest","version":"20","feature":"flagA"},{"os":"ubuntu-latest","version":"22","feature":"flagB"}],"count":4}',
    ],
  },
  {
    name: "case3-oversized-error",
    fixture: "fixtures/case3-oversized.json",
    expectFailure: true,
    expectedInOutput: [
      "MATRIX_ERROR_CONFIRMED: error: Matrix size 36 exceeds maximum allowed size 10",
    ],
  },
];

/** Both workflow jobs must report success in the act log. */
const JOB_SUCCESS_MARKERS = [
  "[Environment Matrix Generator/Unit tests]",
  "[Environment Matrix Generator/Generate build matrix]",
];

function sh(cmd: string[], cwd: string): { code: number; output: string } {
  const proc = Bun.spawnSync(cmd, { cwd, stdout: "pipe", stderr: "pipe" });
  return {
    code: proc.exitCode,
    output: proc.stdout.toString() + proc.stderr.toString(),
  };
}

function fail(msg: string): never {
  console.error(`\nHARNESS FAILURE: ${msg}`);
  process.exit(1);
}

// Start a fresh result file for this run.
writeFileSync(RESULT_FILE, `act test run started\n`);

let passed = 0;
for (const tc of CASES) {
  console.log(`\n=== ${tc.name} ===`);
  const repo = mkdtempSync(join(tmpdir(), `matrix-act-${tc.name}-`));
  try {
    // 1. Assemble the temp repo: project files + this case's config.
    for (const f of PROJECT_FILES) {
      cpSync(join(ROOT, f), join(repo, f), { recursive: true });
    }
    cpSync(join(ROOT, tc.fixture), join(repo, "config.json"));
    if (tc.expectFailure) {
      writeFileSync(join(repo, "EXPECT_FAILURE"), "expect CLI failure\n");
    }
    for (const git of [
      ["git", "init", "-q", "-b", "main"],
      ["git", "config", "user.email", "ci@example.com"],
      ["git", "config", "user.name", "CI"],
      ["git", "add", "-A"],
      ["git", "commit", "-q", "-m", `fixture ${tc.name}`],
    ]) {
      const r = sh(git, repo);
      if (r.code !== 0) fail(`git setup failed for ${tc.name}: ${r.output}`);
    }

    // 2. Run the workflow through act and record the full output.
    console.log("running act push --rm ...");
    // --pull=false: the runner image is local-only (mapped in .actrc);
    // pulling would fail against the public registry.
    const act = sh(["act", "push", "--rm", "--pull=false"], repo);
    appendFileSync(
      RESULT_FILE,
      `\n${"=".repeat(72)}\n=== TEST CASE: ${tc.name} (fixture: ${tc.fixture}) ===\n` +
        `=== act exit code: ${act.code} ===\n${"=".repeat(72)}\n${act.output}\n`,
    );

    // 3. act itself must succeed.
    if (act.code !== 0) {
      fail(`act exited with code ${act.code} for ${tc.name} (see act-result.txt)`);
    }
    // 4. Exact expected values for this case's input.
    for (const expected of tc.expectedInOutput) {
      if (!act.output.includes(expected)) {
        fail(`${tc.name}: expected exact output not found:\n  ${expected}`);
      }
    }
    // 5. Every job must report success.
    for (const jobPrefix of JOB_SUCCESS_MARKERS) {
      const jobSucceeded = act.output
        .split("\n")
        .some((l) => l.includes(jobPrefix) && l.includes("Job succeeded"));
      if (!jobSucceeded) {
        fail(`${tc.name}: no "Job succeeded" line for ${jobPrefix}`);
      }
    }
    console.log(`PASS: ${tc.name}`);
    passed++;
  } finally {
    rmSync(repo, { recursive: true, force: true });
  }
}

appendFileSync(RESULT_FILE, `\nALL ${passed}/${CASES.length} ACT TEST CASES PASSED\n`);
console.log(`\nALL ${passed}/${CASES.length} ACT TEST CASES PASSED (details: act-result.txt)`);
