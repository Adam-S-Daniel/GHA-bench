// Workflow structure tests: parse the YAML, assert the expected triggers, jobs,
// and steps exist; verify the workflow references files that actually exist on
// disk; and confirm actionlint passes (exit code 0). No `act` here — these are
// fast static checks that gate the slower act-based harness.
import { describe, expect, test } from "bun:test";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

const ROOT = join(import.meta.dir, "..");
const WORKFLOW_PATH = join(ROOT, ".github", "workflows", "semantic-version-bumper.yml");

// Parse the workflow once for the whole suite.
const rawYaml = readFileSync(WORKFLOW_PATH, "utf8");
// Bun ships a built-in YAML parser.
const workflow = (Bun as unknown as { YAML: { parse(s: string): any } }).YAML.parse(rawYaml);

describe("workflow file", () => {
  test("exists and parses as YAML", () => {
    expect(existsSync(WORKFLOW_PATH)).toBe(true);
    expect(workflow).toBeTruthy();
    expect(workflow.name).toBe("Semantic Version Bumper");
  });
});

describe("triggers", () => {
  // Note: YAML's bare `on:` can deserialize to the boolean true; the parser
  // keys it under "on" with the value object here.
  const on = workflow.on;

  test("declares push, pull_request, workflow_dispatch and schedule", () => {
    expect(on).toHaveProperty("push");
    expect(on).toHaveProperty("pull_request");
    expect(on).toHaveProperty("workflow_dispatch");
    expect(on).toHaveProperty("schedule");
  });

  test("schedule has a cron expression", () => {
    expect(Array.isArray(on.schedule)).toBe(true);
    expect(on.schedule[0].cron).toMatch(/^\S+ \S+ \S+ \S+ \S+$/);
  });
});

describe("permissions", () => {
  test("grants least-privilege read access to contents", () => {
    expect(workflow.permissions).toEqual({ contents: "read" });
  });
});

describe("env", () => {
  test("centralises the file paths the script consumes", () => {
    expect(workflow.env.VERSION_FILE).toBe("VERSION");
    expect(workflow.env.COMMIT_LOG).toBe("commits.log");
    expect(workflow.env.CHANGELOG_FILE).toBe("CHANGELOG.md");
  });
});

describe("the bump job", () => {
  const job = workflow.jobs.bump;

  test("exists and runs on ubuntu-latest", () => {
    expect(job).toBeTruthy();
    expect(job["runs-on"]).toBe("ubuntu-latest");
  });

  test("checks out the repo with actions/checkout@v4", () => {
    const uses = job.steps.map((s: any) => s.uses).filter(Boolean);
    expect(uses).toContain("actions/checkout@v4");
  });

  test("installs Bun and runs the bumper script", () => {
    const runScripts = job.steps.map((s: any) => s.run ?? "").join("\n");
    expect(runScripts).toContain("bun.sh/install");
    expect(runScripts).toContain("src/bumper.ts");
    expect(runScripts).toContain("bun test");
  });

  test("emits a grep-able RESULT_NEW_VERSION line", () => {
    const runScripts = job.steps.map((s: any) => s.run ?? "").join("\n");
    expect(runScripts).toContain("RESULT_NEW_VERSION=");
  });
});

describe("referenced files exist on disk", () => {
  test("the bumper script the workflow runs is present", () => {
    expect(existsSync(join(ROOT, "src", "bumper.ts"))).toBe(true);
  });

  test("all fixture cases provide a VERSION and commits.log", () => {
    for (const name of ["feat-minor", "fix-patch", "breaking-major", "none-nochange"]) {
      expect(existsSync(join(ROOT, "fixtures", name, "VERSION"))).toBe(true);
      expect(existsSync(join(ROOT, "fixtures", name, "commits.log"))).toBe(true);
    }
  });
});

describe("actionlint", () => {
  test("passes cleanly (exit code 0)", () => {
    const res = spawnSync("actionlint", [WORKFLOW_PATH], { encoding: "utf8" });
    // If actionlint isn't installed in this environment, surface that rather
    // than silently passing.
    expect(res.error).toBeUndefined();
    if (res.status !== 0) {
      // Print diagnostics to aid debugging when it fails.
      console.error(res.stdout, res.stderr);
    }
    expect(res.status).toBe(0);
  });
});
