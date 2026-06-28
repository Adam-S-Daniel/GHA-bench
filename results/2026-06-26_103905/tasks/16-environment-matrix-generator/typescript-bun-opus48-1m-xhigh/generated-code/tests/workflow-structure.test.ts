import { describe, expect, test } from "bun:test";
import { existsSync } from "node:fs";
import { join } from "node:path";

// ---------------------------------------------------------------------------
// Workflow structure tests.
//
// These parse the workflow YAML with Bun's built-in YAML parser and assert the
// structure the rest of the system relies on (triggers, permissions, jobs,
// dependencies, and that the steps reference real script files). They also run
// actionlint and require a clean exit. None of this touches Docker, so it is
// fast and part of the normal `bun test` run.
// ---------------------------------------------------------------------------
const ROOT = join(import.meta.dir, "..");
const WORKFLOW = join(ROOT, ".github", "workflows", "environment-matrix-generator.yml");

// Parsed once and shared across the assertions below.
const text = await Bun.file(WORKFLOW).text();
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const wf = Bun.YAML.parse(text) as any;

describe("workflow triggers", () => {
  test("declares push, pull_request, schedule and workflow_dispatch", () => {
    // YAML's `on:` key is preserved as the string "on" by Bun's parser.
    const triggers = wf["on"];
    expect(Object.keys(triggers).sort()).toEqual([
      "pull_request",
      "push",
      "schedule",
      "workflow_dispatch",
    ]);
  });

  test("schedule uses a valid weekly cron", () => {
    expect(wf["on"].schedule).toEqual([{ cron: "0 6 * * 1" }]);
  });
});

describe("workflow permissions and env", () => {
  test("grants least-privilege read access to contents", () => {
    expect(wf.permissions).toEqual({ contents: "read" });
  });

  test("declares the config-file environment variable", () => {
    expect(wf.env.MATRIX_CONFIG_FILE).toBe("matrix-config.json");
  });
});

describe("workflow jobs", () => {
  test("defines generate-matrix, build and summary jobs", () => {
    expect(Object.keys(wf.jobs)).toEqual([
      "generate-matrix",
      "build",
      "summary",
    ]);
  });

  test("generate-matrix checks out the repo and runs the generator", () => {
    const steps = wf.jobs["generate-matrix"].steps as Array<Record<string, string>>;
    const uses = steps.map((s) => s.uses).filter(Boolean);
    expect(uses).toContain("actions/checkout@v4");

    // Some step must invoke the generator script by its real path.
    const runs = steps.map((s) => s.run ?? "").join("\n");
    expect(runs).toContain("src/generate.ts");
    expect(runs).toContain("bun");
  });

  test("generate-matrix exposes the matrix as a job output", () => {
    const outputs = wf.jobs["generate-matrix"].outputs;
    expect(outputs.matrix).toBe("${{ steps.generate.outputs.matrix }}");
    expect(outputs.count).toBe("${{ steps.generate.outputs.count }}");
  });

  test("build depends on generate-matrix and consumes the dynamic matrix", () => {
    const build = wf.jobs.build;
    expect(build.needs).toBe("generate-matrix");
    expect(build.strategy.matrix).toBe(
      "${{ fromJson(needs.generate-matrix.outputs.matrix) }}",
    );
  });

  test("summary depends on both prior jobs (fan-in)", () => {
    expect(wf.jobs.summary.needs).toEqual(["generate-matrix", "build"]);
  });
});

describe("referenced files exist on disk", () => {
  test("the scripts the workflow runs are present", () => {
    for (const rel of [
      "src/generate.ts",
      "src/matrix.ts",
      "src/cli.ts",
      "src/types.ts",
      "tests/matrix.test.ts",
      "tests/cli.test.ts",
    ]) {
      expect(existsSync(join(ROOT, rel))).toBe(true);
    }
  });
});

describe("actionlint", () => {
  test("the workflow passes actionlint cleanly (exit 0)", () => {
    const proc = Bun.spawnSync(["actionlint", WORKFLOW]);
    if (proc.exitCode !== 0) {
      // Surface actionlint's diagnostics in the test failure message.
      throw new Error(
        `actionlint failed (exit ${proc.exitCode}):\n` +
          proc.stdout.toString() +
          proc.stderr.toString(),
      );
    }
    expect(proc.exitCode).toBe(0);
  });
});
