// ACT TEST HARNESS
// ----------------
// Every test case is executed END-TO-END through the GitHub Actions workflow
// using `act` (nektos/act). For each case we:
//   1. build an isolated temp git repo containing the project + the case's
//      fixture data (a package.json version + a commits.txt commit log),
//   2. run `act push --rm`, capturing all output,
//   3. append that output to ./act-result.txt (clearly delimited),
//   4. assert act exited 0, that BOTH jobs report "Job succeeded", and that
//      the workflow produced the EXACT expected NEW_VERSION / BUMP values.
//
// Run with:  bun run act-harness.ts
import {
  mkdtempSync,
  rmSync,
  writeFileSync,
  readFileSync,
  appendFileSync,
  cpSync,
  existsSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const PROJECT_ROOT = import.meta.dir;
const RESULT_FILE = join(PROJECT_ROOT, "act-result.txt");

interface TestCase {
  name: string;
  startVersion: string;
  commits: string;
  expectedVersion: string;
  expectedBump: string;
}

// Each case maps a known input to its known-good output (asserted exactly).
const CASES: TestCase[] = [
  {
    name: "feat -> minor (1.1.0 => 1.2.0)",
    startVersion: "1.1.0",
    commits: "feat(api): add pagination\nfix: small bug\nchore: noise\n",
    expectedVersion: "1.2.0",
    expectedBump: "minor",
  },
  {
    name: "breaking -> major (2.4.1 => 3.0.0)",
    startVersion: "2.4.1",
    commits: "feat!: overhaul config format\nfix: tidy logs\n",
    expectedVersion: "3.0.0",
    expectedBump: "major",
  },
  {
    name: "fix -> patch (1.0.0 => 1.0.1)",
    startVersion: "1.0.0",
    commits: "fix(parser): correct off-by-one\nchore: reformat\n",
    expectedVersion: "1.0.1",
    expectedBump: "patch",
  },
  {
    name: "no release (2.0.0 unchanged)",
    startVersion: "2.0.0",
    commits: "chore: update CI\ndocs: typo\n",
    expectedVersion: "2.0.0",
    expectedBump: "none",
  },
];

// Project files needed inside the isolated repo (node_modules/.git excluded).
const COPY_ITEMS = [
  "src",
  "tests",
  "fixtures",
  ".github",
  ".actrc",
  "package.json",
  "bun.lock",
  "tsconfig.json",
];

interface RunResult {
  code: number;
  output: string;
}

/** Build an isolated repo for a case and run the workflow through act. */
function runCase(tc: TestCase): RunResult {
  const dir = mkdtempSync(join(tmpdir(), "svb-act-"));
  try {
    // Copy the project into the isolated repo.
    for (const item of COPY_ITEMS) {
      const src = join(PROJECT_ROOT, item);
      if (existsSync(src)) cpSync(src, join(dir, item), { recursive: true });
    }

    // Inject this case's fixture data.
    const pkg = JSON.parse(readFileSync(join(dir, "package.json"), "utf8"));
    pkg.version = tc.startVersion;
    writeFileSync(join(dir, "package.json"), JSON.stringify(pkg, null, 2) + "\n");
    writeFileSync(join(dir, "commits.txt"), tc.commits);

    // act needs a committed git tree for actions/checkout.
    sh(dir, ["git", "init", "-q"]);
    sh(dir, ["git", "config", "user.email", "ci@example.com"]);
    sh(dir, ["git", "config", "user.name", "ci"]);
    sh(dir, ["git", "add", "-A"]);
    sh(dir, ["git", "commit", "-q", "-m", "fixture"]);

    // Run the full workflow (both jobs) through act.
    const proc = Bun.spawnSync(["act", "push", "--rm"], {
      cwd: dir,
      stdout: "pipe",
      stderr: "pipe",
    });
    const output =
      new TextDecoder().decode(proc.stdout) + new TextDecoder().decode(proc.stderr);
    return { code: proc.exitCode ?? -1, output };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

/** Run a helper command, throwing on failure. */
function sh(cwd: string, cmd: string[]): void {
  const p = Bun.spawnSync(cmd, { cwd, stdout: "pipe", stderr: "pipe" });
  if ((p.exitCode ?? -1) !== 0) {
    throw new Error(
      `Command failed: ${cmd.join(" ")}\n${new TextDecoder().decode(p.stderr)}`,
    );
  }
}

// ----- assertions ----------------------------------------------------------

let failures = 0;
function check(cond: boolean, message: string): void {
  if (cond) {
    console.log(`  PASS: ${message}`);
  } else {
    failures++;
    console.log(`  FAIL: ${message}`);
  }
}

// Fresh result file each run.
writeFileSync(RESULT_FILE, `# act-result.txt — generated ${new Date().toISOString()}\n`);

for (const tc of CASES) {
  console.log(`\n=== Case: ${tc.name} ===`);
  const { code, output } = runCase(tc);

  // Persist the raw act output, clearly delimited.
  appendFileSync(
    RESULT_FILE,
    `\n${"=".repeat(78)}\nCASE: ${tc.name}\n` +
      `INPUT: version=${tc.startVersion} expectedVersion=${tc.expectedVersion} expectedBump=${tc.expectedBump}\n` +
      `ACT EXIT CODE: ${code}\n${"-".repeat(78)}\n${output}\n`,
  );

  // Exact-value assertions against the known-good result for this input.
  check(code === 0, "act exited 0");
  check(output.includes(`NEW_VERSION=${tc.expectedVersion}`), `output contains NEW_VERSION=${tc.expectedVersion}`);
  check(output.includes(`BUMP=${tc.expectedBump}`), `output contains BUMP=${tc.expectedBump}`);
  check(
    output.includes(`RESULT_NEW_VERSION=${tc.expectedVersion}`),
    `downstream job echoes RESULT_NEW_VERSION=${tc.expectedVersion}`,
  );

  // Both jobs (bump + report) must succeed.
  const succeeded = (output.match(/Job succeeded/g) ?? []).length;
  check(succeeded >= 2, `both jobs report "Job succeeded" (found ${succeeded})`);
}

console.log(`\nact output written to ${RESULT_FILE}`);
if (failures > 0) {
  console.error(`\n${failures} assertion(s) FAILED.`);
  process.exit(1);
}
console.log("\nAll act test cases passed.");
