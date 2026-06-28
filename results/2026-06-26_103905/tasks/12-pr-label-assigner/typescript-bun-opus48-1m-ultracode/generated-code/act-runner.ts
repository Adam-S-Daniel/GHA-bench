#!/usr/bin/env bun
// End-to-end test harness: runs the PR-label-assigner *through the real GitHub
// Actions workflow* using `act` (nektos/act). This is the only place the
// pipeline is exercised; the unit suites (`bun test`) cover the logic.
//
// For each fixture case it:
//   1. builds a throwaway git repo containing the project + that case's
//      changed-files.txt,
//   2. runs `act push --rm` against it,
//   3. appends the full, delimited act output to ./act-result.txt,
//   4. asserts act exited 0, that BOTH jobs report "Job succeeded", and that the
//      parsed RESULT_LABELS / RESULT_COUNT exactly match the case's expected.json.
//
// Usage:
//   bun run act-runner.ts                # run every fixture case
//   bun run act-runner.ts case-multi     # run a single case (cheap smoke test)
//
// Budget note: each case is one `act push` run. Running a single case first is a
// safe way to validate the pipeline without spending the whole act-run budget.

import {
  cpSync,
  existsSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
  appendFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const ROOT = import.meta.dir;
const FIXTURES_DIR = join(ROOT, "fixtures");
const RESULT_FILE = join(ROOT, "act-result.txt");
const ACT_IMAGE = "act-ubuntu-pwsh:latest";
const ACT_TIMEOUT_MS = 600_000;

// Project files/dirs that must be present in the throwaway repo for the
// workflow to run (everything `actions/checkout` would normally provide).
const PROJECT_PATHS = [
  "cli.ts",
  "src",
  "tests",
  "package.json",
  "tsconfig.json",
  "labeler.config.json",
  ".github",
  ".actrc",
];

interface ExpectedResult {
  labels: string;
  count: number;
}

interface CaseOutcome {
  name: string;
  passed: boolean;
  failures: string[];
}

/** Strip ANSI CSI color/control sequences so output can be parsed reliably. */
function stripAnsi(text: string): string {
  // Anchored on the ESC byte so it never mangles act's "[job-name]" prefixes.
  // eslint-disable-next-line no-control-regex
  return text.replace(/\u001b\[[0-9;]*[A-Za-z]/g, "");
}

/** Extract the value following `marker=` from a line that contains it. */
function extractMarker(output: string, marker: string): string | null {
  for (const rawLine of stripAnsi(output).split(/\r?\n/)) {
    const idx = rawLine.indexOf(`${marker}=`);
    if (idx !== -1) {
      return rawLine.slice(idx + marker.length + 1).trimEnd();
    }
  }
  return null;
}

/** Run a shell-less command synchronously, returning code + combined output. */
function run(cmd: string[], cwd: string): { code: number; output: string } {
  const proc = Bun.spawnSync(cmd, { cwd, stdout: "pipe", stderr: "pipe" });
  return {
    code: proc.exitCode,
    output: proc.stdout.toString() + proc.stderr.toString(),
  };
}

/** Discover available fixture case names (subdirs of fixtures/). */
function discoverCases(): string[] {
  if (!existsSync(FIXTURES_DIR)) return [];
  return readdirSync(FIXTURES_DIR, { withFileTypes: true })
    .filter((d) => d.isDirectory())
    .map((d) => d.name)
    .sort();
}

/** Build a throwaway git repo for `caseName` and return its path. */
function buildCaseRepo(caseName: string): string {
  const repo = mkdtempSync(join(tmpdir(), `act-${caseName}-`));

  // Copy the project into the temp repo.
  for (const rel of PROJECT_PATHS) {
    const src = join(ROOT, rel);
    if (existsSync(src)) {
      cpSync(src, join(repo, rel), { recursive: true });
    }
  }

  // Overlay this case's fixture as the repo's changed-files.txt (the mock PR).
  const fixtureFiles = join(FIXTURES_DIR, caseName, "changed-files.txt");
  cpSync(fixtureFiles, join(repo, "changed-files.txt"));

  // act needs a real git repo with a commit on a branch to simulate `push`.
  const gitSetup = [
    ["git", "init", "-q", "-b", "main"],
    ["git", "config", "user.email", "act-harness@example.com"],
    ["git", "config", "user.name", "act-harness"],
    ["git", "add", "-A"],
    ["git", "commit", "-q", "-m", `fixture: ${caseName}`],
  ];
  for (const cmd of gitSetup) {
    const { code, output } = run(cmd, repo);
    if (code !== 0) {
      throw new Error(`git setup failed (${cmd.join(" ")}): ${output}`);
    }
  }
  return repo;
}

/** Read and validate a case's expected.json. */
function loadExpected(caseName: string): ExpectedResult {
  const path = join(FIXTURES_DIR, caseName, "expected.json");
  const parsed = JSON.parse(readFileSync(path, "utf8")) as ExpectedResult;
  if (typeof parsed.labels !== "string" || typeof parsed.count !== "number") {
    throw new Error(`expected.json for ${caseName} must have string "labels" and number "count"`);
  }
  return parsed;
}

/** Run one case end-to-end through act and assert on the output. */
function runCase(caseName: string): CaseOutcome {
  const failures: string[] = [];
  const expected = loadExpected(caseName);
  const repo = buildCaseRepo(caseName);

  console.log(`\n=== act case: ${caseName} (repo: ${repo}) ===`);
  let actOutput = "";
  let actCode = -1;
  try {
    const proc = Bun.spawnSync(
      ["act", "push", "--rm", "--pull=false", "-P", `ubuntu-latest=${ACT_IMAGE}`],
      { cwd: repo, stdout: "pipe", stderr: "pipe", timeout: ACT_TIMEOUT_MS },
    );
    actCode = proc.exitCode;
    actOutput = proc.stdout.toString() + proc.stderr.toString();
  } finally {
    // Always persist the raw output, clearly delimited, even on failure.
    const header =
      `\n${"=".repeat(78)}\n` +
      `TEST CASE: ${caseName}\n` +
      `EXPECTED: labels="${expected.labels}" count=${expected.count}\n` +
      `${"=".repeat(78)}\n`;
    appendFileSync(RESULT_FILE, header + actOutput + `\n[act exit code: ${actCode}]\n`);
    // Clean up the throwaway repo.
    rmSync(repo, { recursive: true, force: true });
  }

  // --- Assertion 1: act exited 0 ---
  if (actCode !== 0) {
    failures.push(`act exited with code ${actCode} (expected 0)`);
  }

  // --- Assertion 2: every job reported success ---
  const clean = stripAnsi(actOutput);
  const succeeded = (clean.match(/Job succeeded/g) ?? []).length;
  if (succeeded < 2) {
    failures.push(`expected 2 "Job succeeded" markers (test + assign-labels), found ${succeeded}`);
  }
  if (/Job failed/.test(clean)) {
    failures.push(`output contains "Job failed"`);
  }

  // --- Assertion 3: exact RESULT_LABELS ---
  const labels = extractMarker(actOutput, "RESULT_LABELS");
  if (labels === null) {
    failures.push("RESULT_LABELS marker not found in act output");
  } else if (labels !== expected.labels) {
    failures.push(`RESULT_LABELS mismatch:\n   expected: "${expected.labels}"\n   actual:   "${labels}"`);
  }

  // --- Assertion 4: exact RESULT_COUNT ---
  const count = extractMarker(actOutput, "RESULT_COUNT");
  if (count === null) {
    failures.push("RESULT_COUNT marker not found in act output");
  } else if (count !== String(expected.count)) {
    failures.push(`RESULT_COUNT mismatch: expected "${expected.count}", actual "${count}"`);
  }

  const passed = failures.length === 0;
  if (passed) {
    console.log(`PASS ${caseName}: labels="${labels}" count=${count} (${succeeded} jobs succeeded)`);
  } else {
    console.log(`FAIL ${caseName}:\n - ${failures.join("\n - ")}`);
  }
  return { name: caseName, passed, failures };
}

function main(): number {
  const requested = process.argv.slice(2);
  const all = discoverCases();
  if (all.length === 0) {
    console.error(`No fixture cases found under ${FIXTURES_DIR}`);
    return 1;
  }
  const cases = requested.length > 0 ? requested : all;
  for (const c of cases) {
    if (!all.includes(c)) {
      console.error(`Unknown case "${c}". Available: ${all.join(", ")}`);
      return 1;
    }
  }

  // Fresh result file for this harness invocation.
  writeFileSync(
    RESULT_FILE,
    `PR Label Assigner - act integration results\n` +
      `Cases: ${cases.join(", ")}\n` +
      `Runner image: ${ACT_IMAGE}\n`,
  );

  const outcomes = cases.map(runCase);

  console.log(`\n${"#".repeat(60)}\nSUMMARY`);
  for (const o of outcomes) {
    console.log(`  ${o.passed ? "PASS" : "FAIL"}  ${o.name}`);
  }
  const failed = outcomes.filter((o) => !o.passed);
  console.log(`${outcomes.length - failed.length}/${outcomes.length} cases passed`);
  console.log(`Full act output saved to: ${RESULT_FILE}`);
  return failed.length === 0 ? 0 : 1;
}

process.exit(main());
