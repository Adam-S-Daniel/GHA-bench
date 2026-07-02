/**
 * End-to-end pipeline test harness.
 *
 * Every test case runs through the real GitHub Actions workflow via act:
 *   1. copy the project into a fresh temp git repo
 *   2. overwrite secrets.json with the case's fixture data and commit
 *   3. run `act push --rm` and capture all output
 *   4. append the output to act-result.txt (delimited per case)
 *   5. assert exit code 0, every job succeeded, and EXACT expected values
 *      (specific markdown table rows, JSON summary counts, error-handling
 *      marker, and a clean bun test run) in the act output.
 *
 * Run with: bun run scripts/run-act-tests.ts
 */
import { cpSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const ROOT = join(import.meta.dir, "..");
const RESULT_FILE = join(ROOT, "act-result.txt");

/** Files that make up the project inside each temp repo. */
const PROJECT_FILES = [
  "package.json",
  "tsconfig.json",
  "src",
  "tests",
  "fixtures",
  "secrets.json",
  ".github",
  ".actrc", // maps ubuntu-latest to the local runner image
];

interface TestCase {
  name: string;
  /** Fixture (relative to ROOT) copied to secrets.json in the temp repo. */
  fixture: string;
  /** Exact substrings that MUST appear in the act output. */
  expected: string[];
}

// Expected values are the known-good results for each fixture with
// REFERENCE_DATE=2026-07-02 and a 14-day window (both pinned in the
// workflow), computed by hand from lastRotated + rotationPolicyDays.
const CASES: TestCase[] = [
  {
    name: "mixed-urgencies",
    fixture: "fixtures/mixed-secrets.json",
    expected: [
      // bun test ran inside the pipeline and everything passed
      " 0 fail",
      // markdown notification sections with exact bucket counts
      "## EXPIRED (2)",
      "## WARNING (1)",
      "## OK (1)",
      // exact table rows: name | lastRotated | policy | expiresOn | days | services
      "| db-password | 2026-01-01 | 90 | 2026-04-01 | -92 | auth-service, billing-api |",
      "| oauth-client-secret | 2026-04-10 | 83 | 2026-07-02 | 0 | web-frontend |",
      "| api-key-stripe | 2026-05-01 | 70 | 2026-07-10 | 8 | billing-api |",
      "| jwt-signing-key | 2026-06-20 | 180 | 2026-12-17 | 168 | auth-service, web-frontend, billing-api |",
      // exact JSON summary counts
      '"expired": 2,',
      '"warning": 1,',
      '"ok": 1',
      // graceful-failure check on the invalid config ran and passed
      'Error: secret at index 0: "name" must be a non-empty string',
      "error-handling-check: PASSED",
    ],
  },
  {
    name: "all-ok",
    fixture: "fixtures/all-ok-secrets.json",
    expected: [
      " 0 fail",
      "## EXPIRED (0)",
      "## WARNING (0)",
      "## OK (2)",
      "| s3-backup-key | 2026-06-15 | 90 | 2026-09-13 | 73 | backup-service |",
      "| grafana-admin-token | 2026-06-01 | 365 | 2027-06-01 | 334 | monitoring |",
      '"expired": 0,',
      '"warning": 0,',
      '"ok": 2',
      "error-handling-check: PASSED",
    ],
  },
];

/** Both workflow jobs must report success in act's output. */
const JOB_SUCCESS_PATTERNS = [
  /\[Secret Rotation Validator\/test\].*Job succeeded/,
  /\[Secret Rotation Validator\/report\].*Job succeeded/,
];

function sh(cwd: string, cmd: string[]): void {
  const proc = Bun.spawnSync(cmd, { cwd, stdout: "pipe", stderr: "pipe" });
  if (proc.exitCode !== 0) {
    throw new Error(
      `command failed (${cmd.join(" ")}): ${proc.stderr.toString()}`,
    );
  }
}

/** Build the temp repo for one case and return its path. */
function setUpTempRepo(testCase: TestCase): string {
  const dir = mkdtempSync(join(tmpdir(), `act-${testCase.name}-`));
  for (const file of PROJECT_FILES) {
    cpSync(join(ROOT, file), join(dir, file), { recursive: true });
  }
  // Overwrite the default secrets config with this case's fixture data.
  cpSync(join(ROOT, testCase.fixture), join(dir, "secrets.json"));

  sh(dir, ["git", "init", "-q"]);
  sh(dir, ["git", "add", "-A"]);
  sh(dir, [
    "git",
    "-c", "user.email=harness@example.com",
    "-c", "user.name=Act Harness",
    "commit", "-qm", `pipeline test case: ${testCase.name}`,
  ]);
  return dir;
}

async function runCase(testCase: TestCase): Promise<string[]> {
  const failures: string[] = [];
  const dir = setUpTempRepo(testCase);
  console.log(`\n=== running case "${testCase.name}" via act push ===`);

  try {
    // --pull=false: the runner image is local-only; pulling would fail.
    const proc = Bun.spawnSync(["act", "push", "--rm", "--pull=false"], {
      cwd: dir,
      stdout: "pipe",
      stderr: "pipe",
    });
    const output = proc.stdout.toString() + proc.stderr.toString();

    // 2. Persist all act output, clearly delimited per case.
    const delimited =
      `\n${"=".repeat(70)}\n=== TEST CASE: ${testCase.name} (fixture: ${testCase.fixture}) ===\n` +
      `=== act exit code: ${proc.exitCode} ===\n${"=".repeat(70)}\n${output}`;
    await Bun.write(RESULT_FILE, previousResults + delimited);
    previousResults += delimited;

    // 3. act itself must succeed.
    if (proc.exitCode !== 0) {
      failures.push(`act exited with code ${proc.exitCode} (expected 0)`);
    }
    // 5. Every job must report success.
    for (const pattern of JOB_SUCCESS_PATTERNS) {
      if (!pattern.test(output)) {
        failures.push(`missing job success marker: ${pattern}`);
      }
    }
    // 4. Exact expected values for this case's input.
    for (const needle of testCase.expected) {
      if (!output.includes(needle)) {
        failures.push(`missing exact expected output: ${JSON.stringify(needle)}`);
      }
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
  return failures;
}

let previousResults = ""; // accumulated act-result.txt content

let failedCases = 0;
for (const testCase of CASES) {
  const failures = await runCase(testCase);
  if (failures.length === 0) {
    console.log(`PASS: ${testCase.name}`);
  } else {
    failedCases++;
    console.error(`FAIL: ${testCase.name}`);
    for (const f of failures) console.error(`  - ${f}`);
  }
}

console.log(
  `\n${CASES.length - failedCases}/${CASES.length} pipeline cases passed; ` +
    `full act output saved to ${RESULT_FILE}`,
);
process.exit(failedCases === 0 ? 0 : 1);
