// Workflow tests: static structure checks + a real end-to-end run of the
// GitHub Actions workflow through `act` (nektos/act) in Docker.
//
// Per the task requirements, every functional test case is exercised THROUGH
// the pipeline: each case sets up a throwaway git repo with the project files
// plus that case's fixture, runs `act push --rm`, and asserts on the EXACT
// values the workflow prints. All act output is appended to act-result.txt.

import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import {
  appendFileSync,
  cpSync,
  existsSync,
  mkdtempSync,
  mkdirSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const PROJECT_ROOT = join(import.meta.dir, "..");
const WORKFLOW = join(
  PROJECT_ROOT,
  ".github",
  "workflows",
  "secret-rotation-validator.yml",
);
const ACT_RESULT = join(PROJECT_ROOT, "act-result.txt");

// ---------------------------------------------------------------------------
// Static structure tests (fast, no Docker required)
// ---------------------------------------------------------------------------

describe("workflow structure", () => {
  const raw = Bun.file(WORKFLOW); // existence asserted below
  // Parse once for all structural assertions.
  let doc: any;

  beforeAll(async () => {
    expect(await raw.exists()).toBe(true);
    doc = Bun.YAML.parse(await raw.text());
  });

  test("declares the expected trigger events", () => {
    const on = doc.on;
    expect(on).toHaveProperty("push");
    expect(on).toHaveProperty("pull_request");
    expect(on).toHaveProperty("schedule");
    expect(on).toHaveProperty("workflow_dispatch");
  });

  test("uses least-privilege permissions", () => {
    expect(doc.permissions).toEqual({ contents: "read" });
  });

  test("defines validate + notify jobs with a dependency between them", () => {
    expect(Object.keys(doc.jobs)).toEqual(
      expect.arrayContaining(["validate", "notify"]),
    );
    expect(doc.jobs.notify.needs).toBe("validate");
  });

  test("checks out the repo and sets up Bun with pinned action versions", () => {
    const uses = doc.jobs.validate.steps.map((s: any) => s.uses).filter(Boolean);
    expect(uses).toContain("actions/checkout@v4");
    expect(uses).toContain("oven-sh/setup-bun@v2");
  });

  test("invokes the validator script via `bun run validate.ts`", () => {
    const runScript = doc.jobs.validate.steps
      .map((s: any) => s.run)
      .filter(Boolean)
      .join("\n");
    expect(runScript).toContain("bun run validate.ts");
    expect(runScript).toContain("--format markdown");
    expect(runScript).toContain("--format json");
  });

  test("references project files that actually exist on disk", () => {
    // The script the workflow runs, and the default fixture it points at.
    expect(existsSync(join(PROJECT_ROOT, "validate.ts"))).toBe(true);
    expect(existsSync(join(PROJECT_ROOT, "src", "validator.ts"))).toBe(true);
    expect(existsSync(join(PROJECT_ROOT, "fixtures", "secrets.json"))).toBe(
      true,
    );
  });
});

describe("actionlint", () => {
  test("passes cleanly (exit code 0)", () => {
    const res = spawnSync("actionlint", [WORKFLOW], { encoding: "utf8" });
    if (res.status !== 0) {
      // Surface the linter output so failures are actionable.
      console.error(res.stdout, res.stderr);
    }
    expect(res.status).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// End-to-end act runs
// ---------------------------------------------------------------------------

/** Project entries copied into each throwaway repo (everything `act` needs). */
const COPY_TOP_LEVEL = [
  "src",
  "validate.ts",
  "package.json",
  "tsconfig.json",
  ".github",
  ".actrc",
];
// Only the unit-test files the workflow actually runs (not this harness).
const COPY_TEST_FILES = [
  "validator.test.ts",
  "report.test.ts",
  "cli.test.ts",
];

/** Build an isolated git repo containing the project + the given fixture. */
function setupRepo(fixtureFile: string): string {
  const dir = mkdtempSync(join(tmpdir(), "srv-act-"));

  for (const entry of COPY_TOP_LEVEL) {
    cpSync(join(PROJECT_ROOT, entry), join(dir, entry), { recursive: true });
  }
  mkdirSync(join(dir, "tests"), { recursive: true });
  for (const f of COPY_TEST_FILES) {
    cpSync(join(PROJECT_ROOT, "tests", f), join(dir, "tests", f));
  }

  // The workflow reads fixtures/secrets.json by default; swap in this case's data.
  cpSync(
    join(PROJECT_ROOT, "fixtures", fixtureFile),
    join(dir, "fixtures", "secrets.json"),
  );

  // act resolves the event/ref from a git repo, so initialise and commit.
  const git = (args: string[]) =>
    spawnSync("git", args, { cwd: dir, encoding: "utf8" });
  git(["init", "-q"]);
  git(["config", "user.email", "ci@example.com"]);
  git(["config", "user.name", "CI"]);
  git(["add", "-A"]);
  git(["commit", "-q", "-m", "test fixture"]);

  return dir;
}

/** Run `act push --rm` in the repo, capture combined output, append to log. */
function runAct(dir: string, caseName: string): { code: number; out: string } {
  // --pull=false: the act image is already present locally; act's default
  // force-pull would otherwise try (and fail) to re-pull it from a registry.
  const res = spawnSync("act", ["push", "--rm", "--pull=false"], {
    cwd: dir,
    encoding: "utf8",
    maxBuffer: 64 * 1024 * 1024,
  });
  const out = `${res.stdout ?? ""}\n${res.stderr ?? ""}`;

  appendFileSync(
    ACT_RESULT,
    `\n${"=".repeat(72)}\n` +
      `TEST CASE: ${caseName}\n` +
      `act exit code: ${res.status}\n` +
      `${"=".repeat(72)}\n${out}\n`,
  );

  return { code: res.status ?? -1, out };
}

describe("act end-to-end pipeline", () => {
  // Start each full test run with a fresh log file.
  beforeAll(() => {
    writeFileSync(
      ACT_RESULT,
      `Secret Rotation Validator — act run log\n` +
        `Reference date pinned to 2026-06-27 via workflow env defaults.\n`,
    );
  });

  const createdDirs: string[] = [];
  afterAll(() => {
    for (const d of createdDirs) {
      try {
        rmSync(d, { recursive: true, force: true });
      } catch {
        /* best-effort cleanup */
      }
    }
  });

  // Case 1: mixed fixture -> exactly one of each urgency.
  test(
    "case 'mixed': reports expired=1 warning=1 ok=1 total=3 and both jobs succeed",
    () => {
      const dir = setupRepo("secrets.json");
      createdDirs.push(dir);
      const { code, out } = runAct(dir, "mixed");

      expect(code).toBe(0);
      // Exact summary line emitted by the validate job.
      expect(out).toContain("ROTATION_SUMMARY expired=1 warning=1 ok=1 total=3");
      // Exact grouped-notification line emitted by the notify job.
      expect(out).toContain("NOTIFY expired=1 warning=1 ok=1 total=3");
      // The expired secret is named in the rendered report.
      expect(out).toContain("DATABASE_PASSWORD");
      // Both jobs must report success.
      const succeeded = (out.match(/Job succeeded/g) ?? []).length;
      expect(succeeded).toBeGreaterThanOrEqual(2);
    },
    300_000,
  );

  // Case 2: all-healthy fixture -> nothing expired or in the warning window.
  test(
    "case 'healthy': reports expired=0 warning=0 ok=2 total=2 and both jobs succeed",
    () => {
      const dir = setupRepo("all-healthy.json");
      createdDirs.push(dir);
      const { code, out } = runAct(dir, "healthy");

      expect(code).toBe(0);
      expect(out).toContain("ROTATION_SUMMARY expired=0 warning=0 ok=2 total=2");
      expect(out).toContain("NOTIFY expired=0 warning=0 ok=2 total=2");
      const succeeded = (out.match(/Job succeeded/g) ?? []).length;
      expect(succeeded).toBeGreaterThanOrEqual(2);
    },
    300_000,
  );

  // Guarantee the required artifact exists after the suite runs.
  test("produced the act-result.txt artifact", () => {
    expect(existsSync(ACT_RESULT)).toBe(true);
  });
});
