import { describe, expect, test } from "bun:test";
import { existsSync, readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { join } from "node:path";

const ROOT = join(import.meta.dir, "..");
const WORKFLOW = join(ROOT, ".github/workflows/dependency-license-checker.yml");

// Parse the workflow YAML once for structural assertions.
const raw = readFileSync(WORKFLOW, "utf8");
const wf = Bun.YAML.parse(raw) as any;

describe("workflow structure", () => {
  test("declares the expected trigger events", () => {
    // YAML's bare `on:` can be parsed as the boolean key `true`.
    const on = wf.on ?? wf[true];
    expect(on).toBeDefined();
    expect("push" in on).toBe(true);
    expect("pull_request" in on).toBe(true);
    expect("schedule" in on).toBe(true);
    expect("workflow_dispatch" in on).toBe(true);
  });

  test("sets least-privilege read permissions", () => {
    expect(wf.permissions).toEqual({ contents: "read" });
  });

  test("defines a license-check job on ubuntu-latest", () => {
    expect(wf.jobs).toBeDefined();
    expect(wf.jobs["license-check"]).toBeDefined();
    expect(wf.jobs["license-check"]["runs-on"]).toBe("ubuntu-latest");
  });

  test("checks out the repo and references the checker script", () => {
    const steps = wf.jobs["license-check"].steps as any[];
    const uses = steps.map((s) => s.uses).filter(Boolean);
    expect(uses).toContain("actions/checkout@v4");

    const runScript = steps.some(
      (s) => typeof s.run === "string" && s.run.includes("src/cli.ts"),
    );
    expect(runScript).toBe(true);
  });

  test("references config and database paths via env", () => {
    expect(wf.env.MANIFEST).toBe("fixtures/package.json");
    expect(wf.env.LICENSE_CONFIG).toBe("fixtures/license-config.json");
    expect(wf.env.LICENSE_DB).toBe("fixtures/license-db.json");
  });
});

describe("referenced files exist on disk", () => {
  test("the checker script and all fixtures are present", () => {
    expect(existsSync(join(ROOT, "src/cli.ts"))).toBe(true);
    expect(existsSync(join(ROOT, "fixtures/package.json"))).toBe(true);
    expect(existsSync(join(ROOT, "fixtures/license-config.json"))).toBe(true);
    expect(existsSync(join(ROOT, "fixtures/license-db.json"))).toBe(true);
  });
});

describe("actionlint", () => {
  // actionlint is not present inside the act container, so skip there.
  test.skipIf(process.env.ACT === "true")(
    "passes with exit code 0",
    () => {
      const res = spawnSync("actionlint", [WORKFLOW], { encoding: "utf8" });
      expect(res.status).toBe(0);
    },
  );
});
