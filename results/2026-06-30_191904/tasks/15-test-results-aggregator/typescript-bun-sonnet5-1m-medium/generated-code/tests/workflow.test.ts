import { describe, expect, test } from "bun:test";
import { existsSync } from "node:fs";
import { $ } from "bun";

const WORKFLOW_PATH = ".github/workflows/test-results-aggregator.yml";

describe("GitHub Actions workflow structure", () => {
  test("is valid YAML with the expected triggers", async () => {
    const raw = await Bun.file(WORKFLOW_PATH).text();
    const doc = Bun.YAML.parse(raw) as any;

    // YAML parses the bare key "on" as boolean true in YAML 1.1; GH workflows
    // are always read this way by act/GitHub, so check both possible keys.
    const triggers = doc.on ?? (doc as Record<string, unknown>)["true"];
    expect(triggers).toBeDefined();
    expect(Object.keys(triggers)).toEqual(
      expect.arrayContaining(["push", "pull_request", "workflow_dispatch", "schedule"]),
    );
  });

  test("declares the aggregate job with a checkout and bun setup step", async () => {
    const raw = await Bun.file(WORKFLOW_PATH).text();
    const doc = Bun.YAML.parse(raw) as any;

    expect(doc.jobs.aggregate).toBeDefined();
    expect(doc.jobs.aggregate["runs-on"]).toBe("ubuntu-latest");

    const stepUses = doc.jobs.aggregate.steps.map((s: any) => s.uses).filter(Boolean);
    expect(stepUses).toEqual(expect.arrayContaining(["actions/checkout@v4", "oven-sh/setup-bun@v2"]));
  });

  test("verify-summary job depends on the aggregate job", async () => {
    const raw = await Bun.file(WORKFLOW_PATH).text();
    const doc = Bun.YAML.parse(raw) as any;
    expect(doc.jobs["verify-summary"].needs).toBe("aggregate");
  });

  test("declares read-only top-level permissions", async () => {
    const raw = await Bun.file(WORKFLOW_PATH).text();
    const doc = Bun.YAML.parse(raw) as any;
    expect(doc.permissions).toEqual({ contents: "read" });
  });

  test("references the aggregator script at a path that exists in the repo", async () => {
    const raw = await Bun.file(WORKFLOW_PATH).text();
    const runSteps: string[] = raw.match(/run: .*aggregator\.ts.*/g) ?? [];
    expect(runSteps.length).toBeGreaterThan(0);
    expect(existsSync("src/aggregator.ts")).toBe(true);
  });

  test("actionlint passes with exit code 0", async () => {
    const result = await $`actionlint ${WORKFLOW_PATH}`.nothrow();
    expect(result.stdout.toString() + result.stderr.toString()).toBe("");
    expect(result.exitCode).toBe(0);
  });
});
