/**
 * End-to-end test harness: runs every fixture test case through the real
 * GitHub Actions workflow using `act` (nektos/act).
 *
 * For each case it:
 *   1. builds a temp git repo containing the project plus ONLY that case's
 *      fixture in fixtures/cases/,
 *   2. runs `act push --rm` against it,
 *   3. appends the full act output to act-result.txt (delimited per case),
 *   4. asserts act exited 0, that the output contains the EXACT expected
 *      result line for the case's input, and that every job (unit-tests,
 *      generate-matrix, 2x consume-matrix) reports "Job succeeded".
 *
 * Usage:
 *   bun run scripts/act-harness.ts <case-name>   # run one case (appends)
 *   bun run scripts/act-harness.ts --reset       # truncate act-result.txt
 */
import { spawnSync } from "bun";
import { appendFileSync, cpSync, mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const ROOT = join(import.meta.dir, "..");
const RESULT_FILE = join(ROOT, "act-result.txt");

/** One end-to-end test case: a fixture plus its exact expected output. */
interface ActCase {
  name: string;
  /** Fixture file (relative to ROOT) placed as the only case in fixtures/cases/. */
  fixture: string;
  /** Exact substrings that MUST appear in the act output. */
  expect: string[];
}

// The single pipeline matrix (fixtures/pipeline.json) is generated in every
// run, so every case asserts its exact value and the exact matrix-job echoes.
const PIPELINE_EXPECTATIONS: string[] = [
  'PIPELINE_MATRIX {"include":[{"os":"ubuntu-latest","language-version":"18","cache":"bun"},' +
    '{"os":"ubuntu-latest","language-version":"20","cache":"bun"}]}',
  "MATRIX_JOB os=ubuntu-latest version=18 cache=bun",
  "MATRIX_JOB os=ubuntu-latest version=20 cache=bun",
];

const CASES: ActCase[] = [
  {
    name: "ok-basic",
    fixture: "fixtures/cases/ok-basic.json",
    // 2 OS x 2 versions x 1 flag = 4 jobs, fail-fast off, max-parallel 2.
    expect: [
      'CASE_OUTPUT ok-basic EXIT=0 {"strategy":{"fail-fast":false,"max-parallel":2,"matrix":' +
        '{"include":[{"os":"ubuntu-latest","language-version":"18","feature":"telemetry"},' +
        '{"os":"ubuntu-latest","language-version":"20","feature":"telemetry"},' +
        '{"os":"macos-latest","language-version":"18","feature":"telemetry"},' +
        '{"os":"macos-latest","language-version":"20","feature":"telemetry"}]}},"jobCount":4}',
      ...PIPELINE_EXPECTATIONS,
    ],
  },
  {
    name: "ok-include-exclude",
    fixture: "fixtures/cases/ok-include-exclude.json",
    // macos+18 excluded (3 jobs remain); ubuntu combos gain experimental=true.
    expect: [
      'CASE_OUTPUT ok-include-exclude EXIT=0 {"strategy":{"fail-fast":true,"matrix":' +
        '{"include":[{"os":"ubuntu-latest","language-version":"18","experimental":"true"},' +
        '{"os":"ubuntu-latest","language-version":"20","experimental":"true"},' +
        '{"os":"macos-latest","language-version":"20"}]}},"jobCount":3}',
      ...PIPELINE_EXPECTATIONS,
    ],
  },
  {
    name: "fail-oversized",
    fixture: "fixtures/cases/fail-oversized.json",
    // 3 OS x 4 versions = 12 > maxSize 10 -> the CLI must fail with this message.
    expect: [
      "CASE_OUTPUT fail-oversized EXIT=1 Validation error: Matrix size 12 exceeds the " +
        "maximum allowed size 10. Reduce dimensions or add exclude rules.",
      ...PIPELINE_EXPECTATIONS,
    ],
  },
];

/** Jobs per run: unit-tests + generate-matrix + 2 consume-matrix combinations. */
const EXPECTED_JOB_SUCCESSES = 4;

/** Files copied from the project into each temp repo. */
const PROJECT_FILES = [
  ".github",
  ".actrc",
  "src",
  "tests",
  "scripts",
  "fixtures",
  "package.json",
  "bun.lock",
  "tsconfig.json",
  "node_modules", // pre-installed deps keep `bun install` offline-safe in CI
];

function sh(cwd: string, cmd: string[]): void {
  const proc = spawnSync(cmd, { cwd, stdout: "pipe", stderr: "pipe" });
  if (proc.exitCode !== 0) {
    throw new Error(`Command failed (${cmd.join(" ")}): ${proc.stderr.toString()}`);
  }
}

/** Build a disposable git repo holding the project + exactly one fixture case. */
function buildTempRepo(testCase: ActCase): string {
  const repo = mkdtempSync(join(tmpdir(), `matrix-act-${testCase.name}-`));
  for (const file of PROJECT_FILES) {
    cpSync(join(ROOT, file), join(repo, file), { recursive: true });
  }
  // Replace the cases dir with ONLY this case's fixture.
  rmSync(join(repo, "fixtures/cases"), { recursive: true });
  mkdirSync(join(repo, "fixtures/cases"));
  cpSync(join(ROOT, testCase.fixture), join(repo, "fixtures/cases", `${testCase.name}.json`));

  sh(repo, ["git", "init", "-b", "main"]);
  sh(repo, ["git", "config", "user.email", "harness@example.com"]);
  sh(repo, ["git", "config", "user.name", "Act Harness"]);
  sh(repo, ["git", "add", "-A"]);
  sh(repo, ["git", "commit", "-m", `act harness case ${testCase.name}`]);
  return repo;
}

function runCase(testCase: ActCase): boolean {
  console.log(`\n=== Running act case: ${testCase.name} ===`);
  const repo = buildTempRepo(testCase);

  const proc = spawnSync(["act", "push", "--rm", "--pull=false"], {
    cwd: repo,
    stdout: "pipe",
    stderr: "pipe",
  });
  const output = proc.stdout.toString() + proc.stderr.toString();
  const exitCode = proc.exitCode ?? -1;

  // Assertions -------------------------------------------------------------
  const failures: string[] = [];
  if (exitCode !== 0) failures.push(`act exited with code ${exitCode}, expected 0`);

  for (const expected of testCase.expect) {
    if (!output.includes(expected)) {
      failures.push(`missing exact expected output: ${expected}`);
    }
  }

  const successCount = output.split("Job succeeded").length - 1;
  if (successCount !== EXPECTED_JOB_SUCCESSES) {
    failures.push(`expected ${EXPECTED_JOB_SUCCESSES} "Job succeeded" jobs, saw ${successCount}`);
  }
  if (output.includes("Job failed")) failures.push('output contains "Job failed"');

  // Record the full act output + verdicts, clearly delimited per case.
  const verdicts =
    failures.length === 0
      ? `ALL ASSERTIONS PASSED (${testCase.expect.length} exact-output checks, ` +
        `exit code 0, ${EXPECTED_JOB_SUCCESSES}x "Job succeeded")`
      : failures.map((f) => `ASSERTION FAILED: ${f}`).join("\n");
  appendFileSync(
    RESULT_FILE,
    `\n${"=".repeat(72)}\n=== ACT CASE: ${testCase.name} (exit code ${exitCode}) ===\n` +
      `${"=".repeat(72)}\n${output}\n---- HARNESS ASSERTIONS (${testCase.name}) ----\n${verdicts}\n`,
  );

  if (failures.length === 0) {
    rmSync(repo, { recursive: true, force: true });
    console.log(`PASS ${testCase.name}`);
    return true;
  }
  console.error(`FAIL ${testCase.name} (repo kept at ${repo}):\n  ${failures.join("\n  ")}`);
  return false;
}

const arg = process.argv[2];
if (arg === "--reset") {
  writeFileSync(RESULT_FILE, `act harness results — ${new Date().toISOString()}\n`);
  console.log(`Truncated ${RESULT_FILE}`);
  process.exit(0);
}

const selected = CASES.filter((c) => !arg || c.name === arg);
if (selected.length === 0) {
  console.error(`Unknown case "${arg}". Known: ${CASES.map((c) => c.name).join(", ")}`);
  process.exit(1);
}
const allPassed = selected.map(runCase).every(Boolean);
process.exit(allPassed ? 0 : 1);
