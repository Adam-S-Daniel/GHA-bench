// workflow.test.ts — the GitHub Actions integration harness.
//
// This file does NOT test the script directly. Instead, every functional test
// case runs through the real workflow via `act`:
//   1. A temp git repo is created with the project files + that case's fixture
//      data (version file + commit log).
//   2. `act push --rm` runs the workflow inside an isolated Docker container,
//      overriding VERSION_FILE / COMMITS_FILE per case via `--env`.
//   3. The combined act output is appended to ./act-result.txt (delimited).
//   4. We assert act exited 0, every job reports "Job succeeded", and the
//      output contains the EXACT expected version / bump / changelog values.
//
// It also includes pure (no-act) structure tests that parse the workflow YAML
// and verify its triggers, jobs, steps, referenced files, and actionlint.
//
// NOTE: this file is intentionally excluded from `bun run test:unit` (and from
// the in-CI test step) so act is never invoked recursively inside act.
import {
  afterAll,
  beforeAll,
  describe,
  expect,
  it,
} from "bun:test";
import { spawnSync } from "node:child_process";
import {
  appendFileSync,
  cpSync,
  existsSync,
  mkdtempSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const PROJECT_DIR = join(import.meta.dir, "..");
const WORKFLOW_REL = ".github/workflows/semantic-version-bumper.yml";
const WORKFLOW_PATH = join(PROJECT_DIR, WORKFLOW_REL);
const ACT_RESULT_FILE = join(PROJECT_DIR, "act-result.txt");
const ACT_IMAGE = "ubuntu-latest=act-ubuntu-pwsh:latest";

// Project files/dirs copied into each isolated temp repo.
const COPY_INTO_REPO = [
  "src",
  "tests",
  "fixtures",
  ".github",
  "package.json",
  "tsconfig.json",
];

// ─── Test cases ──────────────────────────────────────────────────────────────
// Each case fully specifies its inputs and the exact known-good outputs.
interface ActCase {
  name: string;
  versionFile: string; // path the workflow reads (via VERSION_FILE env)
  versionContent: string; // contents written into that file
  commitsFile: string; // fixture commit-log path (via COMMITS_FILE env)
  startVersion: string;
  expectedVersion: string;
  expectedBump: "major" | "minor" | "patch";
  expectedSections: string[]; // changelog sections that must appear
}

const ALL_CASES: ActCase[] = [
  {
    name: "feat-minor",
    versionFile: "version.txt",
    versionContent: "1.1.0\n",
    commitsFile: "fixtures/commits-feat.txt",
    startVersion: "1.1.0",
    expectedVersion: "1.2.0",
    expectedBump: "minor",
    expectedSections: ["Features", "Bug Fixes", "Other Changes"],
  },
  {
    name: "fix-patch-packagejson",
    versionFile: "meta.json",
    versionContent: `${JSON.stringify({ name: "demo", version: "2.3.4" }, null, 2)}\n`,
    commitsFile: "fixtures/commits-fix.txt",
    startVersion: "2.3.4",
    expectedVersion: "2.3.5",
    expectedBump: "patch",
    expectedSections: ["Bug Fixes", "Other Changes"],
  },
  {
    name: "breaking-major",
    versionFile: "version.txt",
    versionContent: "0.5.7\n",
    commitsFile: "fixtures/commits-breaking.txt",
    startVersion: "0.5.7",
    expectedVersion: "1.0.0",
    expectedBump: "major",
    expectedSections: ["⚠ BREAKING CHANGES", "Features", "Bug Fixes"],
  },
];

// Allow running a subset / controlling truncation so the act budget can be
// spent across a couple of invocations during development. Defaults run the
// full set and start act-result.txt fresh — the canonical deliverable run.
const CASE_FILTER = (process.env.SVB_ACT_CASES ?? "")
  .split(",")
  .map((s) => s.trim())
  .filter(Boolean);
const ACT_CASES = CASE_FILTER.length
  ? ALL_CASES.filter((c) => CASE_FILTER.includes(c.name))
  : ALL_CASES;
const TRUNCATE_RESULTS = process.env.SVB_ACT_TRUNCATE !== "0";

// ─── Helpers ─────────────────────────────────────────────────────────────────

/** Build an isolated git repo containing the project + this case's fixtures. */
function setupRepo(tc: ActCase): string {
  const dir = mkdtempSync(join(tmpdir(), `svb-act-${tc.name}-`));

  for (const entry of COPY_INTO_REPO) {
    const from = join(PROJECT_DIR, entry);
    if (existsSync(from)) {
      cpSync(from, join(dir, entry), { recursive: true });
    }
  }
  // Never let the act harness itself run inside act (it would recurse).
  rmSync(join(dir, "tests", "workflow.test.ts"), { force: true });

  // Write this case's version source.
  writeFileSync(join(dir, tc.versionFile), tc.versionContent);

  // act's actions/checkout@v4 needs a real git repo to operate on.
  const git = (args: string) =>
    spawnSync("git", args.split(" "), { cwd: dir, stdio: "pipe" });
  git("init -b main");
  git("config user.email test@example.com");
  git("config user.name test");
  spawnSync("git", ["add", "-A"], { cwd: dir, stdio: "pipe" });
  spawnSync("git", ["commit", "-m", "chore: scaffold"], {
    cwd: dir,
    stdio: "pipe",
  });

  return dir;
}

/** Run the workflow for one case via act, returning exit code + output. */
function runAct(dir: string, tc: ActCase): { exitCode: number; output: string } {
  const result = spawnSync(
    "act",
    [
      "push",
      "--rm",
      // The runner image is built locally; never try to pull it from a registry.
      "--pull=false",
      "-W",
      WORKFLOW_REL,
      "-P",
      ACT_IMAGE,
      "--env",
      `VERSION_FILE=${tc.versionFile}`,
      "--env",
      `COMMITS_FILE=${tc.commitsFile}`,
    ],
    {
      cwd: dir,
      encoding: "utf-8",
      timeout: 600_000,
      env: { ...process.env },
    },
  );
  const output = `${result.stdout ?? ""}\n${result.stderr ?? ""}`;
  if (result.error) {
    return { exitCode: 1, output: `${output}\nspawn error: ${result.error.message}` };
  }
  return { exitCode: result.status ?? 1, output };
}

// ─── Structure tests (fast, no act) ──────────────────────────────────────────

describe("workflow structure", () => {
  // Parse the workflow YAML once for structural assertions.
  const yaml = Bun.YAML.parse(
    require("node:fs").readFileSync(WORKFLOW_PATH, "utf8"),
  ) as any;

  it("the workflow file exists", () => {
    expect(existsSync(WORKFLOW_PATH)).toBe(true);
  });

  it("declares the expected trigger events", () => {
    const triggers = Object.keys(yaml.on);
    for (const t of ["push", "pull_request", "workflow_dispatch", "schedule"]) {
      expect(triggers).toContain(t);
    }
    // schedule must carry a cron entry.
    expect(yaml.on.schedule[0].cron).toBeDefined();
  });

  it("declares read-only contents permission", () => {
    expect(yaml.permissions.contents).toBe("read");
  });

  it("defines a single bump job on ubuntu-latest", () => {
    expect(Object.keys(yaml.jobs)).toContain("bump");
    expect(yaml.jobs.bump["runs-on"]).toBe("ubuntu-latest");
  });

  it("checks out the repo, installs bun, runs tests, and runs the script", () => {
    const steps = yaml.jobs.bump.steps as any[];
    const uses = steps.map((s) => s.uses).filter(Boolean);
    const runs = steps.map((s) => s.run ?? "").join("\n");

    expect(uses).toContain("actions/checkout@v4");
    expect(runs).toContain("bun.sh/install"); // installs the bun runtime
    expect(runs).toContain("bun run test:unit"); // runs the unit suite
    expect(runs).toContain("src/index.ts"); // invokes our script
  });

  it("references only files that exist on disk", () => {
    for (const f of [
      "src/index.ts",
      "src/bumper.ts",
      "src/semver.ts",
      "src/commits.ts",
      "src/changelog.ts",
      "src/version-file.ts",
      "fixtures/commits.txt",
      "version.txt",
    ]) {
      expect(existsSync(join(PROJECT_DIR, f))).toBe(true);
    }
  });

  it("passes actionlint with exit code 0", () => {
    const r = spawnSync("actionlint", [WORKFLOW_PATH], { encoding: "utf-8" });
    if (r.status !== 0) console.error(r.stdout, r.stderr);
    expect(r.status).toBe(0);
  });
});

// ─── Act integration tests (the real pipeline) ───────────────────────────────

describe("workflow via act", () => {
  const created: string[] = [];

  beforeAll(() => {
    // Start a fresh archive unless we are explicitly appending across runs.
    if (TRUNCATE_RESULTS || !existsSync(ACT_RESULT_FILE)) {
      writeFileSync(
        ACT_RESULT_FILE,
        `=== Semantic Version Bumper — act pipeline results ===\n` +
          `Image: ${ACT_IMAGE}\n`,
      );
    }
  });

  afterAll(() => {
    for (const dir of created) rmSync(dir, { recursive: true, force: true });
  });

  for (const tc of ACT_CASES) {
    it(
      `${tc.name}: ${tc.startVersion} -> ${tc.expectedVersion} (${tc.expectedBump})`,
      () => {
        const dir = setupRepo(tc);
        created.push(dir);

        const { exitCode, output } = runAct(dir, tc);

        // Archive the full output for this case, clearly delimited.
        appendFileSync(
          ACT_RESULT_FILE,
          `\n${"=".repeat(72)}\n` +
            `CASE: ${tc.name}\n` +
            `version file: ${tc.versionFile} (start ${tc.startVersion})\n` +
            `commits: ${tc.commitsFile}\n` +
            `expected: NEW_VERSION=${tc.expectedVersion} BUMP_TYPE=${tc.expectedBump}\n` +
            `act exit code: ${exitCode}\n` +
            `${"=".repeat(72)}\n` +
            output +
            "\n",
        );

        // (1) act succeeded.
        expect(exitCode).toBe(0);
        // (2) every job reported success.
        expect(output).toContain("Job succeeded");
        // (3) exact machine-readable results.
        expect(output).toContain(`PREVIOUS_VERSION=${tc.startVersion}`);
        expect(output).toContain(`NEW_VERSION=${tc.expectedVersion}`);
        expect(output).toContain(`BUMP_TYPE=${tc.expectedBump}`);
        expect(output).toContain("CHANGED=true");
        // (4) changelog header + sections were generated.
        expect(output).toContain(`## [${tc.expectedVersion}]`);
        for (const section of tc.expectedSections) {
          expect(output).toContain(`### ${section}`);
        }
      },
      600_000,
    );
  }

  it("produced the act-result.txt artifact", () => {
    expect(existsSync(ACT_RESULT_FILE)).toBe(true);
    expect(statSync(ACT_RESULT_FILE).size).toBeGreaterThan(0);
  });
});
