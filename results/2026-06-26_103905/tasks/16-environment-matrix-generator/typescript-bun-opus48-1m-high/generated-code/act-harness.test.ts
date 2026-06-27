// act harness.
//
// This is the end-to-end test required by the task: every matrix-generation
// case is exercised THROUGH the GitHub Actions workflow via `act` (not by
// calling the script directly). We:
//   1. Build a temp git repo containing the project files + all fixtures.
//   2. Run `act push --rm` ONCE (the workflow loops over every fixture, so a
//      single act run covers all cases — well within the 3-run budget).
//   3. Save the full act output to act-result.txt (a required artifact).
//   4. Assert act exited 0.
//   5. Parse the output and assert EXACT expected values for each fixture.
//   6. Assert every job shows "Job succeeded".
import { test, expect, beforeAll } from "bun:test";
import { mkdtempSync, mkdirSync, copyFileSync, readdirSync, writeFileSync, appendFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const PROJECT_DIR = process.cwd();
const ACT_RESULT = join(PROJECT_DIR, "act-result.txt");

// Known-good expected results for each fixture (the "green truth" the act
// pipeline output is asserted against). These mirror the unit-tested logic
// but are pinned here independently so the pipeline output is verified
// against concrete numbers, not just "some number appeared".
interface Expectation {
  count: number;
  // substrings that MUST appear in that fixture's MATRIX_JSON line
  jsonContains: string[];
  // substrings that must NOT appear in that fixture's MATRIX_JSON line
  jsonExcludes?: string[];
}
const EXPECTED: Record<string, Expectation> = {
  "01-basic.json": {
    count: 9,
    jsonContains: ['{"os":"ubuntu-latest","language":"18"}', '{"os":"macos-latest","language":"22"}'],
  },
  "02-exclude.json": {
    count: 5,
    jsonContains: ['{"os":"windows-latest","language":"20"}'],
    // windows+18 was excluded; macos never existed.
    jsonExcludes: ['{"os":"windows-latest","language":"18"}', '"macos-latest"'],
  },
  "03-include.json": {
    count: 3,
    jsonContains: [
      '{"os":"ubuntu-latest","language":"20","experimental":true}',
      '{"os":"macos-latest","language":"22"}',
    ],
  },
  "04-features.json": {
    count: 2,
    jsonContains: [
      '{"os":"ubuntu-latest","language":"20","features":"minimal"}',
      '{"os":"ubuntu-latest","language":"20","features":"full"}',
    ],
  },
  "05-include-only.json": {
    count: 2,
    jsonContains: ['"arch":"x64"', '"arch":"arm64"'],
  },
};

// Files the workflow needs to run inside the container.
const PROJECT_FILES = [
  "cli.ts",
  "matrix-generator.ts",
  "package.json",
  "matrix-generator.test.ts",
  "cli.test.ts",
  ".actrc",
];

let actOutput = "";
let actExit = -1;

/** Recursively run git/act commands, returning combined stdout+stderr. */
function run(cmd: string[], cwd: string): { code: number; out: string } {
  const proc = Bun.spawnSync(cmd, { cwd, stdout: "pipe", stderr: "pipe" });
  const out =
    new TextDecoder().decode(proc.stdout) + new TextDecoder().decode(proc.stderr);
  return { code: proc.exitCode ?? -1, out };
}

beforeAll(() => {
  // 1. Assemble a clean temp git repo with exactly the files the pipeline uses.
  const tmp = mkdtempSync(join(tmpdir(), "matrix-act-"));
  for (const f of PROJECT_FILES) {
    copyFileSync(join(PROJECT_DIR, f), join(tmp, f));
  }
  // fixtures/
  mkdirSync(join(tmp, "fixtures"));
  for (const f of readdirSync(join(PROJECT_DIR, "fixtures"))) {
    copyFileSync(join(PROJECT_DIR, "fixtures", f), join(tmp, "fixtures", f));
  }
  // .github/workflows/
  mkdirSync(join(tmp, ".github", "workflows"), { recursive: true });
  copyFileSync(
    join(PROJECT_DIR, ".github", "workflows", "environment-matrix-generator.yml"),
    join(tmp, ".github", "workflows", "environment-matrix-generator.yml"),
  );

  // 2. Initialise the git repo (act needs a committed tree).
  run(["git", "init", "-q", "-b", "main"], tmp);
  run(["git", "config", "user.email", "ci@example.com"], tmp);
  run(["git", "config", "user.name", "CI"], tmp);
  run(["git", "add", "-A"], tmp);
  run(["git", "commit", "-q", "-m", "init"], tmp);

  // 3. Run the pipeline once. --rm cleans up the container afterwards;
  //    --pull=false uses the locally-built act image instead of force-pulling
  //    (the image is provided locally, a remote pull would fail auth).
  const result = run(["act", "push", "--rm", "--pull=false"], tmp);
  actOutput = result.out;
  actExit = result.code;

  // 4. Persist the artifact (required by the task).
  writeFileSync(
    ACT_RESULT,
    `==== act push --rm (all fixtures) ====\nexit code: ${actExit}\n\n${actOutput}\n`,
  );
  // Append a per-fixture, clearly-delimited breakdown for easy inspection.
  for (const name of Object.keys(EXPECTED)) {
    const section = extractFixtureSection(actOutput, name);
    appendFileSync(
      ACT_RESULT,
      `\n---- fixture: ${name} ----\n${section || "(section not found)"}\n`,
    );
  }
}, 600_000); // act can take 30-90s; well under this generous timeout.

/** Pull the lines emitted between this fixture's START/END markers. */
function extractFixtureSection(output: string, name: string): string {
  const startIdx = output.indexOf(`FIXTURE_START ${name}`);
  const endIdx = output.indexOf(`FIXTURE_END ${name}`);
  if (startIdx === -1 || endIdx === -1) return "";
  return output.slice(startIdx, endIdx);
}

test("act exited with code 0", () => {
  expect(actExit).toBe(0);
});

test("act-result.txt artifact was written", () => {
  expect(require("node:fs").existsSync(ACT_RESULT)).toBe(true);
});

test("every job shows 'Job succeeded' (validate + generate)", () => {
  const matches = actOutput.match(/Job succeeded/g) ?? [];
  // Two jobs in the workflow must both succeed.
  expect(matches.length).toBeGreaterThanOrEqual(2);
});

test("unit tests ran inside the pipeline (validate job)", () => {
  // bun test prints a pass summary; assert the generator tests ran in-container.
  expect(actOutput).toContain("matrix-generator.test.ts");
});

// One assertion block PER fixture/test-case: exact count + exact JSON content,
// all parsed from the act pipeline output.
for (const [name, exp] of Object.entries(EXPECTED)) {
  test(`fixture ${name}: pipeline produced exactly count=${exp.count} with expected combos`, () => {
    const section = extractFixtureSection(actOutput, name);
    expect(section.length).toBeGreaterThan(0);

    // Exact count marker.
    expect(section).toContain(`MTX_COUNT=${exp.count}`);

    // Locate this fixture's MTX_JSON marker line.
    const jsonLine = section
      .split("\n")
      .find((l) => l.includes("MTX_JSON="));
    expect(jsonLine).toBeDefined();
    const json = jsonLine!.slice(jsonLine!.indexOf("MTX_JSON=") + "MTX_JSON=".length);

    // The JSON must be parseable and have exactly `count` entries.
    const combos = JSON.parse(json.trim());
    expect(Array.isArray(combos)).toBe(true);
    expect(combos).toHaveLength(exp.count);

    for (const needle of exp.jsonContains) {
      expect(json).toContain(needle);
    }
    for (const needle of exp.jsonExcludes ?? []) {
      expect(json).not.toContain(needle);
    }
  });
}
