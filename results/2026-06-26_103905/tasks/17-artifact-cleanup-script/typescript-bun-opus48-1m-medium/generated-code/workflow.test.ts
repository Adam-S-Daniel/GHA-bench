/**
 * Workflow validation tests.
 *
 * Two layers:
 *  1. Structure tests — parse/inspect the workflow YAML, confirm it references
 *     real script paths, and confirm actionlint passes (all instant).
 *  2. Act execution tests — for each fixture "test case", build a temp git repo,
 *     run the workflow end-to-end in Docker via `act push`, and assert on EXACT
 *     expected output values. All act output is appended to act-result.txt.
 */

import { describe, it, expect } from "bun:test";
import {
  mkdtempSync,
  copyFileSync,
  mkdirSync,
  writeFileSync,
  appendFileSync,
  existsSync,
  readFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

const PROJECT_DIR = import.meta.dir;
const WORKFLOW_PATH = join(
  PROJECT_DIR,
  ".github/workflows/artifact-cleanup-script.yml",
);
const ACT_RESULT = join(PROJECT_DIR, "act-result.txt");

// ---------------------------------------------------------------------------
// Structure tests
// ---------------------------------------------------------------------------

describe("workflow structure", () => {
  const yaml = readFileSync(WORKFLOW_PATH, "utf8");

  it("declares the expected trigger events", () => {
    expect(yaml).toMatch(/^on:/m);
    expect(yaml).toMatch(/^\s+push:/m);
    expect(yaml).toMatch(/^\s+pull_request:/m);
    expect(yaml).toMatch(/^\s+schedule:/m);
    expect(yaml).toMatch(/^\s+workflow_dispatch:/m);
  });

  it("declares least-privilege permissions", () => {
    expect(yaml).toMatch(/permissions:\s*\n\s+contents:\s*read/);
  });

  it("defines a test job and a dependent cleanup-plan job", () => {
    expect(yaml).toMatch(/^\s+test:/m);
    expect(yaml).toMatch(/^\s+cleanup-plan:/m);
    // cleanup-plan depends on test (job dependency).
    expect(yaml).toMatch(/needs:\s*test/);
  });

  it("uses pinned, valid action references", () => {
    expect(yaml).toContain("actions/checkout@v4");
    expect(yaml).toContain("oven-sh/setup-bun@v2");
  });

  it("references script files that actually exist on disk", () => {
    // The workflow runs cleanup.ts and tests cleanup.test.ts.
    expect(yaml).toContain("cleanup.ts");
    expect(yaml).toContain("cleanup.test.ts");
    expect(existsSync(join(PROJECT_DIR, "cleanup.ts"))).toBe(true);
    expect(existsSync(join(PROJECT_DIR, "cleanup.test.ts"))).toBe(true);
    expect(existsSync(join(PROJECT_DIR, "fixtures/active.json"))).toBe(true);
  });

  it("passes actionlint cleanly", () => {
    const res = spawnSync("actionlint", [WORKFLOW_PATH], { encoding: "utf8" });
    if (res.status !== 0) {
      console.error(res.stdout, res.stderr);
    }
    expect(res.status).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// Act execution tests — every test case runs through the real workflow.
// ---------------------------------------------------------------------------

interface ActCase {
  name: string;
  fixture: string; // fixture file (copied into the temp repo as fixtures/active.json)
  expected: {
    mode: "DRY-RUN" | "EXECUTE";
    deleted: number;
    retained: number;
    reclaimed: number;
    retainedBytes: number;
  };
}

const CASES: ActCase[] = [
  {
    name: "max-age + dry-run",
    fixture: "fixtures/max-age-dryrun.json",
    expected: {
      mode: "DRY-RUN",
      deleted: 2,
      retained: 1,
      reclaimed: 2500,
      retainedBytes: 2000,
    },
  },
  {
    name: "max-total-size + execute",
    fixture: "fixtures/max-size-execute.json",
    expected: {
      mode: "EXECUTE",
      deleted: 2,
      retained: 1,
      reclaimed: 3000,
      retainedBytes: 3000,
    },
  },
];

/** Build an isolated git repo containing the project + the case's fixture. */
function setupRepo(fixture: string): string {
  const dir = mkdtempSync(join(tmpdir(), "artifact-cleanup-act-"));
  for (const f of ["cleanup.ts", "cleanup.test.ts", "package.json", ".actrc"]) {
    copyFileSync(join(PROJECT_DIR, f), join(dir, f));
  }
  mkdirSync(join(dir, ".github/workflows"), { recursive: true });
  copyFileSync(
    WORKFLOW_PATH,
    join(dir, ".github/workflows/artifact-cleanup-script.yml"),
  );
  mkdirSync(join(dir, "fixtures"), { recursive: true });
  // The workflow always evaluates fixtures/active.json; copy the case onto it.
  copyFileSync(join(PROJECT_DIR, fixture), join(dir, "fixtures/active.json"));

  const git = (args: string[]) =>
    spawnSync("git", args, { cwd: dir, encoding: "utf8" });
  git(["init", "-q"]);
  git(["config", "user.email", "test@example.com"]);
  git(["config", "user.name", "Test"]);
  git(["add", "-A"]);
  git(["commit", "-q", "-m", "test fixture"]);
  return dir;
}

/** Extract `KEY=value` regardless of act's per-line job/step prefixes. */
function grabNumber(output: string, key: string): number | null {
  const m = output.match(new RegExp(`${key}=(-?\\d+)`));
  return m ? Number(m[1]) : null;
}

/** Run one case through act and return its captured output + exit status. */
function runActCase(c: ActCase): { output: string; status: number | null } {
  const dir = setupRepo(c.fixture);
  // --pull=false: use the locally-provisioned runner image instead of forcing
  // a registry pull (the benchmark image is local-only).
  const res = spawnSync("act", ["push", "--rm", "--pull=false"], {
    cwd: dir,
    encoding: "utf8",
    env: process.env,
    maxBuffer: 50 * 1024 * 1024,
  });
  const output = `${res.stdout ?? ""}\n${res.stderr ?? ""}`;
  appendFileSync(
    ACT_RESULT,
    `\n\n===== CASE: ${c.name} (fixture=${c.fixture}) =====\n` +
      `exit code: ${res.status}\n` +
      `${"-".repeat(60)}\n${output}\n`,
  );
  return { output, status: res.status };
}

// All cases run inside ONE test so the act invocations are strictly sequential —
// two `act push` runs must never overlap or they race on Docker containers.
describe("workflow execution via act", () => {
  it(
    "runs every fixture case through act with exact expected output",
    () => {
      // Start a fresh act-result.txt for this run.
      writeFileSync(
        ACT_RESULT,
        `Artifact cleanup workflow — act run log\n${"=".repeat(60)}\n`,
      );

      for (const c of CASES) {
        const { output, status } = runActCase(c);

        // 1. act exited cleanly.
        expect(status, `act exit code for case "${c.name}"`).toBe(0);

        // 2. every job succeeded (test + cleanup-plan).
        const succeeded = output.match(/Job succeeded/g) ?? [];
        expect(
          succeeded.length,
          `Job succeeded count for case "${c.name}"`,
        ).toBeGreaterThanOrEqual(2);

        // 3. exact expected output values from the cleanup plan.
        expect(output).toContain(`MODE=${c.expected.mode}`);
        expect(grabNumber(output, "DELETED_COUNT")).toBe(c.expected.deleted);
        expect(grabNumber(output, "RETAINED_COUNT")).toBe(c.expected.retained);
        expect(grabNumber(output, "BYTES_RECLAIMED")).toBe(c.expected.reclaimed);
        expect(grabNumber(output, "BYTES_RETAINED")).toBe(
          c.expected.retainedBytes,
        );
      }

      // 4. the required artifact exists.
      expect(existsSync(ACT_RESULT)).toBe(true);
    },
    600_000, // two sequential act runs need well beyond the default 5s timeout.
  );
});
