/**
 * Workflow-structure tests. These do NOT run act (that is the job of the act
 * harness in harness/run-act.ts); they statically validate that the workflow
 * YAML has the expected shape, references real script paths, and passes
 * actionlint. They are fast and run as part of `bun test`.
 */
import { describe, expect, it, beforeAll } from "bun:test";
import { existsSync } from "node:fs";

const ROOT = new URL("../", import.meta.url).pathname;
const WORKFLOW = ROOT + ".github/workflows/test-results-aggregator.yml";

let yaml = "";
beforeAll(async () => {
  yaml = await Bun.file(WORKFLOW).text();
});

describe("workflow triggers", () => {
  it("the workflow file exists", () => {
    expect(existsSync(WORKFLOW)).toBe(true);
  });

  it("declares push, pull_request, schedule, and workflow_dispatch triggers", () => {
    // Restrict the search to the `on:` block (everything before `permissions:`).
    const onBlock = yaml.slice(yaml.indexOf("on:"), yaml.indexOf("permissions:"));
    expect(onBlock).toContain("push:");
    expect(onBlock).toContain("pull_request:");
    expect(onBlock).toContain("schedule:");
    expect(onBlock).toContain("workflow_dispatch:");
    expect(onBlock).toMatch(/cron:\s*'[^']+'/);
  });
});

describe("workflow permissions and env", () => {
  it("sets least-privilege contents: read permission", () => {
    expect(yaml).toMatch(/permissions:\s*\n\s*contents:\s*read/);
  });

  it("defines the RESULTS_DIR environment variable", () => {
    expect(yaml).toMatch(/env:\s*\n\s*RESULTS_DIR:/);
  });
});

describe("workflow jobs and dependencies", () => {
  it("defines unit-tests and aggregate jobs", () => {
    expect(yaml).toMatch(/^\s{2}unit-tests:/m);
    expect(yaml).toMatch(/^\s{2}aggregate:/m);
  });

  it("makes aggregate depend on unit-tests", () => {
    expect(yaml).toMatch(/needs:\s*unit-tests/);
  });

  it("runs on ubuntu-latest", () => {
    expect(yaml).toContain("runs-on: ubuntu-latest");
  });
});

describe("workflow steps reference real actions and scripts", () => {
  it("uses actions/checkout@v4", () => {
    expect(yaml).toContain("actions/checkout@v4");
  });

  it("uses oven-sh/setup-bun@v2", () => {
    expect(yaml).toContain("oven-sh/setup-bun@v2");
  });

  it("runs the unit test suite", () => {
    expect(yaml).toContain("bun test");
  });

  it("invokes the aggregator entry script", () => {
    expect(yaml).toMatch(/bun run src\/index\.ts/);
  });

  it("the referenced script paths exist on disk", () => {
    expect(existsSync(ROOT + "src/index.ts")).toBe(true);
    expect(existsSync(ROOT + "src/loader.ts")).toBe(true);
    expect(existsSync(ROOT + "fixtures")).toBe(true);
  });
});

describe("actionlint validation", () => {
  // actionlint is a host dev tool; it is not installed inside the act CI
  // container. Skip the assertion there so `bun test` passes both on the host
  // (where it genuinely lints) and inside the workflow's own test job.
  const hasActionlint = Bun.which("actionlint") !== null;

  it.skipIf(!hasActionlint)("passes actionlint with exit code 0", async () => {
    const proc = Bun.spawn(["actionlint", WORKFLOW], {
      stdout: "pipe",
      stderr: "pipe",
    });
    const code = await proc.exited;
    if (code !== 0) {
      const out = await new Response(proc.stdout).text();
      const err = await new Response(proc.stderr).text();
      throw new Error(`actionlint failed (exit ${code}):\n${out}\n${err}`);
    }
    expect(code).toBe(0);
  });
});
