// Workflow tests: (1) static structure / actionlint checks and (2) end-to-end
// execution of the GitHub Actions workflow through `act` in Docker.
//
// The act-integration tests build a throwaway git repo per test case, overwrite
// the `fixtures/` data with that case's inputs, run `act push`, capture the full
// output to `act-result.txt`, and assert on EXACT expected report values.
//
// NOTE: these tests require `act` + Docker (pre-installed in the benchmark
// environment). They are slow (each spins up containers), so generous per-test
// timeouts are set.

import { test, expect, describe, beforeAll } from "bun:test";
import { parse as parseYaml } from "yaml";
import { spawnSync } from "node:child_process";
import {
  mkdtempSync,
  writeFileSync,
  appendFileSync,
  cpSync,
  rmSync,
  existsSync,
  readFileSync,
  mkdirSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const PROJECT_DIR: string = import.meta.dir;
const WORKFLOW_REL = ".github/workflows/dependency-license-checker.yml";
const WORKFLOW_PATH = join(PROJECT_DIR, WORKFLOW_REL);
const ACT_RESULT = join(PROJECT_DIR, "act-result.txt");
const ACT_IMAGE = "act-ubuntu-pwsh:latest";

// ---------------------------------------------------------------------------
// 1. Workflow structure / static validation
// ---------------------------------------------------------------------------

describe("workflow structure", () => {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let doc: any;
  let rawYaml: string;

  beforeAll(() => {
    rawYaml = readFileSync(WORKFLOW_PATH, "utf8");
    doc = parseYaml(rawYaml);
  });

  test("declares the expected trigger events", () => {
    const triggers = Object.keys(doc.on);
    expect(triggers).toContain("push");
    expect(triggers).toContain("pull_request");
    expect(triggers).toContain("schedule");
    expect(triggers).toContain("workflow_dispatch");
  });

  test("declares least-privilege permissions", () => {
    expect(doc.permissions).toEqual({ contents: "read" });
  });

  test("defines the unit-test and compliance jobs with a dependency edge", () => {
    expect(Object.keys(doc.jobs)).toEqual(["unit-tests", "license-compliance"]);
    expect(doc.jobs["license-compliance"].needs).toBe("unit-tests");
  });

  test("uses pinned, valid action references", () => {
    const steps = [
      ...doc.jobs["unit-tests"].steps,
      ...doc.jobs["license-compliance"].steps,
    ];
    const uses = steps.map((s: { uses?: string }) => s.uses).filter(Boolean);
    expect(uses).toContain("actions/checkout@v4");
    expect(uses).toContain("oven-sh/setup-bun@v2");
  });

  test("references the checker script and its inputs, and they exist on disk", () => {
    // The workflow must invoke the real script with the fixture paths.
    expect(rawYaml).toContain("bun run license-checker.ts");
    expect(rawYaml).toContain("bun test license-checker.test.ts");
    for (const f of [
      "license-checker.ts",
      "license-checker.test.ts",
      "fixtures/package.json",
      "fixtures/config.json",
      "fixtures/licenses.json",
    ]) {
      expect(existsSync(join(PROJECT_DIR, f))).toBe(true);
    }
  });

  test("passes actionlint with exit code 0", () => {
    const res = spawnSync("actionlint", [WORKFLOW_PATH], { encoding: "utf8" });
    if (res.status !== 0) {
      console.error(res.stdout, res.stderr);
    }
    expect(res.status).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// 2. End-to-end execution through `act`
// ---------------------------------------------------------------------------

/** Inputs for one act test case. */
interface ActCase {
  name: string;
  pkg: unknown;
  config: unknown;
  licenses: unknown;
}

/** Result of running one act case. */
interface ActRun {
  code: number;
  output: string;
}

/**
 * Build an isolated git repo containing the project + this case's fixtures,
 * run `act push`, and return the exit code + combined output.
 */
function runActCase(c: ActCase): ActRun {
  const tmp = mkdtempSync(join(tmpdir(), "license-act-"));
  try {
    // Copy the project files needed to run the workflow (NOT this test file,
    // node_modules, or the original fixtures).
    for (const f of [
      "license-checker.ts",
      "license-checker.test.ts",
      "package.json",
      "tsconfig.json",
      "bun.lock",
      ".gitignore",
      ".actrc",
    ]) {
      const src = join(PROJECT_DIR, f);
      if (existsSync(src)) cpSync(src, join(tmp, f));
    }
    cpSync(join(PROJECT_DIR, ".github"), join(tmp, ".github"), { recursive: true });

    // Write this case's fixture data, overriding the committed defaults.
    mkdirSync(join(tmp, "fixtures"), { recursive: true });
    writeFileSync(join(tmp, "fixtures/package.json"), JSON.stringify(c.pkg, null, 2));
    writeFileSync(join(tmp, "fixtures/config.json"), JSON.stringify(c.config, null, 2));
    writeFileSync(join(tmp, "fixtures/licenses.json"), JSON.stringify(c.licenses, null, 2));

    // act's `push` event needs a committed git repo.
    const git = (args: string[]) =>
      spawnSync("git", args, { cwd: tmp, encoding: "utf8" });
    git(["init", "-q", "-b", "main"]);
    git(["config", "user.email", "test@example.com"]);
    git(["config", "user.name", "act-test"]);
    git(["add", "-A"]);
    git(["commit", "-q", "-m", "license checker fixture"]);

    // Run the workflow. `--pull=false` uses the locally-built image; `-P` maps
    // ubuntu-latest to it explicitly (matches the workspace .actrc).
    const res = spawnSync(
      "act",
      [
        "push",
        "--rm",
        "--pull=false",
        "-P",
        `ubuntu-latest=${ACT_IMAGE}`,
        "-W",
        WORKFLOW_REL,
      ],
      {
        cwd: tmp,
        encoding: "utf8",
        timeout: 280_000,
        maxBuffer: 64 * 1024 * 1024,
      },
    );
    const output = `${res.stdout ?? ""}${res.stderr ?? ""}`;
    const code = res.status === null ? 1 : res.status;
    return { code, output };
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
}

/** Append one case's full output to the required act-result.txt artifact. */
function recordResult(name: string, run: ActRun): void {
  const block = [
    "=".repeat(72),
    `TEST CASE: ${name}`,
    `ACT EXIT CODE: ${run.code}`,
    "-".repeat(72),
    run.output.trimEnd(),
    "",
  ].join("\n");
  appendFileSync(ACT_RESULT, block + "\n");
}

describe("act integration", () => {
  beforeAll(() => {
    // Start a fresh artifact for this run.
    writeFileSync(
      ACT_RESULT,
      `Dependency License Checker - act run log\nGenerated by workflow.test.ts\n\n`,
    );
  });

  test(
    "mixed manifest: approved + denied + unknown, job succeeds, exact report",
    () => {
      const run = runActCase({
        name: "mixed",
        pkg: {
          name: "mixed-fixture",
          version: "1.0.0",
          dependencies: { "left-pad": "1.3.0", "copyleft-lib": "2.0.0" },
          devDependencies: { "mystery-lib": "0.1.0" },
        },
        config: {
          allow: ["MIT", "Apache-2.0", "BSD-3-Clause"],
          deny: ["GPL-3.0", "AGPL-3.0"],
        },
        licenses: { "left-pad": "MIT", "copyleft-lib": "GPL-3.0" },
      });
      recordResult("mixed", run);

      expect(run.code).toBe(0);
      // Exact per-dependency statuses.
      expect(run.output).toContain("[APPROVED] left-pad@1.3.0 (MIT)");
      expect(run.output).toContain("[DENIED] copyleft-lib@2.0.0 (GPL-3.0)");
      expect(run.output).toContain("[UNKNOWN] mystery-lib@0.1.0 (no license found)");
      // Exact summary + verdict.
      expect(run.output).toContain("SUMMARY total=3 approved=1 denied=1 unknown=1");
      expect(run.output).toContain("RESULT NON-COMPLIANT");
      // Both jobs succeeded.
      const succeeded = (run.output.match(/Job succeeded/g) ?? []).length;
      expect(succeeded).toBeGreaterThanOrEqual(2);
    },
    300_000,
  );

  test(
    "all-approved manifest: compliant, job succeeds, exact report",
    () => {
      const run = runActCase({
        name: "all-approved",
        pkg: {
          name: "clean-fixture",
          version: "2.1.0",
          dependencies: { alpha: "1.0.0", beta: "2.0.0" },
        },
        config: { allow: ["MIT", "Apache-2.0"], deny: ["GPL-3.0"] },
        licenses: { alpha: "MIT", beta: "Apache-2.0" },
      });
      recordResult("all-approved", run);

      expect(run.code).toBe(0);
      expect(run.output).toContain("[APPROVED] alpha@1.0.0 (MIT)");
      expect(run.output).toContain("[APPROVED] beta@2.0.0 (Apache-2.0)");
      expect(run.output).toContain("SUMMARY total=2 approved=2 denied=0 unknown=0");
      expect(run.output).toContain("RESULT COMPLIANT");
      const succeeded = (run.output.match(/Job succeeded/g) ?? []).length;
      expect(succeeded).toBeGreaterThanOrEqual(2);
    },
    300_000,
  );
});
