/**
 * Workflow integration + structure tests.
 *
 * Per the task requirements, EVERY functional test case is executed through the
 * GitHub Actions workflow via `act` (nektos/act) running in Docker — we never
 * invoke the script directly here. For each case we:
 *   1. build a throwaway git repo containing the project files + that case's
 *      fixture data (copied to the path the workflow reads),
 *   2. run `act push --rm`, capturing combined stdout/stderr,
 *   3. append the output to `act-result.txt` (the required artifact),
 *   4. assert act exited 0, that BOTH jobs report "Job succeeded", and that the
 *      output contains the EXACT expected values for that fixture.
 *
 * It also statically validates the workflow file (YAML structure, script
 * references, and a clean `actionlint` run).
 *
 * Run with: `bun test`   (act + Docker must be available)
 */
import { describe, it, expect, beforeAll } from "bun:test";
import { spawnSync } from "node:child_process";
import {
  mkdtempSync,
  mkdirSync,
  copyFileSync,
  writeFileSync,
  appendFileSync,
  existsSync,
  rmSync,
  readFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { parse as parseYaml } from "yaml";

// Project root = directory of this test file. `bun test` runs from here too.
const ROOT = import.meta.dir;
const WORKFLOW_REL = ".github/workflows/secret-rotation-validator.yml";
const WORKFLOW_PATH = join(ROOT, WORKFLOW_REL);
const SCRIPT = "secret-rotation-validator.ts";
const ACT_RESULT = join(ROOT, "act-result.txt");

// Files every temp repo needs. The script is self-contained (only bun built-ins
// + its own module), so the workflow never has to run `bun install`.
const PROJECT_FILES = [SCRIPT, "package.json", "tsconfig.json", ".actrc"] as const;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Run a command, returning {status, output} with combined stdout+stderr. */
function run(
  cmd: string,
  argv: string[],
  cwd: string,
  timeoutMs = 240_000,
): { status: number; output: string } {
  const res = spawnSync(cmd, argv, {
    cwd,
    encoding: "utf8",
    timeout: timeoutMs,
    maxBuffer: 256 * 1024 * 1024,
  });
  if (res.error) {
    return { status: 1, output: `spawn error: ${res.error.message}` };
  }
  return { status: res.status ?? 1, output: (res.stdout ?? "") + (res.stderr ?? "") };
}

/**
 * Build a temp git repo with the project + the given fixture (copied to the path
 * the workflow reads), run `act push`, append output to act-result.txt, and
 * return the captured output + exit code.
 */
function runActCase(
  caseName: string,
  fixtureRelPath: string,
): { output: string; exitCode: number } {
  const tmp = mkdtempSync(join(tmpdir(), "srv-act-"));
  try {
    // Copy the static project files.
    for (const f of PROJECT_FILES) {
      copyFileSync(join(ROOT, f), join(tmp, f));
    }
    // The workflow reads fixtures/secrets.json; drop this case's fixture there.
    mkdirSync(join(tmp, "fixtures"), { recursive: true });
    copyFileSync(join(ROOT, fixtureRelPath), join(tmp, "fixtures", "secrets.json"));
    // Copy the workflow.
    mkdirSync(join(tmp, ".github", "workflows"), { recursive: true });
    copyFileSync(WORKFLOW_PATH, join(tmp, WORKFLOW_REL));

    // Initialise a committed git repo (act requires a commit to check out).
    const gitSetup = run(
      "bash",
      [
        "-c",
        "git init -q && git config user.email ci@example.com && " +
          "git config user.name ci && git add -A && git commit -qm 'test fixture'",
      ],
      tmp,
    );
    if (gitSetup.status !== 0) {
      throw new Error(`git setup failed:\n${gitSetup.output}`);
    }

    // Run the workflow in Docker via act. --pull=false: the base image is a
    // locally-built tag, so never try to pull it from a registry.
    const act = run("act", ["push", "--rm", "--pull=false"], tmp);

    // Append to the required artifact with a clear delimiter.
    const banner = "=".repeat(78);
    appendFileSync(
      ACT_RESULT,
      `\n${banner}\nTEST CASE: ${caseName}  (fixture: ${fixtureRelPath})\n` +
        `act exit code: ${act.status}\n${banner}\n${act.output}\n`,
    );

    return { output: act.output, exitCode: act.status };
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
}

/** Count non-overlapping occurrences of a substring. */
function countOccurrences(haystack: string, needle: string): number {
  let count = 0;
  let idx = haystack.indexOf(needle);
  while (idx !== -1) {
    count++;
    idx = haystack.indexOf(needle, idx + needle.length);
  }
  return count;
}

// ---------------------------------------------------------------------------
// Workflow structure tests (static — no Docker needed)
// ---------------------------------------------------------------------------

describe("workflow structure", () => {
  const rawYaml = readFileSync(WORKFLOW_PATH, "utf8");
  // YAML parses `on:` to the boolean key `true`, so read it back from both.
  const wf = parseYaml(rawYaml) as Record<string, unknown>;
  const triggers = (wf.on ?? (wf as Record<string, unknown>)["true"]) as Record<
    string,
    unknown
  >;

  it("the workflow file exists and is valid YAML", () => {
    expect(existsSync(WORKFLOW_PATH)).toBe(true);
    expect(wf).toBeTypeOf("object");
    expect(wf.name).toBe("Secret Rotation Validator");
  });

  it("declares the expected trigger events", () => {
    expect(triggers).toBeTypeOf("object");
    expect(Object.keys(triggers)).toEqual(
      expect.arrayContaining(["push", "pull_request", "schedule", "workflow_dispatch"]),
    );
  });

  it("sets least-privilege permissions", () => {
    expect(wf.permissions).toMatchObject({ contents: "read" });
  });

  it("defines the validate and notify jobs with a dependency", () => {
    const jobs = wf.jobs as Record<string, { needs?: unknown; steps?: unknown[] }>;
    expect(Object.keys(jobs)).toEqual(expect.arrayContaining(["validate", "notify"]));
    expect(jobs.notify!.needs).toBe("validate");
    expect(Array.isArray(jobs.validate!.steps)).toBe(true);
    expect((jobs.validate!.steps as unknown[]).length).toBeGreaterThan(0);
  });

  it("checks out the repo and sets up Bun via pinned actions", () => {
    const steps = (wf.jobs as Record<string, { steps: { uses?: string }[] }>).validate.steps;
    const uses = steps.map((s) => s.uses).filter(Boolean);
    expect(uses).toEqual(expect.arrayContaining(["actions/checkout@v4", "oven-sh/setup-bun@v2"]));
  });

  it("references the script and config files, which exist on disk", () => {
    expect(rawYaml).toContain(SCRIPT);
    expect(existsSync(join(ROOT, SCRIPT))).toBe(true);
    expect(rawYaml).toContain("fixtures/secrets.json");
    expect(existsSync(join(ROOT, "fixtures/secrets.json"))).toBe(true);
  });

  it("passes actionlint with exit code 0", () => {
    const res = run("actionlint", [WORKFLOW_PATH], ROOT, 60_000);
    expect(res.output).toBe(res.status === 0 ? res.output : ""); // surface output on failure
    expect(res.status).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// Act integration tests — one `act push` per fixture, exact-value assertions
// ---------------------------------------------------------------------------

describe("act integration (every case runs through the workflow)", () => {
  beforeAll(() => {
    // Start each full run with a fresh artifact.
    writeFileSync(
      ACT_RESULT,
      `Secret Rotation Validator — act integration output\n` +
        `Each section below is one fixture executed end-to-end via 'act push'.\n`,
    );
    // Fail fast with a clear message if the toolchain is missing.
    expect(run("act", ["--version"], ROOT, 20_000).status).toBe(0);
    expect(run("docker", ["version"], ROOT, 20_000).status).toBe(0);
  });

  // Assertions shared by every successful run.
  function assertJobsSucceeded(output: string, exitCode: number): void {
    expect(exitCode).toBe(0);
    expect(output).not.toContain("Job failed");
    // Two jobs (validate + notify) must each report success.
    expect(countOccurrences(output, "Job succeeded")).toBe(2);
  }

  it(
    "mixed fixture: 6 secrets across expired/warning/ok with exact grouping",
    () => {
      const { output, exitCode } = runActCase("mixed", "fixtures/secrets.json");
      assertJobsSucceeded(output, exitCode);

      // Validator summary line (stderr -> act log).
      expect(output).toContain(
        "total=6 expired=2 warning=2 ok=2 (now=2026-06-28, warningWindow=14d)",
      );
      // notify job: exact urgency grouping, in soonest-deadline order.
      expect(output).toContain("EXPIRED (2): db-password,stripe-api-key");
      expect(output).toContain("WARNING (2): tls-cert,jwt-signing-key");
      expect(output).toContain("OK (2): backup-encryption-key,oauth-client-secret");
      // markdown report row.
      expect(output).toContain("| db-password | expired |");
      // JSON report present with a concrete classification.
      expect(output).toContain('"status": "expired"');
    },
    240_000,
  );

  it(
    "all-ok fixture: nothing expired or in the warning window",
    () => {
      const { output, exitCode } = runActCase("all-ok", "fixtures/all-ok.json");
      assertJobsSucceeded(output, exitCode);

      expect(output).toContain(
        "total=2 expired=0 warning=0 ok=2 (now=2026-06-28, warningWindow=30d)",
      );
      expect(output).toContain("EXPIRED (0): ");
      expect(output).toContain("WARNING (0): ");
      expect(output).toContain("OK (2): deploy-key,service-token");
    },
    240_000,
  );

  it(
    "boundary fixture: due-today=expired, edge=warning, +1=ok",
    () => {
      const { output, exitCode } = runActCase("boundary", "fixtures/boundary.json");
      assertJobsSucceeded(output, exitCode);

      expect(output).toContain(
        "total=3 expired=1 warning=1 ok=1 (now=2026-06-28, warningWindow=10d)",
      );
      expect(output).toContain("EXPIRED (1): due-today");
      expect(output).toContain("WARNING (1): edge-warning");
      expect(output).toContain("OK (1): just-ok");
    },
    240_000,
  );

  it("wrote the act-result.txt artifact", () => {
    expect(existsSync(ACT_RESULT)).toBe(true);
    const content = readFileSync(ACT_RESULT, "utf8");
    expect(content).toContain("TEST CASE: mixed");
    expect(content).toContain("TEST CASE: all-ok");
    expect(content).toContain("TEST CASE: boundary");
  });
});
