import { describe, expect, test } from "bun:test";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

// Resolve paths relative to the project root (one level up from tests/).
const root = join(import.meta.dir, "..");
const workflowPath = join(root, ".github", "workflows", "artifact-cleanup-script.yml");

// Parse the workflow YAML once for all structural assertions.
const workflowSource = readFileSync(workflowPath, "utf8");
// Bun ships a YAML parser; use it so we assert on real structure, not strings.
const workflow = Bun.YAML.parse(workflowSource) as any;

describe("workflow structure", () => {
  test("the workflow file exists and parses as YAML", () => {
    expect(existsSync(workflowPath)).toBe(true);
    expect(workflow).toBeTruthy();
    expect(workflow.name).toBe("Artifact Cleanup");
  });

  test("declares the expected trigger events", () => {
    // YAML's bare `on:` can parse to the boolean true as a key in some loaders;
    // Bun keeps it as the string "on".
    const on = workflow.on ?? workflow[true as unknown as string];
    expect(on).toBeTruthy();
    expect(Object.keys(on).sort()).toEqual(["pull_request", "push", "schedule", "workflow_dispatch"]);
    expect(on.schedule[0].cron).toBe("0 3 * * 0");
  });

  test("sets read-only permissions", () => {
    expect(workflow.permissions).toEqual({ contents: "read" });
  });

  test("defines two jobs with the plan job depending on the test job", () => {
    expect(Object.keys(workflow.jobs).sort()).toEqual(["plan", "test"]);
    expect(workflow.jobs.plan.needs).toBe("test");
  });

  test("both jobs run on ubuntu-latest", () => {
    expect(workflow.jobs.test["runs-on"]).toBe("ubuntu-latest");
    expect(workflow.jobs.plan["runs-on"]).toBe("ubuntu-latest");
  });

  test("checks out the repo and installs Bun in both jobs", () => {
    for (const jobName of ["test", "plan"]) {
      const steps = workflow.jobs[jobName].steps as any[];
      const uses = steps.map((s) => s.uses).filter(Boolean);
      expect(uses).toContain("actions/checkout@v4");
      const runs = steps.map((s) => s.run ?? "").join("\n");
      expect(runs).toContain("bun.sh/install");
    }
  });

  test("the plan job references the CLI script by its real path", () => {
    const steps = workflow.jobs.plan.steps as any[];
    const runs = steps.map((s) => s.run ?? "").join("\n");
    expect(runs).toContain("src/cli.ts");
    // The referenced script must actually exist on disk.
    expect(existsSync(join(root, "src", "cli.ts"))).toBe(true);
  });

  test("references the fixture file path via an env var that points at a real file", () => {
    expect(workflow.env.FIXTURE_FILE).toBe("fixtures/ci-input.json");
    expect(existsSync(join(root, workflow.env.FIXTURE_FILE))).toBe(true);
  });
});

// actionlint is present on the host CI machine but not inside the act
// container, where this same suite is re-run. Detect it and skip if absent
// so the in-container `bun test` step stays green.
const actionlintAvailable = !spawnSync("actionlint", ["-version"], { encoding: "utf8" }).error;

describe("actionlint", () => {
  test.skipIf(!actionlintAvailable)("passes with exit code 0", () => {
    const result = spawnSync("actionlint", [workflowPath], { encoding: "utf8" });
    expect(result.stdout + result.stderr).toBe("");
    expect(result.status).toBe(0);
  });
});
