// Workflow STRUCTURE tests.
//
// These assert that .github/workflows/semantic-version-bumper.yml is shaped the
// way the pipeline expects — without invoking act (fast, no Docker). They parse
// the YAML with Bun's built-in parser, check the triggers/jobs/steps, confirm
// the workflow references real script files, and confirm it passes actionlint.

import { describe, test, expect } from "bun:test";
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

const PROJECT = import.meta.dir;
const WORKFLOW_PATH = join(PROJECT, ".github/workflows/semantic-version-bumper.yml");

// Parse the workflow once for all the structural assertions below.
const workflowText = readFileSync(WORKFLOW_PATH, "utf8");
// `Bun.YAML` is a relatively new API; fail loudly (not cryptically) on an older
// Bun rather than throwing an opaque "undefined" at import time.
const bunYaml = (Bun as unknown as { YAML?: { parse(s: string): any } }).YAML;
if (!bunYaml?.parse) {
  throw new Error(
    "Bun.YAML.parse is unavailable — upgrade Bun (>= 1.2) to run the workflow-structure tests.",
  );
}
// Bun's YAML parser follows YAML 1.2, so the `on:` key stays the string "on"
// (it is NOT coerced to the boolean `true`, as YAML 1.1 parsers would do).
const workflow = bunYaml.parse(workflowText);

describe("workflow file", () => {
  test("exists and is valid, non-empty YAML", () => {
    expect(existsSync(WORKFLOW_PATH)).toBe(true);
    expect(typeof workflow).toBe("object");
    expect(workflow).not.toBeNull();
  });

  test("has a human-readable name", () => {
    expect(workflow.name).toBe("Semantic Version Bumper");
  });
});

describe("triggers", () => {
  test("fires on push, pull_request, workflow_dispatch and schedule", () => {
    const on = workflow.on;
    expect(on).toBeDefined();
    expect(on).toHaveProperty("push");
    expect(on).toHaveProperty("pull_request");
    expect(on).toHaveProperty("workflow_dispatch");
    expect(on).toHaveProperty("schedule");
  });

  test("the schedule is a valid cron list", () => {
    expect(Array.isArray(workflow.on.schedule)).toBe(true);
    expect(workflow.on.schedule[0].cron).toBe("0 3 * * 1");
  });

  test("workflow_dispatch exposes a dry-run boolean input", () => {
    expect(workflow.on.workflow_dispatch.inputs["dry-run"].type).toBe("boolean");
  });
});

describe("permissions and env", () => {
  test("requests least-privilege read-only contents access", () => {
    expect(workflow.permissions).toEqual({ contents: "read" });
  });

  test("declares the file-location environment variables", () => {
    expect(workflow.env.VERSION_FILE).toBe("version.txt");
    expect(workflow.env.COMMIT_LOG).toBe("commits.log");
    expect(workflow.env.CHANGELOG_FILE).toBe("CHANGELOG.md");
  });
});

describe("the bump job", () => {
  const job = () => workflow.jobs.bump;

  test("exists and runs on ubuntu-latest", () => {
    expect(job()).toBeDefined();
    expect(job()["runs-on"]).toBe("ubuntu-latest");
  });

  test("checks out the repo with actions/checkout@v4", () => {
    const uses = job().steps.map((s: any) => s.uses).filter(Boolean);
    expect(uses).toContain("actions/checkout@v4");
  });

  test("installs Bun before using it", () => {
    const steps: any[] = job().steps;
    const installIdx = steps.findIndex(
      (s) => typeof s.run === "string" && s.run.includes("bun.sh/install"),
    );
    const runIdx = steps.findIndex(
      (s) => typeof s.run === "string" && s.run.includes("version-bumper.ts"),
    );
    expect(installIdx).toBeGreaterThanOrEqual(0);
    expect(runIdx).toBeGreaterThan(installIdx);
  });

  test("has a step that actually runs the version-bumper script", () => {
    const runsScript = job().steps.some(
      (s: any) =>
        typeof s.run === "string" &&
        s.run.includes("bun run version-bumper.ts"),
    );
    expect(runsScript).toBe(true);
  });

  test("the bump step has an id so its outputs can be consumed", () => {
    const bumpStep = job().steps.find(
      (s: any) => typeof s.run === "string" && s.run.includes("bun run version-bumper.ts"),
    );
    expect(bumpStep.id).toBe("bump");
  });
});

describe("referenced files exist on disk", () => {
  test("the script the workflow runs is present", () => {
    expect(existsSync(join(PROJECT, "version-bumper.ts"))).toBe(true);
  });

  test("the unit-test file the CI step runs is present", () => {
    expect(existsSync(join(PROJECT, "version-bumper.test.ts"))).toBe(true);
  });

  test("all fixture commit logs and version files are present", () => {
    for (const c of ["feat", "fix", "breaking"]) {
      expect(existsSync(join(PROJECT, `fixtures/${c}/version.txt`))).toBe(true);
      expect(existsSync(join(PROJECT, `fixtures/${c}/commits.log`))).toBe(true);
    }
  });
});

describe("actionlint", () => {
  test("validates the workflow with exit code 0", () => {
    const result = spawnSync("actionlint", [WORKFLOW_PATH], { encoding: "utf8" });
    // Surface any findings in the failure message for easy diagnosis.
    expect(result.stdout + result.stderr).toBe("");
    expect(result.status).toBe(0);
  });
});
