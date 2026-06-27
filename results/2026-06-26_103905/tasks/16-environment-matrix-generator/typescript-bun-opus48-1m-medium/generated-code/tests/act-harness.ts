#!/usr/bin/env bun
/**
 * act-based integration harness.
 *
 * For each test case this harness:
 *   1. Creates a temp git repo containing the project files + that case's
 *      fixture config (written to fixtures/matrix.json, which the workflow reads).
 *   2. Runs `act push --rm` against the workflow inside that repo.
 *   3. Appends the full act output to act-result.txt (clearly delimited).
 *   4. Asserts act exited 0, every job reports "Job succeeded", and the
 *      generated matrix + fan-out build jobs match the EXACT expected values.
 *
 * Run with:  bun run tests/act-harness.ts
 */

import { spawnSync } from "node:child_process";
import { mkdtempSync, writeFileSync, appendFileSync, rmSync, cpSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const PROJECT_ROOT = join(import.meta.dir, "..");
const RESULT_FILE = join(PROJECT_ROOT, "act-result.txt");

interface TestCase {
  name: string;
  config: unknown;
  /** The exact `matrix.include` the generator must produce. */
  expectedInclude: Record<string, string | number | boolean>[];
  /** Exact BUILD report lines the fan-out jobs must emit. */
  expectedBuildLines: string[];
}

const CASES: TestCase[] = [
  {
    name: "basic-two-languages",
    config: {
      os: ["ubuntu-latest"],
      language: ["20", "22"],
      maxParallel: 2,
      failFast: false,
      maxSize: 10,
    },
    expectedInclude: [
      { os: "ubuntu-latest", language: "20" },
      { os: "ubuntu-latest", language: "22" },
    ],
    expectedBuildLines: [
      "BUILD os=ubuntu-latest language=20 feature=",
      "BUILD os=ubuntu-latest language=22 feature=",
    ],
  },
  {
    name: "exclude-and-include",
    config: {
      os: ["ubuntu-latest", "windows-latest"],
      language: ["18", "20"],
      exclude: [{ os: "windows-latest", language: "18" }],
      include: [{ os: "ubuntu-latest", language: "18", experimental: true }],
      failFast: false,
      maxSize: 10,
    },
    expectedInclude: [
      { os: "ubuntu-latest", language: "18", experimental: true },
      { os: "ubuntu-latest", language: "20" },
      { os: "windows-latest", language: "20" },
    ],
    expectedBuildLines: [
      "BUILD os=ubuntu-latest language=18 feature=",
      "BUILD os=ubuntu-latest language=20 feature=",
      "BUILD os=windows-latest language=20 feature=",
    ],
  },
  {
    name: "feature-flags",
    config: {
      os: ["ubuntu-latest"],
      language: ["20"],
      features: ["sqlite", "postgres"],
      failFast: false,
      maxSize: 10,
    },
    expectedInclude: [
      { os: "ubuntu-latest", language: "20", feature: "sqlite" },
      { os: "ubuntu-latest", language: "20", feature: "postgres" },
    ],
    expectedBuildLines: [
      "BUILD os=ubuntu-latest language=20 feature=sqlite",
      "BUILD os=ubuntu-latest language=20 feature=postgres",
    ],
  },
];

/** Strip act's `[Workflow/job] | ` line prefix to recover raw step output. */
function stripActPrefix(line: string): string {
  return line.replace(/^\[[^\]]*\]\s*\|\s?/, "");
}

/** Extract the matrix JSON printed between the START/END markers. */
function extractMatrixJson(output: string): unknown {
  const lines = output.split("\n").map(stripActPrefix);
  const start = lines.findIndex((l) => l.trim() === "MATRIX_OUTPUT_START");
  const end = lines.findIndex((l) => l.trim() === "MATRIX_OUTPUT_END");
  if (start === -1 || end === -1 || end <= start) {
    throw new Error("could not locate MATRIX_OUTPUT markers in act output");
  }
  const body = lines.slice(start + 1, end).join("\n");
  return JSON.parse(body);
}

