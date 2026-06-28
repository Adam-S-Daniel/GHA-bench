// Workflow-structure tests.
//
// These parse the actual workflow YAML and assert on its structure, verify
// that the script paths it references exist, and confirm actionlint passes.
// They do NOT run act (that lives in the act harness) — they are fast static
// checks so a malformed workflow is caught instantly.
import { test, expect } from "bun:test";
import { parse } from "yaml";
import { existsSync } from "node:fs";
import { resolve } from "node:path";

const WORKFLOW_PATH = ".github/workflows/environment-matrix-generator.yml";

function loadWorkflow(): any {
  const text = require("node:fs").readFileSync(WORKFLOW_PATH, "utf8");
  return parse(text);
}

test("workflow file exists and is valid YAML", () => {
  expect(existsSync(WORKFLOW_PATH)).toBe(true);
  const wf = loadWorkflow();
  expect(wf).toBeTypeOf("object");
  expect(wf.name).toBe("Environment Matrix Generator");
});

test("declares the expected trigger events", () => {
  // YAML parses the bare `on:` key as boolean true in some libs; the `yaml`
  // package keeps it as the string "on". Handle both for safety.
  const wf = loadWorkflow();
  const on = wf.on ?? wf[true];
  expect(on).toBeDefined();
  expect(on).toHaveProperty("push");
  expect(on).toHaveProperty("pull_request");
  expect(on).toHaveProperty("schedule");
  expect(on).toHaveProperty("workflow_dispatch");
  // schedule must carry a cron entry
  expect(Array.isArray(on.schedule)).toBe(true);
  expect(on.schedule[0].cron).toBeTypeOf("string");
});

test("declares least-privilege read permissions", () => {
  const wf = loadWorkflow();
  expect(wf.permissions).toEqual({ contents: "read" });
});

test("has validate and generate jobs with a dependency between them", () => {
  const wf = loadWorkflow();
  expect(wf.jobs).toHaveProperty("validate");
  expect(wf.jobs).toHaveProperty("generate");
  // generate must depend on validate (job dependency requirement)
  expect(wf.jobs.generate.needs).toBe("validate");
});

test("checks out the repo and installs Bun in both jobs", () => {
  const wf = loadWorkflow();
  for (const jobId of ["validate", "generate"]) {
    const steps = wf.jobs[jobId].steps;
    const uses = steps.map((s: any) => s.uses).filter(Boolean);
    expect(uses).toContain("actions/checkout@v4");
    const runScript = steps.map((s: any) => s.run ?? "").join("\n");
    expect(runScript).toContain("bun.sh/install");
  }
});

test("the generate job references cli.ts and the fixtures dir", () => {
  const wf = loadWorkflow();
  const runScript = wf.jobs.generate.steps.map((s: any) => s.run ?? "").join("\n");
  expect(runScript).toContain("cli.ts");
  expect(runScript).toContain("FIXTURES_DIR");
  expect(wf.env.FIXTURES_DIR).toBe("fixtures");
});

test("every script path the workflow relies on actually exists", () => {
  // The files the workflow needs to run.
  for (const file of ["cli.ts", "matrix-generator.ts", "package.json"]) {
    expect(existsSync(resolve(file))).toBe(true);
  }
  // And there is at least one fixture to feed it.
  const fixtures = require("node:fs").readdirSync("fixtures").filter((f: string) => f.endsWith(".json"));
  expect(fixtures.length).toBeGreaterThan(0);
});

test("actionlint passes on the workflow (exit code 0)", () => {
  const proc = Bun.spawnSync(["actionlint", WORKFLOW_PATH]);
  const output = new TextDecoder().decode(proc.stdout) + new TextDecoder().decode(proc.stderr);
  // Surface any actionlint output to make failures debuggable.
  expect(output).toBe("");
  expect(proc.exitCode).toBe(0);
});
