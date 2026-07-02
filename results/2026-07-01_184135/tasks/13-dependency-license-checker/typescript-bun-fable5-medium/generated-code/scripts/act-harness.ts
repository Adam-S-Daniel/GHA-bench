/**
 * End-to-end test harness: runs every test case THROUGH the GitHub Actions
 * workflow via `act` (nektos/act), never by invoking the script directly.
 *
 * For each case it:
 *   1. builds a temp git repo containing the project plus ONLY that case's
 *      manifest fixture under fixtures/manifests/,
 *   2. runs `act push --rm` inside it,
 *   3. appends the full act output to act-result.txt (clearly delimited),
 *   4. asserts act exited 0, that every job reports "Job succeeded", and
 *      that the report contains the EXACT expected lines for that input.
 *
 * Run with: bun run scripts/act-harness.ts
 */
import { cpSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const resultFile = join(root, "act-result.txt");

/** One act-driven test case: a manifest fixture and its exact expected report. */
interface ActCase {
  id: string;
  /** File name (under fixtures/manifests/) this case exercises. */
  manifest: string;
  /** Exact report lines the workflow must print for this input. */
  expectedLines: string[];
  /** Number of workflow jobs that must report "Job succeeded". */
  expectedJobSuccesses: number;
}

const CASES: ActCase[] = [
  {
    id: "npm-package-json",
    manifest: "package.json",
    expectedLines: [
      "=== Checking fixtures/manifests/package.json ===",
      "APPROVED left-pad@^1.3.0 MIT",
      "DENIED evil-lib@2.0.0 GPL-3.0-only",
      "UNKNOWN mystery-pkg@0.1.0 (license not found)",
      "APPROVED typescript@~5.4.0 Apache-2.0",
      "Summary: total=4 approved=2 denied=1 unknown=1",
    ],
    expectedJobSuccesses: 2, // test job + compliance job
  },
  {
    id: "python-requirements-txt",
    manifest: "requirements.txt",
    expectedLines: [
      "=== Checking fixtures/manifests/requirements.txt ===",
      "APPROVED requests@2.31.0 Apache-2.0",
      "DENIED copyleft-pkg@1.0.0 AGPL-3.0-only",
      "APPROVED flask@>=2.0 BSD-3-Clause",
      "APPROVED pyyaml@6.0.1 MIT",
      "UNKNOWN unknown-thing@9.9.9 (license not found)",
      "Summary: total=5 approved=3 denied=1 unknown=1",
    ],
    expectedJobSuccesses: 2,
  },
];

/** Files/dirs copied into each temp repo (fixtures/manifests is rebuilt per case). */
const PROJECT_ITEMS: string[] = [
  "package.json",
  "bun.lock",
  "tsconfig.json",
  ".actrc",
  ".github",
  "src",
  "tests",
  "fixtures",
];

interface RunResult {
  exitCode: number;
  output: string;
}

/** Run a command, merging stdout+stderr, without throwing on failure. */
async function run(cmd: string[], cwd: string): Promise<RunResult> {
  const proc = Bun.spawn(cmd, { cwd, stdout: "pipe", stderr: "pipe" });
  const [out, err, exitCode] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
    proc.exited,
  ]);
  return { exitCode, output: out + err };
}

let failures = 0;
function assert(condition: boolean, label: string): void {
  if (condition) {
    console.log(`  PASS ${label}`);
  } else {
    failures++;
    console.error(`  FAIL ${label}`);
  }
}

/** Build the per-case temp repo and commit it so `act push` has an event. */
async function setupTempRepo(testCase: ActCase): Promise<string> {
  const dir = mkdtempSync(join(tmpdir(), `license-checker-${testCase.id}-`));
  for (const item of PROJECT_ITEMS) {
    cpSync(join(root, item), join(dir, item), { recursive: true });
  }
  // Replace the manifests dir with ONLY this case's fixture.
  rmSync(join(dir, "fixtures", "manifests"), { recursive: true });
  cpSync(
    join(root, "fixtures", "manifests", testCase.manifest),
    join(dir, "fixtures", "manifests", testCase.manifest),
  );
  const gitCommands: string[][] = [
    ["git", "init", "--quiet", "--initial-branch=main"],
    ["git", "config", "user.email", "harness@example.com"],
    ["git", "config", "user.name", "Act Harness"],
    ["git", "add", "-A"],
    ["git", "commit", "--quiet", "-m", `fixture: ${testCase.id}`],
  ];
  for (const cmd of gitCommands) {
    const result = await run(cmd, dir);
    if (result.exitCode !== 0) {
      throw new Error(`Setup failed (${cmd.join(" ")}): ${result.output}`);
    }
  }
  return dir;
}

// Fresh result file per harness run; each case's output is appended below.
await Bun.write(resultFile, "");

for (const testCase of CASES) {
  console.log(`\n=== act case: ${testCase.id} ===`);
  const dir = await setupTempRepo(testCase);
  try {
    const act = await run(["act", "push", "--rm", "--pull=false"], dir);

    const delimiter = `\n${"=".repeat(70)}\n=== ACT CASE: ${testCase.id} (manifest: ${testCase.manifest}) ===\n=== act exit code: ${act.exitCode} ===\n${"=".repeat(70)}\n`;
    const existing = await Bun.file(resultFile).text();
    await Bun.write(resultFile, existing + delimiter + act.output + "\n");

    assert(act.exitCode === 0, "act exited with code 0");
    const successes = act.output.match(/Job succeeded/g)?.length ?? 0;
    assert(
      successes >= testCase.expectedJobSuccesses,
      `all ${testCase.expectedJobSuccesses} jobs report "Job succeeded" (saw ${successes})`,
    );
    for (const line of testCase.expectedLines) {
      assert(act.output.includes(line), `output contains exact line: "${line}"`);
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

console.log(
  `\n${failures === 0 ? "ALL ACT ASSERTIONS PASSED" : `${failures} ASSERTION(S) FAILED`}`,
);
console.log(`Full act output saved to ${resultFile}`);
process.exit(failures === 0 ? 0 : 1);
