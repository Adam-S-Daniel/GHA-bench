// End-to-end pipeline harness: every test case is executed through the real
// GitHub Actions workflow via `act` (nektos/act), never by calling the
// script directly.
//
// For each case we:
//   1. build a temp git repo containing the project files + that case's
//      input fixtures (input/rules.json, input/changed-files.json),
//   2. run `act push --rm` in it,
//   3. append the full act output to act-result.txt (clearly delimited),
//   4. assert: act exit code 0, the EXACT expected "FINAL LABELS: ..." line,
//      a clean in-container unit-test run, and both jobs reporting
//      "Job succeeded".
//
// Run with:  bun run scripts/run-act-tests.ts
import { cpSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";

const ROOT = join(import.meta.dir, "..");
const RESULT_FILE = join(ROOT, "act-result.txt");

// Files that make up the deployable project (the harness itself is excluded —
// the pipeline must not recurse into running act inside act).
const PROJECT_FILES = [
  ".actrc",
  ".github/workflows/pr-label-assigner.yml",
  "package.json",
  "tsconfig.json",
  "src/glob.ts",
  "src/glob.test.ts",
  "src/labeler.ts",
  "src/labeler.test.ts",
  "src/cli.ts",
  "src/cli.test.ts",
  "src/workflow.test.ts",
  "fixtures/rules.json",
  "fixtures/changed-files.json",
  "input/rules.json",
  "input/changed-files.json",
];

interface ActCase {
  name: string;
  /** Per-case overrides written into the temp repo (path -> content). */
  files: Record<string, string>;
  /** The exact final-label line the workflow must print. */
  expectedLine: string;
}

const CASES: ActCase[] = [
  {
    // Uses the committed default inputs untouched: exercises docs/**,
    // priority suppression (docs/api/** beats docs/**), multi-label rules
    // (src/api/** -> api+backend), basename matching (*.test.*) and a
    // no-match file (README.md).
    name: "default-inputs",
    files: {},
    expectedLine: "FINAL LABELS: api,api-docs,backend,documentation,tests",
  },
  {
    // Custom inputs: priority ties are additive (src/** + src/legacy/** both
    // at priority 1), a higher priority suppresses (src/api/** at 5 hides
    // "source" for API files), basename *.md matches at depth, and LICENSE
    // matches nothing.
    name: "priority-conflicts",
    files: {
      "input/rules.json": JSON.stringify(
        {
          rules: [
            { pattern: "src/**", labels: ["source"], priority: 1 },
            { pattern: "src/legacy/**", labels: ["legacy"], priority: 1 },
            { pattern: "src/api/**", labels: ["api"], priority: 5 },
            { pattern: "*.md", labels: ["markdown"] },
          ],
        },
        null,
        2,
      ),
      "input/changed-files.json": JSON.stringify(
        ["src/legacy/old.ts", "src/api/v1/users.ts", "notes/todo.md", "LICENSE"],
        null,
        2,
      ),
    },
    expectedLine: "FINAL LABELS: api,legacy,markdown,source",
  },
];

let failures = 0;

function check(condition: boolean, label: string, detail = ""): void {
  if (condition) {
    console.log(`  PASS  ${label}`);
  } else {
    failures += 1;
    console.error(`  FAIL  ${label}${detail ? `\n        ${detail}` : ""}`);
  }
}

function run(cmd: string[], cwd: string, timeoutMs = 60_000): { exitCode: number; output: string } {
  const proc = Bun.spawnSync(cmd, { cwd, timeout: timeoutMs, env: process.env });
  return {
    exitCode: proc.exitCode ?? -1,
    output: proc.stdout.toString() + proc.stderr.toString(),
  };
}

/** Materialize one test case as a standalone git repo and run act in it. */
function runCase(testCase: ActCase): void {
  console.log(`\n=== act case: ${testCase.name} ===`);
  const repo = mkdtempSync(join(tmpdir(), `labeler-act-${testCase.name}-`));

  try {
    for (const file of PROJECT_FILES) {
      const dest = join(repo, file);
      mkdirSync(dirname(dest), { recursive: true });
      cpSync(join(ROOT, file), dest);
    }
    for (const [path, content] of Object.entries(testCase.files)) {
      const dest = join(repo, path);
      mkdirSync(dirname(dest), { recursive: true });
      writeFileSync(dest, content);
    }

    // act needs a real git repo with a commit to synthesize the push event.
    for (const gitCmd of [
      ["git", "init", "-q", "-b", "main"],
      ["git", "config", "user.email", "harness@example.com"],
      ["git", "config", "user.name", "Act Harness"],
      ["git", "add", "-A"],
      ["git", "commit", "-q", "-m", `act case ${testCase.name}`],
    ]) {
      const result = run(gitCmd, repo);
      if (result.exitCode !== 0) {
        throw new Error(`git setup failed (${gitCmd.join(" ")}): ${result.output}`);
      }
    }

    console.log("  running: act push --rm (this takes a while)...");
    const act = run(
      // --pull=false: the runner image exists only locally; act's default
      // force-pull fails against the registry with an auth error.
      ["act", "push", "--rm", "--pull=false", "-W", ".github/workflows/pr-label-assigner.yml"],
      repo,
      10 * 60_000,
    );

    // Requirement: append every case's full act output to act-result.txt.
    const delimiter = `\n${"=".repeat(78)}\n== ACT CASE: ${testCase.name} (exit code ${act.exitCode})\n${"=".repeat(78)}\n`;
    appendResult(delimiter + act.output);

    check(act.exitCode === 0, `act exited 0 (got ${act.exitCode})`);
    check(
      act.output.includes(testCase.expectedLine),
      `output contains exact "${testCase.expectedLine}"`,
    );
    check(
      / 0 fail/.test(act.output),
      "in-container bun test reported 0 failures",
    );
    const succeeded = (act.output.match(/Job succeeded/g) ?? []).length;
    check(succeeded === 2, `both jobs report "Job succeeded" (got ${succeeded})`);
  } finally {
    rmSync(repo, { recursive: true, force: true });
  }
}

let resultBuffer = "";
function appendResult(chunk: string): void {
  resultBuffer += chunk;
}

console.log("PR Label Assigner — end-to-end pipeline tests via act");

// Pre-flight (cheap, instant): actionlint must pass before we spend act runs.
const lint = run(["actionlint", ".github/workflows/pr-label-assigner.yml"], ROOT);
check(lint.exitCode === 0, "actionlint passes on the workflow", lint.output);

if (failures === 0) {
  for (const testCase of CASES) runCase(testCase);
} else {
  console.error("Skipping act runs because actionlint failed.");
}

await Bun.write(RESULT_FILE, resultBuffer || "(no act output captured)\n");
console.log(`\nact output written to ${RESULT_FILE}`);

if (failures > 0) {
  console.error(`\n${failures} assertion(s) FAILED`);
  process.exit(1);
}
console.log("\nAll pipeline assertions passed.");
