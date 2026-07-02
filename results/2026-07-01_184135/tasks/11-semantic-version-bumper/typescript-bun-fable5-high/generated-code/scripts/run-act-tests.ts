/**
 * Act-based end-to-end test harness.
 *
 * Every test case runs through the REAL GitHub Actions pipeline via
 * `act push --rm` — nothing is tested by invoking the script directly.
 *
 * Per case:
 *   1. Build a throwaway git repo containing the project files plus the
 *      case's fixture data (its start VERSION, and its commit log copied to
 *      `commits.log`, which the workflow prefers over the default fixture).
 *   2. Run `act push --rm` in that repo and capture ALL output.
 *   3. Append the output to act-result.txt (clearly delimited per case).
 *   4. Assert: act exit code 0, EXACT expected OLD_VERSION/BUMP/NEW_VERSION
 *      values in the output, the step-output round-trip line
 *      (RESULT_NEW_VERSION=...), and a "Job succeeded" line for BOTH jobs.
 *
 * Run with: bun run scripts/run-act-tests.ts
 */
import { appendFileSync, cpSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

interface ActCase {
  name: string;
  /** Version the temp repo's VERSION file starts at. */
  startVersion: string;
  /** Fixture (in fixtures/) copied to commits.log in the temp repo. */
  fixture: string;
  expectedBump: string;
  expectedNewVersion: string;
}

// Known-good expectations, hand-derived from the semver + conventional
// commit rules: feat -> minor, fix -> patch, breaking -> major.
const CASES: ActCase[] = [
  {
    name: "feat commits bump minor: 1.1.0 -> 1.2.0",
    startVersion: "1.1.0",
    fixture: "commits-feat.log",
    expectedBump: "minor",
    expectedNewVersion: "1.2.0",
  },
  {
    name: "fix commits bump patch: 2.3.4 -> 2.3.5",
    startVersion: "2.3.4",
    fixture: "commits-fix.log",
    expectedBump: "patch",
    expectedNewVersion: "2.3.5",
  },
  {
    name: "breaking change bumps major: 1.1.0 -> 2.0.0",
    startVersion: "1.1.0",
    fixture: "commits-breaking.log",
    expectedBump: "major",
    expectedNewVersion: "2.0.0",
  },
];

const ROOT = join(import.meta.dir, "..");
const RESULT_FILE = join(ROOT, "act-result.txt");
// Files the workflow needs inside the isolated repo.
const PROJECT_FILES = ["package.json", "src", "tests", "fixtures", ".github", ".actrc"];
const JOB_NAMES = [
  "Unit and workflow-structure tests",
  "Bump version and generate changelog",
];

function sh(cmd: string[], cwd: string): { code: number; output: string } {
  const proc = Bun.spawnSync(cmd, { cwd, stdout: "pipe", stderr: "pipe" });
  return {
    code: proc.exitCode ?? 1,
    output: proc.stdout.toString() + proc.stderr.toString(),
  };
}

/** Build the throwaway repo for one case and return its path. */
function setUpTempRepo(c: ActCase): string {
  const dir = mkdtempSync(join(tmpdir(), "svb-act-"));
  for (const f of PROJECT_FILES) {
    cpSync(join(ROOT, f), join(dir, f), { recursive: true });
  }
  writeFileSync(join(dir, "VERSION"), `${c.startVersion}\n`);
  cpSync(join(ROOT, "fixtures", c.fixture), join(dir, "commits.log"));

  // act wants a real git repo with a commit for the push event.
  const git = ["git", "-c", "user.name=ci", "-c", "user.email=ci@example.com"];
  for (const args of [
    ["init", "--initial-branch=main", "--quiet"],
    ["add", "-A"],
    ["commit", "--quiet", "-m", "test: act harness fixture commit"],
  ]) {
    const { code, output } = sh([...git, ...args], dir);
    if (code !== 0) throw new Error(`git ${args[0]} failed in ${dir}:\n${output}`);
  }
  return dir;
}

interface CaseResult {
  name: string;
  failures: string[];
}

function runCase(c: ActCase, index: number): CaseResult {
  console.log(`\n=== Case ${index + 1}/${CASES.length}: ${c.name} ===`);
  const dir = setUpTempRepo(c);
  const failures: string[] = [];
  try {
    const { code, output } = sh(
      ["act", "push", "--rm", "--pull=false", "-P", "ubuntu-latest=act-ubuntu-pwsh:latest"],
      dir,
    );

    // Persist the full act output before asserting anything.
    appendFileSync(
      RESULT_FILE,
      [
        `${"=".repeat(78)}`,
        `TEST CASE ${index + 1}: ${c.name}`,
        `fixture=${c.fixture} startVersion=${c.startVersion}`,
        `expected: BUMP=${c.expectedBump} NEW_VERSION=${c.expectedNewVersion}`,
        `act exit code: ${code}`,
        `${"=".repeat(78)}`,
        output,
        "",
      ].join("\n"),
    );

    const expect = (cond: boolean, msg: string): void => {
      if (!cond) failures.push(msg);
    };

    expect(code === 0, `act exited with code ${code}, expected 0`);
    expect(
      output.includes(`OLD_VERSION=${c.startVersion}`),
      `missing exact "OLD_VERSION=${c.startVersion}"`,
    );
    expect(output.includes(`BUMP=${c.expectedBump}`), `missing exact "BUMP=${c.expectedBump}"`);
    expect(
      output.includes(`NEW_VERSION=${c.expectedNewVersion}`),
      `missing exact "NEW_VERSION=${c.expectedNewVersion}"`,
    );
    // Step-output round trip: proves steps.bump.outputs.NEW_VERSION wiring.
    expect(
      output.includes(`RESULT_NEW_VERSION=${c.expectedNewVersion}`),
      `missing exact "RESULT_NEW_VERSION=${c.expectedNewVersion}"`,
    );
    // Every job must report success.
    for (const job of JOB_NAMES) {
      expect(
        new RegExp(`${job}\\].*Job succeeded`).test(output),
        `job "${job}" did not report "Job succeeded"`,
      );
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }

  console.log(
    failures.length === 0
      ? "PASS"
      : `FAIL:\n${failures.map((f) => `  - ${f}`).join("\n")}`,
  );
  return { name: c.name, failures };
}

// Start a fresh result file for this harness run.
writeFileSync(RESULT_FILE, `act test harness results\n`);

const results = CASES.map(runCase);
const failed = results.filter((r) => r.failures.length > 0);

console.log(`\n${"=".repeat(40)}`);
console.log(`act harness: ${results.length - failed.length}/${results.length} cases passed`);
if (failed.length > 0) {
  for (const f of failed) console.log(`FAILED: ${f.name}`);
  process.exit(1);
}