function assert(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

function deepEqual(a: unknown, b: unknown): boolean {
  return JSON.stringify(a) === JSON.stringify(b);
}

/** Build a throwaway git repo for one test case and return its path. */
function setupRepo(testCase: TestCase): string {
  const dir = mkdtempSync(join(tmpdir(), `matrix-act-${testCase.name}-`));
  // Copy the files the workflow needs.
  for (const entry of ["src", "tests", "fixtures", ".github", "package.json", ".actrc"]) {
    cpSync(join(PROJECT_ROOT, entry), join(dir, entry), { recursive: true });
  }
  // Write this case's fixture as the file the workflow reads.
  writeFileSync(
    join(dir, "fixtures", "matrix.json"),
    JSON.stringify(testCase.config, null, 2),
  );
  // act's checkout needs a committed git repo.
  const git = (...args: string[]) =>
    spawnSync("git", args, { cwd: dir, encoding: "utf8" });
  git("init", "-q");
  git("config", "user.email", "ci@example.com");
  git("config", "user.name", "CI");
  git("add", "-A");
  git("commit", "-q", "-m", "test case");
  return dir;
}

function runActCase(testCase: TestCase): void {
  const dir = setupRepo(testCase);
  try {
    const result = spawnSync(
      "act",
      [
        "push",
        "--rm",
        "--pull=false",
        "-W",
        ".github/workflows/environment-matrix-generator.yml",
      ],
      { cwd: dir, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 },
    );
    const output = (result.stdout ?? "") + "\n" + (result.stderr ?? "");

    // 1. Persist the output, clearly delimited.
    appendFileSync(
      RESULT_FILE,
      `\n========================================================\n` +
        `TEST CASE: ${testCase.name}\n` +
        `act exit code: ${result.status}\n` +
        `--------------------------------------------------------\n` +
        output +
        `\n======================= END ${testCase.name} =======================\n`,
    );

    // 2. act must succeed.
    assert(result.status === 0, `[${testCase.name}] act exited ${result.status}, expected 0`);

    // 3. Every job must report success. The two jobs are `generate` and `build`.
    const succeeded = (output.match(/Job succeeded/g) ?? []).length;
    assert(
      succeeded >= 2,
      `[${testCase.name}] expected >=2 "Job succeeded", saw ${succeeded}`,
    );

    // 4. Exact matrix JSON. The generate job prints the full strategy object
    //    ({ matrix: { include: [...] }, ... }), so reach into `.matrix.include`.
    const strategy = extractMatrixJson(output) as {
      matrix: { include: unknown };
    };
    assert(
      deepEqual(strategy.matrix.include, testCase.expectedInclude),
      `[${testCase.name}] matrix.include mismatch.\n` +
        `  expected: ${JSON.stringify(testCase.expectedInclude)}\n` +
        `  actual:   ${JSON.stringify(strategy.matrix.include)}`,
    );

    // 5. Exact fan-out build lines (order-independent).
    const cleaned = output.split("\n").map(stripActPrefix);
    for (const expected of testCase.expectedBuildLines) {
      assert(
        cleaned.some((l) => l.includes(expected)),
        `[${testCase.name}] missing expected build line: "${expected}"`,
      );
    }

    console.log(`PASS  ${testCase.name}`);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

// Reset the result artifact at the start of a run.
writeFileSync(
  RESULT_FILE,
  `act integration results - environment-matrix-generator\n`,
);

let failures = 0;
for (const testCase of CASES) {
  try {
    runActCase(testCase);
  } catch (err) {
    failures++;
    console.error(`FAIL  ${testCase.name}: ${(err as Error).message}`);
    appendFileSync(RESULT_FILE, `\nASSERTION FAILURE: ${(err as Error).message}\n`);
  }
}

console.log(`\n${CASES.length - failures}/${CASES.length} act cases passed`);
if (failures > 0) process.exit(1);
