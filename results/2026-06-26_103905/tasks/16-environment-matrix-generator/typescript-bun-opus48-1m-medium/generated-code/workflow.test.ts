// Workflow-level tests.
//
// Two kinds of checks live here:
//   1. Static structure tests — parse the workflow YAML and verify triggers,
//      jobs, steps, referenced script paths, and that actionlint passes.
//   2. End-to-end act tests — for several fixture configs, build a throwaway
//      git repo, run the workflow with `nektos/act`, and assert on the EXACT
//      generated-matrix values parsed out of the act output.
//
// All act output is appended to act-result.txt (a required artifact).
import { describe, expect, test, beforeAll } from "bun:test";
import {
  cpSync,
  existsSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
  appendFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const PROJECT = import.meta.dir;
const WORKFLOW = join(PROJECT, ".github/workflows/environment-matrix-generator.yml");
const ACT_RESULT = join(PROJECT, "act-result.txt");

// ---------------------------------------------------------------------------
// 1. Static workflow structure tests.
// ---------------------------------------------------------------------------
describe("workflow structure", () => {
  const text = readFileSync(WORKFLOW, "utf8");
  const wf = Bun.YAML.parse(text) as any;

  test("defines the expected trigger events", () => {
    const on = wf.on;
    expect(Object.keys(on)).toEqual(
      expect.arrayContaining(["push", "pull_request", "schedule", "workflow_dispatch"]),
    );
    expect(on.schedule[0].cron).toBe("0 6 * * 1");
  });

  test("declares least-privilege read permissions", () => {
    expect(wf.permissions.contents).toBe("read");
  });

  test("has a generate-matrix job running on ubuntu-latest", () => {
    expect(wf.jobs["generate-matrix"]).toBeDefined();
    expect(wf.jobs["generate-matrix"]["runs-on"]).toBe("ubuntu-latest");
  });

  test("checks out the repo and references the generator scripts", () => {
    const steps = wf.jobs["generate-matrix"].steps as any[];
    const uses = steps.map((s) => s.uses).filter(Boolean);
    expect(uses).toContain("actions/checkout@v4");
    const runs = steps.map((s) => s.run ?? "").join("\n");
    expect(runs).toContain("matrix-generator.ts");
    expect(runs).toContain("summarize.ts");
    expect(runs).toContain("bun test");
  });

  test("references script files that actually exist on disk", () => {
    for (const f of ["matrix-generator.ts", "summarize.ts"]) {
      expect(existsSync(join(PROJECT, f))).toBe(true);
    }
  });

  test("passes actionlint with exit code 0", async () => {
    const proc = Bun.spawn(["actionlint", WORKFLOW], { stdout: "pipe", stderr: "pipe" });
    const out = (await new Response(proc.stdout).text()) + (await new Response(proc.stderr).text());
    const code = await proc.exited;
    expect(out).toBe("");
    expect(code).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// 2. End-to-end act tests.
//
// Each case: a fixture config + the exact values we expect the workflow to
// print. The generator is deterministic, so we assert on known-good output.
// ---------------------------------------------------------------------------
interface ActCase {
  name: string;
  config: unknown;
  expect: {
    size: number;
    failFast: boolean;
    maxParallel: number | null;
    include: unknown[];
  };
}

const CASES: ActCase[] = [
  {
    // Default config: cartesian, one exclude, one include that adds a new row.
    name: "default-exclude-include",
    config: {
      matrix: { os: ["ubuntu-latest", "windows-latest"], node: ["18", "20"] },
      exclude: [{ os: "windows-latest", node: "18" }],
      include: [{ os: "macos-latest", node: "20", experimental: true }],
      failFast: false,
      maxParallel: 3,
      maxSize: 50,
    },
    expect: {
      size: 4,
      failFast: false,
      maxParallel: 3,
      include: [
        { os: "ubuntu-latest", node: "18" },
        { os: "ubuntu-latest", node: "20" },
        { os: "windows-latest", node: "20" },
        { os: "macos-latest", node: "20", experimental: true },
      ],
    },
  },
  {
    // Multiple partial excludes whittle a 3x3 grid down to 4 rows.
    name: "multi-exclude",
    config: {
      matrix: {
        os: ["ubuntu-latest", "windows-latest", "macos-latest"],
        node: ["18", "20", "22"],
      },
      exclude: [{ os: "macos-latest" }, { node: "18" }],
      failFast: true,
      maxParallel: 5,
      maxSize: 100,
    },
    expect: {
      size: 4,
      failFast: true,
      maxParallel: 5,
      include: [
        { os: "ubuntu-latest", node: "20" },
        { os: "ubuntu-latest", node: "22" },
        { os: "windows-latest", node: "20" },
        { os: "windows-latest", node: "22" },
      ],
    },
  },
  {
    // Boolean feature flags + an include row that no base combo can absorb.
    name: "feature-flags",
    config: {
      matrix: {
        os: ["ubuntu-latest"],
        python: ["3.11", "3.12"],
        coverage: [true, false],
      },
      include: [
        { os: "ubuntu-latest", python: "3.13", coverage: true, experimental: true },
      ],
      failFast: true,
      maxParallel: 2,
      maxSize: 10,
    },
    expect: {
      size: 5,
      failFast: true,
      maxParallel: 2,
      include: [
        { os: "ubuntu-latest", python: "3.11", coverage: true },
        { os: "ubuntu-latest", python: "3.11", coverage: false },
        { os: "ubuntu-latest", python: "3.12", coverage: true },
        { os: "ubuntu-latest", python: "3.12", coverage: false },
        { os: "ubuntu-latest", python: "3.13", coverage: true, experimental: true },
      ],
    },
  },
];

/** Build a throwaway git repo containing the project + this case's fixture. */
function setupRepo(config: unknown): string {
  const dir = mkdtempSync(join(tmpdir(), "matrix-act-"));
  // Copy project files needed by the workflow (skip vcs/node_modules/artifacts).
  for (const f of [
    "matrix-generator.ts",
    "summarize.ts",
    "matrix-generator.test.ts",
    "cli.test.ts",
    "package.json",
    ".actrc",
    ".github",
    "fixtures",
  ]) {
    const src = join(PROJECT, f);
    if (existsSync(src)) cpSync(src, join(dir, f), { recursive: true });
  }
  // Overwrite the config the workflow reads with this case's fixture.
  writeFileSync(
    join(dir, "fixtures/default-config.json"),
    JSON.stringify(config, null, 2),
  );
  // act requires a git repo.
  const git = (args: string[]) =>
    Bun.spawnSync(["git", ...args], { cwd: dir, stdout: "pipe", stderr: "pipe" });
  git(["init", "-q"]);
  git(["config", "user.email", "test@example.com"]);
  git(["config", "user.name", "test"]);
  git(["add", "-A"]);
  git(["commit", "-qm", "fixture"]);
  return dir;
}

/** Run act for one case and return its combined output + exit code. */
function runAct(dir: string): { output: string; code: number } {
  const proc = Bun.spawnSync(
    [
      "act",
      "push",
      "--rm",
      "--pull=false", // use the locally-built act image; don't try to pull it.
      "-W",
      ".github/workflows/environment-matrix-generator.yml",
    ],
    { cwd: dir, stdout: "pipe", stderr: "pipe" },
  );
  const output =
    new TextDecoder().decode(proc.stdout) + new TextDecoder().decode(proc.stderr);
  return { output, code: proc.exitCode ?? -1 };
}

/** Extract `KEY=...` lines that the summarize step prints (act prefixes them). */
function extract(output: string, key: string): string | null {
  // act lines look like: "[Workflow/job] |   KEY=value"
  const re = new RegExp(`${key}=(.*)`);
  const lines = output.split("\n");
  for (let i = lines.length - 1; i >= 0; i--) {
    const m = lines[i].match(re);
    if (m) return m[1].trim();
  }
  return null;
}

describe("workflow via act", () => {
  beforeAll(() => {
    // Start each full run with a fresh artifact file.
    writeFileSync(ACT_RESULT, `act-result — generated ${"run"}\n`);
  });

  for (const c of CASES) {
    test(
      `case: ${c.name}`,
      () => {
        const dir = setupRepo(c.config);
        let result: { output: string; code: number };
        try {
          result = runAct(dir);
        } finally {
          // Keep the artifact even if act throws.
        }
        // Append clearly-delimited output to the required artifact.
        appendFileSync(
          ACT_RESULT,
          `\n${"=".repeat(70)}\nCASE: ${c.name}\nEXIT CODE: ${result.code}\n${"=".repeat(70)}\n${result.output}\n`,
        );
        rmSync(dir, { recursive: true, force: true });

        // Assert act succeeded.
        expect(result.code).toBe(0);
        // Assert the job reported success.
        expect(result.output).toMatch(/Job succeeded/);

        // Assert EXACT generated-matrix values parsed from the output.
        expect(extract(result.output, "MATRIX_SIZE")).toBe(String(c.expect.size));
        expect(extract(result.output, "FAIL_FAST")).toBe(String(c.expect.failFast));
        expect(extract(result.output, "MAX_PARALLEL")).toBe(
          String(c.expect.maxParallel),
        );
        const json = extract(result.output, "MATRIX_JSON");
        expect(json).not.toBeNull();
        expect(JSON.parse(json as string)).toEqual(c.expect.include);
      },
      300_000, // act can take a while: install bun, run tests, generate.
    );
  }
});
