/**
 * Runs the pr-label-assigner GitHub Actions workflow through `act` for each
 * of three test-case scenarios (one `workflow_dispatch` fixture input per
 * scenario), each in an isolated temp git repo. Asserts exact expected label
 * output and writes all raw act output to act-result.txt.
 *
 * This is the required end-to-end validation: every test case here executes
 * through the real workflow via `act`, not by calling the script directly.
 */
import { execFileSync } from "node:child_process";
import { cpSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const PROJECT_ROOT = join(import.meta.dir, "..");
const RESULT_FILE = join(PROJECT_ROOT, "act-result.txt");

interface TestCase {
  name: string;
  fixture: string;
  expectedLabels: string[];
}

const TEST_CASES: TestCase[] = [
  {
    name: "docs-only",
    fixture: "fixtures/case-docs-only.json",
    expectedLabels: ["documentation"],
  },
  {
    name: "mixed-changes",
    fixture: "fixtures/case-mixed.json",
    expectedLabels: ["api", "ci", "database", "documentation"],
  },
  {
    name: "no-match",
    fixture: "fixtures/case-no-match.json",
    expectedLabels: [],
  },
];

const FILES_TO_COPY = [
  "src",
  "fixtures",
  ".github",
  "package.json",
  "bun.lock",
  "tsconfig.json",
  "rules.json",
  ".actrc",
];

function setUpTempRepo(testCase: TestCase): string {
  const dir = mkdtempSync(join(tmpdir(), `pr-label-assigner-${testCase.name}-`));

  for (const entry of FILES_TO_COPY) {
    cpSync(join(PROJECT_ROOT, entry), join(dir, entry), { recursive: true });
  }

  writeFileSync(
    join(dir, "event.json"),
    JSON.stringify({ inputs: { fixture: testCase.fixture } }),
  );

  // act requires a real git repo (it reads the current ref/SHA for event context).
  execFileSync("git", ["init", "-q"], { cwd: dir });
  execFileSync("git", ["add", "-A"], { cwd: dir });
  execFileSync(
    "git",
    ["-c", "user.name=act", "-c", "user.email=act@example.com", "commit", "-q", "-m", "init"],
    { cwd: dir },
  );

  return dir;
}

function runAct(dir: string): { exitCode: number; output: string } {
  try {
    const output = execFileSync(
      "act",
      ["workflow_dispatch", "-e", "event.json", "--rm", "--pull=false"],
      { cwd: dir, encoding: "utf-8", maxBuffer: 1024 * 1024 * 50 },
    );
    return { exitCode: 0, output };
  } catch (error) {
    const err = error as { status?: number; stdout?: string; stderr?: string };
    const output = `${err.stdout ?? ""}\n${err.stderr ?? ""}`;
    return { exitCode: err.status ?? 1, output };
  }
}

function assert(condition: boolean, message: string): void {
  if (!condition) {
    throw new Error(`ASSERTION FAILED: ${message}`);
  }
}

function main(): void {
  writeFileSync(RESULT_FILE, "");
  let failures = 0;

  for (const testCase of TEST_CASES) {
    console.log(`\n=== Running act test case: ${testCase.name} ===`);
    const dir = setUpTempRepo(testCase);
    const { exitCode, output } = runAct(dir);

    const delimiter = `\n${"=".repeat(20)} TEST CASE: ${testCase.name} (exit ${exitCode}) ${"=".repeat(20)}\n`;
    writeFileSync(RESULT_FILE, delimiter + output + "\n", { flag: "a" });

    try {
      assert(exitCode === 0, `act exited with code ${exitCode} for case "${testCase.name}"`);
      assert(
        output.includes("Job succeeded"),
        `expected "Job succeeded" in output for case "${testCase.name}"`,
      );
      const expectedLine = `LABELS=${JSON.stringify(testCase.expectedLabels)}`;
      assert(
        output.includes(expectedLine),
        `expected output to contain "${expectedLine}" for case "${testCase.name}"`,
      );
      console.log(`PASS: ${testCase.name}`);
    } catch (error) {
      failures++;
      console.error(`FAIL: ${testCase.name}: ${(error as Error).message}`);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  }

  if (failures > 0) {
    console.error(`\n${failures} test case(s) failed. See ${RESULT_FILE} for full act output.`);
    process.exit(1);
  }

  console.log(`\nAll test cases passed. Full act output written to ${RESULT_FILE}.`);
}

main();
