#!/usr/bin/env bun
/**
 * Act-based integration harness for the PR Label Assigner workflow.
 *
 * Per the task spec, EVERY integration test case is executed through the real
 * GitHub Actions workflow via `act` (nektos/act) rather than by calling the
 * script directly. For each case this harness:
 *
 *   1. Builds a throwaway git repo containing the project + that case's
 *      changed-files fixture (written to examples/changed-files.json, the path
 *      the workflow reads by default).
 *   2. Runs `act push --rm` against the workflow inside that repo.
 *   3. Appends the full act output to ./act-result.txt, clearly delimited.
 *   4. Asserts: act exited 0, both jobs report "Job succeeded", the workflow
 *      emitted the EXACT expected label set (via the __PR_LABELS__= marker the
 *      CLI prints), and the GITHUB_OUTPUT-derived label count matches.
 *
 * Run with:  bun run tests/act-harness.ts
 * Exits non-zero if any case fails.
 */
import {
  cpSync,
  mkdtempSync,
  writeFileSync,
  appendFileSync,
  rmSync,
  existsSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const PROJECT_ROOT = join(import.meta.dir, "..");
const ACT_RESULT = join(PROJECT_ROOT, "act-result.txt");
const WORKFLOW_REL = ".github/workflows/pr-label-assigner.yml";
const ACT_IMAGE = "act-ubuntu-pwsh:latest";

// Files/dirs copied into each throwaway repo. node_modules is intentionally
// omitted — the script has zero runtime dependencies and the workflow installs
// Bun itself.
const COPY_ITEMS = [
  "src",
  "tests",
  "examples",
  ".github",
  "package.json",
  "tsconfig.json",
  ".actrc",
];

interface TestCase {
  /** Short, filesystem-safe identifier. */
  name: string;
  /** Human description of what the case exercises. */
  description: string;
  /** The mock PR's changed file paths. */
  changedFiles: string[];
  /** EXACT expected machine-readable label list (priority order, comma-sep). */
  expectedLabels: string;
  /** EXACT expected label count (round-tripped through GITHUB_OUTPUT). */
  expectedCount: number;
}

// The cases are evaluated against the default examples/labeler.config.json:
//   documentation: docs/**, *.md         (priority 1)
//   api:           src/api/**            (priority 10)
//   tests:         *.test.*, **/*.spec.ts (priority 5)
//   ci:            .github/**            (priority 8)
//   frontend:      src/web/**, *.css, *.html (priority 3)
const CASES: TestCase[] = [
  {
    name: "multi-label-priority",
    description:
      "A file can yield multiple labels; the union is emitted in priority order.",
    changedFiles: [
      "docs/getting-started.md", // documentation (p1)
      "src/api/users.ts", // api (p10)
      "src/api/users.test.ts", // api (p10) + tests (p5)
      "src/web/app.tsx", // frontend (p3)
    ],
    // priority desc: api(10), tests(5), frontend(3), documentation(1)
    expectedLabels: "api,tests,frontend,documentation",
    expectedCount: 4,
  },
  {
    name: "docs-and-ci",
    description:
      "Directory and basename globs both fire; ci(8) outranks documentation(1).",
    changedFiles: [
      "docs/intro.md", // documentation (docs/**)
      "README.md", // documentation (*.md) — deduped, no double label
      ".github/workflows/deploy.yml", // ci (.github/**)
    ],
    expectedLabels: "ci,documentation",
    expectedCount: 2,
  },
  {
    name: "no-matches",
    description: "When nothing matches, the label set is empty (not an error).",
    changedFiles: ["LICENSE", "Makefile", "src/core/engine.ts"],
    expectedLabels: "",
    expectedCount: 0,
  },
];

/** Strip ANSI escape sequences so we can match plain text in act's output. */
function stripAnsi(s: string): string {
  // eslint-disable-next-line no-control-regex
  return s.replace(/\x1b\[[0-9;]*[A-Za-z]/g, "");
}

/** Run a command synchronously, throwing with context on failure. */
function run(cmd: string[], cwd: string): void {
  const proc = Bun.spawnSync(cmd, { cwd, stdout: "pipe", stderr: "pipe" });
  if (proc.exitCode !== 0) {
    throw new Error(
      `command failed (${proc.exitCode}): ${cmd.join(" ")}\n` +
        proc.stderr.toString(),
    );
  }
}

/** Create a throwaway git repo for one test case and return its path. */
function setupRepo(testCase: TestCase): string {
  const dir = mkdtempSync(join(tmpdir(), `act-pr-label-${testCase.name}-`));

  for (const item of COPY_ITEMS) {
    const src = join(PROJECT_ROOT, item);
    if (existsSync(src)) cpSync(src, join(dir, item), { recursive: true });
  }

  // Inject this case's changed-files fixture into the path the workflow reads.
  writeFileSync(
    join(dir, "examples", "changed-files.json"),
    JSON.stringify(testCase.changedFiles, null, 2) + "\n",
  );

  // act derives event context from git; use a branch the workflow listens on.
  run(["git", "init", "-q", "-b", "main"], dir);
  run(["git", "config", "user.email", "ci@example.com"], dir);
  run(["git", "config", "user.name", "CI"], dir);
  run(["git", "add", "-A"], dir);
  run(["git", "commit", "-q", "-m", `fixture: ${testCase.name}`], dir);

  return dir;
}

/** Run the workflow under act for the given repo; return exit code + output. */
function runAct(dir: string): { exitCode: number; output: string } {
  const proc = Bun.spawnSync(
    [
      "act",
      "push",
      "--rm",
      "--pull=false", // the custom image is local-only; never attempt a registry pull
      "-P",
      `ubuntu-latest=${ACT_IMAGE}`,
      "-W",
      WORKFLOW_REL,
    ],
    { cwd: dir, stdout: "pipe", stderr: "pipe" },
  );
  const output = stripAnsi(proc.stdout.toString() + "\n" + proc.stderr.toString());
  return { exitCode: proc.exitCode ?? -1, output };
}

/**
 * Return the text after `marker` on the first line that contains it (with
 * surrounding whitespace trimmed), or null if no line contains the marker.
 */
function valueAfter(output: string, marker: string): string | null {
  for (const line of output.split(/\r?\n/)) {
    const idx = line.indexOf(marker);
    if (idx !== -1) return line.slice(idx + marker.length).trim();
  }
  return null;
}

interface CaseResult {
  name: string;
  passed: boolean;
  failures: string[];
}

/** Evaluate all assertions for one completed act run. */
function assertCase(
  testCase: TestCase,
  exitCode: number,
  output: string,
): CaseResult {
  const failures: string[] = [];

  if (exitCode !== 0) {
    failures.push(`act exited with code ${exitCode} (expected 0)`);
  }

  // EXACT expected label set, via the CLI's machine-readable marker line.
  const labels = valueAfter(output, "__PR_LABELS__=");
  if (labels === null) {
    failures.push("no __PR_LABELS__= marker found in act output");
  } else if (labels !== testCase.expectedLabels) {
    failures.push(
      `labels mismatch: got "${labels}", expected "${testCase.expectedLabels}"`,
    );
  }

  // EXACT label count, round-tripped through GITHUB_OUTPUT -> step output.
  const count = valueAfter(output, "Label count:");
  if (count === null) {
    failures.push("no 'Label count:' line found (GITHUB_OUTPUT round-trip)");
  } else if (count !== String(testCase.expectedCount)) {
    failures.push(
      `count mismatch: got "${count}", expected "${testCase.expectedCount}"`,
    );
  }

  // Both jobs (test + assign-labels) must report success.
  const succeeded = (output.match(/Job succeeded/g) ?? []).length;
  if (succeeded < 2) {
    failures.push(
      `expected 2 "Job succeeded" (one per job), found ${succeeded}`,
    );
  }
  if (/Job failed/.test(output)) {
    failures.push('output contains "Job failed"');
  }

  return { name: testCase.name, passed: failures.length === 0, failures };
}

/** Append a clearly delimited record of one case to act-result.txt. */
function recordResult(
  testCase: TestCase,
  exitCode: number,
  output: string,
  result: CaseResult,
): void {
  const banner = "=".repeat(78);
  const verdict = result.passed ? "PASS" : "FAIL";
  let block = `\n${banner}\n`;
  block += `TEST CASE: ${testCase.name}  [${verdict}]\n`;
  block += `DESCRIPTION: ${testCase.description}\n`;
  block += `CHANGED FILES: ${JSON.stringify(testCase.changedFiles)}\n`;
  block += `EXPECTED LABELS: "${testCase.expectedLabels}" (count ${testCase.expectedCount})\n`;
  block += `ACT EXIT CODE: ${exitCode}\n`;
  if (result.failures.length > 0) {
    block += `FAILURES:\n  - ${result.failures.join("\n  - ")}\n`;
  }
  block += `${banner}\n`;
  block += `----- BEGIN ACT OUTPUT (${testCase.name}) -----\n`;
  block += output.trimEnd() + "\n";
  block += `----- END ACT OUTPUT (${testCase.name}) -----\n`;
  appendFileSync(ACT_RESULT, block);
}

async function main(): Promise<number> {
  // Start a fresh act-result.txt for this run.
  const header =
    `PR Label Assigner — act integration results\n` +
    `Workflow: ${WORKFLOW_REL}\n` +
    `Image: ${ACT_IMAGE}\n` +
    `Cases: ${CASES.length}\n`;
  writeFileSync(ACT_RESULT, header);

  const results: CaseResult[] = [];

  for (const testCase of CASES) {
    console.log(`\n>>> Running act for case: ${testCase.name}`);
    const dir = setupRepo(testCase);
    try {
      const { exitCode, output } = runAct(dir);
      const result = assertCase(testCase, exitCode, output);
      recordResult(testCase, exitCode, output, result);
      results.push(result);
      console.log(
        `    ${result.passed ? "PASS" : "FAIL"} — ${testCase.name}` +
          (result.passed ? "" : `\n      ${result.failures.join("\n      ")}`),
      );
    } finally {
      // Throwaway repo; the act output is already saved to act-result.txt.
      try {
        rmSync(dir, { recursive: true, force: true });
      } catch {
        /* best effort */
      }
    }
  }

  const passed = results.filter((r) => r.passed).length;
  const summary =
    `\n${"#".repeat(78)}\n` +
    `SUMMARY: ${passed}/${results.length} cases passed\n` +
    results
      .map((r) => `  ${r.passed ? "PASS" : "FAIL"}  ${r.name}`)
      .join("\n") +
    `\n${"#".repeat(78)}\n`;
  appendFileSync(ACT_RESULT, summary);
  console.log(summary);

  return passed === results.length ? 0 : 1;
}

main().then((code) => process.exit(code));
