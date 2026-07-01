// Workflow-level tests.
//
// Two kinds of checks live here, deliberately kept out of `bun run test`
// (see package.json) because they are slow and/or shell out to `act`/Docker:
//
//   1. Static structure tests — parse the workflow YAML and confirm the
//      triggers/jobs/steps/permissions are as expected, that it references
//      real files on disk, and that `actionlint` accepts it.
//   2. End-to-end pipeline tests — for each fixture scenario, build a
//      throwaway git repo containing this project, run the real workflow
//      with `act push`, and assert on the EXACT matrix values parsed out of
//      the container's output. Every test case here executes through the
//      actual GitHub Actions pipeline; nothing is asserted by calling the
//      script directly.
//
// All `act` output is appended to act-result.txt, a required artifact.
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
const WORKFLOW_PATH = join(PROJECT, ".github/workflows/environment-matrix-generator.yml");
const ACT_RESULT_PATH = join(PROJECT, "act-result.txt");

// ---------------------------------------------------------------------------
// 1. Static workflow structure tests.
// ---------------------------------------------------------------------------
describe("workflow structure", () => {
  const yamlText = readFileSync(WORKFLOW_PATH, "utf8");
  const workflow = Bun.YAML.parse(yamlText) as any;
  const triggers = workflow.on;

  test("triggers on push, pull_request, schedule, and workflow_dispatch", () => {
    expect(Object.keys(triggers)).toEqual(
      expect.arrayContaining(["push", "pull_request", "schedule", "workflow_dispatch"]),
    );
    expect(triggers.schedule[0].cron).toBe("0 6 * * 1");
  });

  test("grants only read access to repository contents", () => {
    expect(workflow.permissions).toEqual({ contents: "read" });
  });

  test("defines a config-path environment variable", () => {
    expect(workflow.env.MATRIX_CONFIG_PATH).toBe("fixtures/scenario.json");
  });

  test("has a generate-matrix job that depends on the test job", () => {
    expect(workflow.jobs.test).toBeDefined();
    expect(workflow.jobs["generate-matrix"]).toBeDefined();
    expect(workflow.jobs["generate-matrix"].needs).toBe("test");
    expect(workflow.jobs.test["runs-on"]).toBe("ubuntu-latest");
    expect(workflow.jobs["generate-matrix"]["runs-on"]).toBe("ubuntu-latest");
  });

  test("checks out the repo and references the generator scripts", () => {
    const allSteps = [
      ...workflow.jobs.test.steps,
      ...workflow.jobs["generate-matrix"].steps,
    ] as any[];
    expect(allSteps.map((s) => s.uses).filter(Boolean)).toContain("actions/checkout@v4");
    const runText = allSteps.map((s) => s.run ?? "").join("\n");
    expect(runText).toContain("matrix-generator.ts");
    expect(runText).toContain("format-summary.ts");
    expect(runText).toContain("bun run test");
  });

  test("references script and fixture files that actually exist on disk", () => {
    for (const relativePath of [
      "matrix-generator.ts",
      "format-summary.ts",
      "fixtures/scenario.json",
      "package.json",
    ]) {
      expect(existsSync(join(PROJECT, relativePath))).toBe(true);
    }
  });

  test("passes actionlint with exit code 0 and no output", async () => {
    const proc = Bun.spawn(["actionlint", WORKFLOW_PATH], { stdout: "pipe", stderr: "pipe" });
    const output =
      (await new Response(proc.stdout).text()) + (await new Response(proc.stderr).text());
    const code = await proc.exited;
    expect(output).toBe("");
    expect(code).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// 2. End-to-end tests: run the real workflow through `act` for each fixture.
//
// Expected values below were derived by hand from GitHub's documented
// exclude/include semantics (see matrix-generator.test.ts for the isolated
// unit-level proof of that same algorithm) and cross-checked once locally
// before wiring up `act`; the act run here is what actually proves the
// *pipeline* — checkout, Bun install, script invocation — produces them.
// ---------------------------------------------------------------------------
interface PipelineCase {
  name: string;
  fixture: string;
  expectedSize: number;
  expectedFailFast: boolean;
  expectedMaxParallel: number;
  expectedInclude: Record<string, unknown>[];
}

const CASES: PipelineCase[] = [
  {
    name: "basic-exclude-and-standalone-include",
    fixture: "fixtures/scenario.json",
    expectedSize: 7,
    expectedFailFast: false,
    expectedMaxParallel: 3,
    expectedInclude: [
      { os: "ubuntu-latest", version: "18", coverage: true },
      { os: "ubuntu-latest", version: "18", coverage: false },
      { os: "ubuntu-latest", version: "20", coverage: true },
      { os: "ubuntu-latest", version: "20", coverage: false },
      { os: "windows-latest", version: "20", coverage: true },
      { os: "windows-latest", version: "20", coverage: false },
      { os: "macos-latest", version: "20", coverage: true, experimental: true },
    ],
  },
  {
    name: "multi-exclude-and-merging-include",
    fixture: "fixtures/rules.json",
    expectedSize: 4,
    expectedFailFast: true,
    expectedMaxParallel: 5,
    expectedInclude: [
      { os: "ubuntu-latest", version: "20", tier: "stable" },
      { os: "ubuntu-latest", version: "22", tier: "stable" },
      { os: "windows-latest", version: "20" },
      { os: "windows-latest", version: "22" },
    ],
  },
  {
    name: "two-independent-feature-flags",
    fixture: "fixtures/multi-flag.json",
    expectedSize: 16,
    expectedFailFast: true,
    expectedMaxParallel: 4,
    // Independently enumerated (not via cartesianProduct) so this is a real
    // second oracle, not a restatement of the implementation under test.
    expectedInclude: (() => {
      const rows: Record<string, unknown>[] = [];
      for (const os of ["ubuntu-latest", "windows-latest"]) {
        for (const version of ["18", "20"]) {
          for (const coverage of [true, false]) {
            for (const lint of [true, false]) {
              rows.push({ os, version, coverage, lint });
            }
          }
        }
      }
      return rows;
    })(),
  },
];

/** Build a throwaway git repo containing the project plus this case's fixture. */
function setupRepo(fixtureRelativePath: string): string {
  const dir = mkdtempSync(join(tmpdir(), "matrix-act-"));
  for (const relativePath of [
    "matrix-generator.ts",
    "format-summary.ts",
    "matrix-generator.test.ts",
    "cli.test.ts",
    "package.json",
    "bun.lock",
    "tsconfig.json",
    ".actrc",
    ".github",
    "fixtures",
  ]) {
    const src = join(PROJECT, relativePath);
    if (existsSync(src)) cpSync(src, join(dir, relativePath), { recursive: true });
  }
  // The workflow always reads fixtures/scenario.json; overwrite it with this
  // case's fixture so the workflow file itself never has to change.
  cpSync(join(PROJECT, fixtureRelativePath), join(dir, "fixtures/scenario.json"));

  const git = (args: string[]) =>
    Bun.spawnSync(["git", ...args], { cwd: dir, stdout: "pipe", stderr: "pipe" });
  git(["init", "-q"]);
  git(["config", "user.email", "test@example.com"]);
  git(["config", "user.name", "act-test-harness"]);
  git(["add", "-A"]);
  git(["commit", "-qm", "fixture snapshot"]);
  return dir;
}

/** Run `act push` for one case and return its combined output and exit code. */
function runActPush(dir: string): { output: string; code: number } {
  const proc = Bun.spawnSync(
    [
      "act",
      "push",
      "--rm",
      "--pull=false", // use the locally-built image; don't hit the registry.
      "-W",
      ".github/workflows/environment-matrix-generator.yml",
    ],
    { cwd: dir, stdout: "pipe", stderr: "pipe" },
  );
  const output =
    new TextDecoder().decode(proc.stdout) + new TextDecoder().decode(proc.stderr);
  return { output, code: proc.exitCode ?? -1 };
}

/** Extract the value of the last `KEY=...` line the summarize step printed. */
function extractField(output: string, key: string): string | null {
  const pattern = new RegExp(`${key}=(.*)`);
  const lines = output.split("\n");
  for (let i = lines.length - 1; i >= 0; i--) {
    const match = lines[i]?.match(pattern);
    if (match) return match[1]!.trim();
  }
  return null;
}

describe("workflow via act", () => {
  beforeAll(() => {
    writeFileSync(ACT_RESULT_PATH, "act-result.txt — environment-matrix-generator\n");
  });

  for (const testCase of CASES) {
    test(
      `case: ${testCase.name}`,
      () => {
        const repoDir = setupRepo(testCase.fixture);
        const result = runActPush(repoDir);

        appendFileSync(
          ACT_RESULT_PATH,
          `\n${"=".repeat(72)}\nCASE: ${testCase.name}\nFIXTURE: ${testCase.fixture}\nEXIT CODE: ${result.code}\n${"=".repeat(72)}\n${result.output}\n`,
        );
        rmSync(repoDir, { recursive: true, force: true });

        // 1. act itself must exit 0.
        expect(result.code).toBe(0);

        // 2. Both jobs must report success.
        const successCount = (result.output.match(/Job succeeded/g) ?? []).length;
        expect(successCount).toBe(2);
        expect(result.output).not.toMatch(/Job failed/);

        // 3. Exact values parsed from the real pipeline output.
        expect(extractField(result.output, "MATRIX_SIZE")).toBe(String(testCase.expectedSize));
        expect(extractField(result.output, "FAIL_FAST")).toBe(String(testCase.expectedFailFast));
        expect(extractField(result.output, "MAX_PARALLEL")).toBe(
          String(testCase.expectedMaxParallel),
        );
        const matrixJson = extractField(result.output, "MATRIX_JSON");
        expect(matrixJson).not.toBeNull();
        expect(JSON.parse(matrixJson as string)).toEqual(testCase.expectedInclude);
      },
      300_000, // act installs Bun and runs two jobs; give it plenty of room.
    );
  }
});
