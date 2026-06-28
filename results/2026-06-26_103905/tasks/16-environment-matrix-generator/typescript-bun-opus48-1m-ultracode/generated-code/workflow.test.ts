/**
 * Workflow tests for the Environment Matrix Generator.
 *
 * Two groups:
 *   1. "Workflow structure" — fast, offline checks that parse the YAML and
 *      assert the expected triggers/permissions/jobs/steps, that the workflow
 *      references real script + fixture files, and that `actionlint` passes.
 *   2. "act integration" — the mandatory end-to-end harness. For each test
 *      case it builds a throwaway git repo containing the project files + that
 *      case's fixture, runs the workflow with `act push --rm`, appends the full
 *      output to `act-result.txt`, asserts act exited 0 and every job
 *      succeeded, and asserts the parsed output matches the EXACT known-good
 *      values for that fixture.
 *
 * Per the task constraints the whole suite is exercised through `act`; the pure
 * logic is additionally unit-tested in matrix-generator.test.ts.
 */
import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import {
  cpSync,
  existsSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const PROJECT_DIR = import.meta.dir;
const WORKFLOW_PATH = join(PROJECT_DIR, ".github/workflows/environment-matrix-generator.yml");
const ACT_RESULT_PATH = join(PROJECT_DIR, "act-result.txt");

/* -------------------------------------------------------------------------- */
/* 1. Workflow structure tests                                                 */
/* -------------------------------------------------------------------------- */

describe("Workflow structure", () => {
  const raw = readFileSync(WORKFLOW_PATH, "utf8");
  // Bun's YAML parser preserves the literal "on" key (it is not coerced to the
  // boolean true), but we guard for both just in case.
  const wf = Bun.YAML.parse(raw) as Record<string, any>;
  const triggers = (wf.on ?? wf[true as unknown as string]) as Record<string, unknown>;

  test("declares the expected trigger events", () => {
    expect(triggers).toBeDefined();
    expect(Object.keys(triggers)).toEqual(
      expect.arrayContaining(["push", "pull_request", "workflow_dispatch", "schedule"]),
    );
  });

  test("workflow_dispatch exposes a 'config' input with a fixture default", () => {
    const input = (triggers.workflow_dispatch as any).inputs.config;
    expect(input).toBeDefined();
    expect(input.default).toBe("fixtures/basic.config.json");
  });

  test("schedule uses a valid 5-field cron", () => {
    const cron = (triggers.schedule as any[])[0].cron as string;
    expect(cron.trim().split(/\s+/)).toHaveLength(5);
  });

  test("sets least-privilege permissions", () => {
    expect(wf.permissions).toEqual({ contents: "read" });
  });

  test("defines the generate-matrix and report jobs with a dependency", () => {
    expect(Object.keys(wf.jobs)).toEqual(
      expect.arrayContaining(["generate-matrix", "report"]),
    );
    expect(wf.jobs.report.needs).toBe("generate-matrix");
  });

  test("generate-matrix exposes matrix/size/within-limit outputs", () => {
    const outputs = wf.jobs["generate-matrix"].outputs;
    expect(Object.keys(outputs)).toEqual(
      expect.arrayContaining(["matrix", "size", "within-limit"]),
    );
  });

  test("uses pinned, valid action references (checkout + setup-bun)", () => {
    const steps = wf.jobs["generate-matrix"].steps as Array<{ uses?: string }>;
    const uses = steps.map((s) => s.uses).filter(Boolean);
    expect(uses).toContain("actions/checkout@v4");
    expect(uses).toContain("oven-sh/setup-bun@v2");
  });

  test("references the generator script, which exists on disk", () => {
    expect(raw).toContain("matrix-generator.ts");
    expect(existsSync(join(PROJECT_DIR, "matrix-generator.ts"))).toBe(true);
  });

  test("every fixture referenced by the workflow exists on disk", () => {
    // The default fixture plus the ones the harness feeds in.
    for (const fixture of [
      "fixtures/basic.config.json",
      "fixtures/exclude-include.config.json",
      "fixtures/over-limit.config.json",
    ]) {
      expect(existsSync(join(PROJECT_DIR, fixture))).toBe(true);
    }
  });

  test("passes actionlint with exit code 0", () => {
    const result = Bun.spawnSync(["actionlint", WORKFLOW_PATH]);
    const combined = result.stdout.toString() + result.stderr.toString();
    expect(combined).toBe("");
    expect(result.exitCode).toBe(0);
  });
});

/* -------------------------------------------------------------------------- */
/* 2. act integration harness                                                  */
/* -------------------------------------------------------------------------- */

/** One end-to-end case: a fixture + the exact values the workflow must emit. */
interface ActCase {
  name: string;
  fixture: string;
  expected: {
    size: number;
    withinLimit: "true" | "false";
    maxSize: number;
    failFast: "true" | "false";
    maxParallel: string; // numeric string or "none"
    includeCount: number;
    include: Array<Record<string, unknown>>;
  };
}

const ACT_CASES: ActCase[] = [
  {
    name: "basic",
    fixture: "fixtures/basic.config.json",
    expected: {
      size: 6,
      withinLimit: "true",
      maxSize: 256,
      failFast: "true",
      maxParallel: "none",
      includeCount: 6,
      include: [
        { os: "ubuntu-latest", node: "18" },
        { os: "ubuntu-latest", node: "20" },
        { os: "windows-latest", node: "18" },
        { os: "windows-latest", node: "20" },
        { os: "macos-latest", node: "18" },
        { os: "macos-latest", node: "20" },
      ],
    },
  },
  {
    name: "exclude-include",
    fixture: "fixtures/exclude-include.config.json",
    expected: {
      size: 10,
      withinLimit: "true",
      maxSize: 100,
      failFast: "false",
      maxParallel: "4",
      includeCount: 10,
      include: [
        { os: "ubuntu-latest", node: "18", feature: "minimal" },
        { os: "ubuntu-latest", node: "20", feature: "minimal" },
        { os: "ubuntu-latest", node: "20", feature: "full" },
        { os: "ubuntu-latest", node: "22", feature: "minimal" },
        { os: "ubuntu-latest", node: "22", feature: "full" },
        { os: "windows-latest", node: "20", feature: "minimal" },
        { os: "windows-latest", node: "20", feature: "full" },
        { os: "windows-latest", node: "22", feature: "minimal" },
        { os: "windows-latest", node: "22", feature: "full" },
        { os: "macos-latest", node: "22", feature: "full", experimental: true },
      ],
    },
  },
  {
    name: "over-limit",
    fixture: "fixtures/over-limit.config.json",
    expected: {
      size: 9,
      withinLimit: "false", // exceeds max-size=4, reported (not fatal in non-strict)
      maxSize: 4,
      failFast: "true",
      maxParallel: "none",
      includeCount: 9,
      include: [
        { os: "ubuntu-latest", node: "16" },
        { os: "ubuntu-latest", node: "18" },
        { os: "ubuntu-latest", node: "20" },
        { os: "windows-latest", node: "16" },
        { os: "windows-latest", node: "18" },
        { os: "windows-latest", node: "20" },
        { os: "macos-latest", node: "16" },
        { os: "macos-latest", node: "18" },
        { os: "macos-latest", node: "20" },
      ],
    },
  },
];

/** Strip ANSI escape sequences so output parsing is robust. */
function stripAnsi(text: string): string {
  // eslint-disable-next-line no-control-regex
  return text.replace(/\[[0-9;]*m/g, "");
}

/** Pull a single-token `KEY=value` value out of (prefixed) act output. */
function extractValue(output: string, key: string): string | undefined {
  const match = output.match(new RegExp(`\\b${key}=(\\S+)`));
  return match ? match[1] : undefined;
}

/** Files/dirs copied into each throwaway repo (no node_modules needed). */
const COPY_ENTRIES = [
  "matrix-generator.ts",
  "package.json",
  "tsconfig.json",
  "fixtures",
  ".github",
  ".actrc",
];

/** Build a temp git repo with the project + run the workflow via act. */
function runActCase(testCase: ActCase): { output: string; exitCode: number } {
  const repo = mkdtempSync(join(tmpdir(), `act-matrix-${testCase.name}-`));
  try {
    for (const entry of COPY_ENTRIES) {
      const src = join(PROJECT_DIR, entry);
      if (existsSync(src)) cpSync(src, join(repo, entry), { recursive: true });
    }

    // act needs a committed git repo to derive the push event from.
    const git = (args: string[]) =>
      Bun.spawnSync(["git", ...args], { cwd: repo, stdout: "pipe", stderr: "pipe" });
    git(["init", "-q"]);
    git(["config", "user.email", "test@example.com"]);
    git(["config", "user.name", "Matrix Test"]);
    git(["add", "-A"]);
    git(["commit", "-q", "-m", `fixture: ${testCase.name}`]);

    // --pull=false: all images are local; the custom act image is registry-less.
    const proc = Bun.spawnSync(
      [
        "act",
        "push",
        "--rm",
        "--pull=false",
        "--env",
        `CONFIG_FILE=${testCase.fixture}`,
        "-W",
        ".github/workflows/environment-matrix-generator.yml",
      ],
      { cwd: repo, stdout: "pipe", stderr: "pipe" },
    );

    const output = stripAnsi(proc.stdout.toString() + "\n" + proc.stderr.toString());
    return { output, exitCode: proc.exitCode ?? -1 };
  } finally {
    rmSync(repo, { recursive: true, force: true });
  }
}

describe("act integration (end-to-end pipeline)", () => {
  beforeAll(() => {
    // Start a fresh artifact for this harness run.
    writeFileSync(
      ACT_RESULT_PATH,
      `Environment Matrix Generator — act run results\nGenerated by workflow.test.ts\n`,
    );
  });

  afterAll(() => {
    // The artifact must exist when the suite finishes.
    expect(existsSync(ACT_RESULT_PATH)).toBe(true);
  });

  for (const testCase of ACT_CASES) {
    test(
      `runs '${testCase.name}' through act and emits the exact expected matrix`,
      () => {
        const { output, exitCode } = runActCase(testCase);

        // Persist the full output, clearly delimited, before asserting.
        const block =
          `\n${"=".repeat(78)}\n` +
          `CASE: ${testCase.name}  (CONFIG_FILE=${testCase.fixture})\n` +
          `act exit code: ${exitCode}\n` +
          `${"-".repeat(78)}\n` +
          `${output}\n`;
        require("node:fs").appendFileSync(ACT_RESULT_PATH, block);

        // act must succeed.
        expect(exitCode).toBe(0);

        // Both jobs (generate-matrix + report) must report success.
        const succeeded = (output.match(/Job succeeded/g) ?? []).length;
        expect(succeeded).toBeGreaterThanOrEqual(2);

        // Exact value assertions parsed from the workflow's emitted lines.
        expect(extractValue(output, "MATRIX_SIZE")).toBe(String(testCase.expected.size));
        expect(extractValue(output, "WITHIN_LIMIT")).toBe(testCase.expected.withinLimit);
        expect(extractValue(output, "MAX_SIZE")).toBe(String(testCase.expected.maxSize));
        expect(extractValue(output, "FAIL_FAST")).toBe(testCase.expected.failFast);
        expect(extractValue(output, "MAX_PARALLEL")).toBe(testCase.expected.maxParallel);
        expect(extractValue(output, "INCLUDE_COUNT")).toBe(
          String(testCase.expected.includeCount),
        );

        // The exact, fully-expanded include array (compact, single line).
        const includeJson = extractValue(output, "INCLUDE_JSON");
        expect(includeJson).toBeDefined();
        expect(JSON.parse(includeJson as string)).toEqual(testCase.expected.include);

        // The downstream report job consumed the same matrix.
        expect(extractValue(output, "REPORT_SIZE")).toBe(String(testCase.expected.size));
        expect(extractValue(output, "REPORT_INCLUDE_COUNT")).toBe(
          String(testCase.expected.includeCount),
        );
        expect(extractValue(output, "REPORT_WITHIN_LIMIT")).toBe(
          testCase.expected.withinLimit,
        );
      },
      240_000, // act needs time to boot a container and install Bun.
    );
  }
});
