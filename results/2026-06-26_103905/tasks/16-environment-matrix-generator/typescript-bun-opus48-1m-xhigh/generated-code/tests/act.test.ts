import { beforeAll, describe, expect, test } from "bun:test";
import {
  cpSync,
  copyFileSync,
  mkdirSync,
  mkdtempSync,
  rmSync,
  writeFileSync,
  appendFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

// ---------------------------------------------------------------------------
// Act integration harness.
//
// EVERY assertion here runs the real GitHub Actions workflow through `act`
// (nektos/act) — the script is never invoked directly. For each fixture we:
//   1. build a throwaway git repo containing the project + that fixture as the
//      workflow's `matrix-config.json`,
//   2. run `act push --rm`, capturing all output,
//   3. append the output to ../act-result.txt (delimited per case),
//   4. assert act exited 0, the pipeline printed the EXACT expected values for
//      that fixture, and every job reported "Job succeeded".
//
// This suite is slow (Docker) and therefore opt-in: set RUN_ACT=1 to run it.
// A plain `bun test` skips it so the fast unit/structure tests stay quick.
//   RUN_ACT=1 bun test tests/act.test.ts
// ---------------------------------------------------------------------------
const RUN_ACT = process.env.RUN_ACT === "1";

const ROOT = join(import.meta.dir, "..");
const ACT_RESULT = join(ROOT, "act-result.txt");

/** Strip ANSI colour/escape codes so output is easy to grep and parse. */
function stripAnsi(s: string): string {
  // eslint-disable-next-line no-control-regex
  return s.replace(/\[[0-9;]*m/g, "").replace(/\[[0-9;]*[A-Za-z]/g, "");
}

/** Count non-overlapping occurrences of `needle` in `haystack`. */
function countOccurrences(haystack: string, needle: string): number {
  let count = 0;
  let idx = haystack.indexOf(needle);
  while (idx !== -1) {
    count++;
    idx = haystack.indexOf(needle, idx + needle.length);
  }
  return count;
}

/** Pull the value of a `MARKER=...` line out of the (ANSI-stripped) output. */
function markerValue(output: string, marker: string): string | undefined {
  for (const line of output.split("\n")) {
    const idx = line.indexOf(`${marker}=`);
    if (idx !== -1) {
      return line.slice(idx + marker.length + 1).trim();
    }
  }
  return undefined;
}

interface ActCase {
  name: string;
  fixture: string;
  expected: {
    count: number;
    maxParallel: string;
    failFast: string;
    include: unknown[];
    /** generate-matrix (1) + build (count) + summary (1). */
    jobs: number;
  };
}

// Expected values are the known-good results computed from each fixture. The
// harness asserts EXACT values, not merely that "some output appeared".
const CASES: ActCase[] = [
  {
    name: "basic",
    fixture: "fixtures/basic.json",
    expected: {
      count: 4,
      maxParallel: "2",
      failFast: "true",
      include: [
        { os: "ubuntu-latest", node: "18" },
        { os: "ubuntu-latest", node: "20" },
        { os: "windows-latest", node: "18" },
        { os: "windows-latest", node: "20" },
      ],
      jobs: 6,
    },
  },
  {
    name: "include-exclude",
    fixture: "fixtures/include-exclude.json",
    expected: {
      count: 4,
      maxParallel: "2",
      failFast: "false",
      include: [
        { os: "ubuntu-latest", node: "18" },
        { os: "ubuntu-latest", node: "20" },
        { os: "windows-latest", node: "20" },
        { os: "macos-latest", node: "20", experimental: true },
      ],
      jobs: 6,
    },
  },
  {
    name: "feature-flags",
    fixture: "fixtures/feature-flags.json",
    expected: {
      count: 2,
      maxParallel: "1",
      failFast: "true",
      include: [
        { os: "ubuntu-latest", node: 20, feature: "off" },
        { os: "ubuntu-latest", node: 20, feature: "on", experimental: true },
      ],
      jobs: 4,
    },
  },
];

/** Build a throwaway git repo containing the project + the chosen fixture. */
function setupRepo(fixture: string): string {
  const dir = mkdtempSync(join(tmpdir(), "act-matrix-"));

  // Copy the pieces the workflow needs at runtime.
  cpSync(join(ROOT, "src"), join(dir, "src"), { recursive: true });
  cpSync(join(ROOT, ".github"), join(dir, ".github"), { recursive: true });
  // The workflow's "Run unit tests" step runs these two pure-logic files only.
  mkdirSync(join(dir, "tests"), { recursive: true });
  copyFileSync(join(ROOT, "tests", "matrix.test.ts"), join(dir, "tests", "matrix.test.ts"));
  copyFileSync(join(ROOT, "tests", "cli.test.ts"), join(dir, "tests", "cli.test.ts"));
  copyFileSync(join(ROOT, "package.json"), join(dir, "package.json"));
  copyFileSync(join(ROOT, "tsconfig.json"), join(dir, "tsconfig.json"));

  // The fixture becomes the config file the workflow reads.
  copyFileSync(join(ROOT, fixture), join(dir, "matrix-config.json"));

  // Pin act to the known-good local image that has curl + unzip (for Bun).
  writeFileSync(join(dir, ".actrc"), "-P ubuntu-latest=act-ubuntu-pwsh:latest\n");

  // Commit so actions/checkout has content to check out.
  const git = (args: string[]) =>
    Bun.spawnSync(["git", "-C", dir, ...args], {
      env: { ...process.env, GIT_TERMINAL_PROMPT: "0" },
    });
  git(["init", "-q", "-b", "main"]);
  git(["config", "user.email", "harness@example.com"]);
  git(["config", "user.name", "Act Harness"]);
  git(["config", "commit.gpgsign", "false"]);
  git(["add", "-A"]);
  git(["commit", "-q", "-m", "fixture"]);

  return dir;
}

/** Run `act push --rm` in the repo and return combined, de-ANSI'd output. */
function runAct(dir: string): { output: string; exitCode: number } {
  const proc = Bun.spawnSync(
    ["act", "push", "--rm", "--pull=false", "-W", ".github/workflows/environment-matrix-generator.yml"],
    {
      cwd: dir,
      env: { ...process.env },
      timeout: 600_000,
    },
  );
  const raw = proc.stdout.toString() + "\n" + proc.stderr.toString();
  return { output: stripAnsi(raw), exitCode: proc.exitCode ?? -1 };
}

// Results collected by the (slow) act runs, asserted on by the fast tests.
const results = new Map<string, { output: string; exitCode: number }>();

const suite = RUN_ACT ? describe : describe.skip;

suite("act integration (RUN_ACT=1)", () => {
  beforeAll(() => {
    // Fresh artifact each run.
    writeFileSync(
      ACT_RESULT,
      `# act-result.txt — output of running the workflow through nektos/act\n` +
        `# Generated by tests/act.test.ts\n`,
    );

    let broken = false;
    for (const c of CASES) {
      if (broken) break; // Fail-fast: don't burn act runs after a failure.

      const dir = setupRepo(c.fixture);
      try {
        const result = runAct(dir);
        results.set(c.name, result);

        // Persist this case's output, clearly delimited.
        appendFileSync(
          ACT_RESULT,
          `\n${"=".repeat(78)}\n` +
            `TEST CASE: ${c.name}  (fixture: ${c.fixture})\n` +
            `act exit code: ${result.exitCode}\n` +
            `${"=".repeat(78)}\n` +
            result.output +
            `\n`,
        );

        if (result.exitCode !== 0) broken = true;
      } finally {
        rmSync(dir, { recursive: true, force: true });
      }
    }
  }, 1_800_000); // up to 30 min for all act runs combined.

  for (const c of CASES) {
    describe(`fixture: ${c.name}`, () => {
      test("act exited 0", () => {
        const r = results.get(c.name);
        expect(r, `no act result captured for ${c.name}`).toBeDefined();
        expect(r!.exitCode).toBe(0);
      });

      test("pipeline printed the exact combination count", () => {
        const r = results.get(c.name)!;
        expect(markerValue(r.output, "MATRIX_COUNT")).toBe(String(c.expected.count));
      });

      test("pipeline printed the exact max-parallel and fail-fast", () => {
        const r = results.get(c.name)!;
        expect(markerValue(r.output, "MATRIX_MAX_PARALLEL")).toBe(c.expected.maxParallel);
        expect(markerValue(r.output, "MATRIX_FAIL_FAST")).toBe(c.expected.failFast);
      });

      test("pipeline emitted the exact generated matrix (include list)", () => {
        const r = results.get(c.name)!;
        const raw = markerValue(r.output, "MATRIX_INCLUDE_JSON");
        expect(raw, "MATRIX_INCLUDE_JSON marker missing").toBeDefined();
        const parsed = JSON.parse(raw!);
        expect(parsed).toEqual({ include: c.expected.include });
      });

      test("the summary job confirmed the pipeline ran end to end", () => {
        const r = results.get(c.name)!;
        expect(r.output).toContain("MATRIX_PIPELINE_OK=true");
      });

      test("every job reported Job succeeded and none failed", () => {
        const r = results.get(c.name)!;
        expect(r.output).not.toContain("Job failed");
        const succeeded = countOccurrences(r.output, "Job succeeded");
        expect(succeeded).toBeGreaterThanOrEqual(c.expected.jobs);
      });
    });
  }
});
