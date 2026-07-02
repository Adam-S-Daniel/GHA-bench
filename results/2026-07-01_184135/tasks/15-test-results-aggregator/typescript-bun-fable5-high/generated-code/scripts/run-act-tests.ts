/**
 * End-to-end pipeline test harness: runs every test case THROUGH the GitHub
 * Actions workflow via `act` (nektos/act), never by invoking the aggregator
 * directly.
 *
 * For each case it:
 *   1. Creates a temp git repo containing the project files plus that case's
 *      fixture files copied to `results/` (what a matrix build would produce),
 *   2. Runs `act push --rm` and captures all output,
 *   3. Appends the output to ./act-result.txt (clearly delimited),
 *   4. Asserts: act exited 0, both jobs report "Job succeeded", no job
 *      failed, and the logs contain the EXACT expected values for that
 *      case's input (AGGREGATE_RESULT counters, flaky test names, markdown
 *      rows, and the bun test tally).
 *
 * Run with:  bun run scripts/run-act-tests.ts
 */
import { cp, mkdir, mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

const ROOT = join(import.meta.dir, "..");
const ACT_RESULT_FILE = join(process.cwd(), "act-result.txt");

/** Files/dirs that make up the project inside each temp repo. */
const PROJECT_FILES = [
  "package.json",
  "tsconfig.json",
  ".actrc",
  "src",
  "tests",
  "fixtures",
  ".github",
] as const;

interface ActCase {
  name: string;
  /** Fixture directory (relative to repo root) copied to `results/`. */
  fixtureDir: string;
  /** Every string must appear verbatim in the act output. */
  expectExact: string[];
}

// Known-good expected values, hand-computed from the fixture files.
const CASES: ActCase[] = [
  {
    name: "case1-mixed-matrix-with-flaky-test",
    fixtureDir: "fixtures/case1",
    expectExact: [
      // 10 tests: 6 passed, 2 failed, 2 skipped; 4.9s total; 1 flaky.
      "AGGREGATE_RESULT total=10 passed=6 failed=2 skipped=2 duration=4.90s flaky=1",
      "FLAKY_TEST auth > test_flaky_network",
      "| ✅ Passed | 6 |",
      "| **Total** | **10** |",
      "| `auth > test_flaky_network` | junit-shard-macos.xml | junit-shard-ubuntu.xml |",
      "| `api > test_delete` | json-shard-windows.json | 500 from server |",
      "**Total duration:** 4.90s across 3 runs",
      // The unit-test job must run the whole suite green inside the container.
      "41 pass",
      "0 fail",
    ],
  },
  {
    name: "case2-all-green-matrix",
    fixtureDir: "fixtures/case2",
    expectExact: [
      "AGGREGATE_RESULT total=5 passed=5 failed=0 skipped=0 duration=1.50s flaky=0",
      "✅ All 5 tests passed.",
      "No flaky tests detected.",
      "**Total duration:** 1.50s across 2 runs",
      "41 pass",
      "0 fail",
    ],
  },
];

function sh(cmd: string[], cwd: string): { exitCode: number; output: string } {
  const proc = Bun.spawnSync(cmd, { cwd, stdout: "pipe", stderr: "pipe" });
  return {
    exitCode: proc.exitCode,
    output: proc.stdout.toString() + proc.stderr.toString(),
  };
}

/** Fail loudly with context; the harness is a test, so any assert kills it. */
function assert(condition: boolean, message: string): void {
  if (!condition) {
    console.error(`\n❌ ASSERTION FAILED: ${message}`);
    process.exit(1);
  }
}

async function setupTempRepo(testCase: ActCase): Promise<string> {
  const dir = await mkdtemp(join(tmpdir(), `aggregator-act-${testCase.name}-`));
  for (const entry of PROJECT_FILES) {
    await cp(join(ROOT, entry), join(dir, entry), { recursive: true });
  }
  // The case's fixture files become the `results/` dir a matrix build would produce.
  await mkdir(join(dir, "results"), { recursive: true });
  await cp(join(ROOT, testCase.fixtureDir), join(dir, "results"), { recursive: true });

  for (const cmd of [
    ["git", "init", "-b", "main"],
    ["git", "config", "user.email", "harness@example.com"],
    ["git", "config", "user.name", "Act Harness"],
    ["git", "add", "-A"],
    ["git", "commit", "-m", `act harness: ${testCase.name}`],
  ]) {
    const { exitCode, output } = sh(cmd, dir);
    assert(exitCode === 0, `git setup failed (${cmd.join(" ")}): ${output}`);
  }
  return dir;
}

async function main(): Promise<void> {
  await Bun.write(ACT_RESULT_FILE, ""); // start fresh each harness run
  let combined = "";

  for (const testCase of CASES) {
    console.log(`\n=== Running ${testCase.name} through act ===`);
    const repo = await setupTempRepo(testCase);

    const { exitCode, output } = sh(["act", "push", "--rm", "--pull=false"], repo);

    combined +=
      `\n${"=".repeat(78)}\n` +
      `=== ACT TEST CASE: ${testCase.name} (fixtures: ${testCase.fixtureDir}) ===\n` +
      `=== act exit code: ${exitCode} ===\n` +
      `${"=".repeat(78)}\n` +
      output;
    await Bun.write(ACT_RESULT_FILE, combined);

    await rm(repo, { recursive: true, force: true });

    // 1. act itself must succeed.
    assert(exitCode === 0, `${testCase.name}: act exited with ${exitCode} (see act-result.txt)`);

    // 2. Both jobs (unit-tests, aggregate) must report success, none may fail.
    const succeeded = (output.match(/Job succeeded/g) ?? []).length;
    assert(succeeded >= 2, `${testCase.name}: expected 2 "Job succeeded" markers, saw ${succeeded}`);
    assert(!output.includes("Job failed"), `${testCase.name}: a job reported "Job failed"`);

    // 3. Exact expected values for this case's fixture input.
    for (const expected of testCase.expectExact) {
      assert(
        output.includes(expected),
        `${testCase.name}: output is missing exact expected string:\n  ${expected}`,
      );
    }
    console.log(`✅ ${testCase.name} passed (${succeeded} jobs succeeded)`);
  }

  console.log(`\nAll ${CASES.length} act test cases passed. Full logs: ${ACT_RESULT_FILE}`);
}

main().catch((err: unknown) => {
  console.error(`harness error: ${err instanceof Error ? (err.stack ?? err.message) : String(err)}`);
  process.exit(1);
});
