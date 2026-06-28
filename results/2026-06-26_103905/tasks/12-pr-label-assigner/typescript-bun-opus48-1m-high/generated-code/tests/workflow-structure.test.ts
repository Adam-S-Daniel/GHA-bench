import { describe, expect, test } from "bun:test";
import { existsSync } from "node:fs";
import { join } from "node:path";
import { parse } from "yaml";

// These tests validate the *workflow file itself* (structure + references),
// independently of running it through act. They run under plain `bun test`.
const ROOT = join(import.meta.dir, "..");
const WORKFLOW = join(ROOT, ".github/workflows/pr-label-assigner.yml");

async function readWorkflow(): Promise<any> {
  const raw = await Bun.file(WORKFLOW).text();
  return parse(raw);
}

describe("workflow structure", () => {
  test("workflow file exists", () => {
    expect(existsSync(WORKFLOW)).toBe(true);
  });

  test("declares the expected trigger events", async () => {
    const wf = await readWorkflow();
    // YAML parses the `on:` key; ensure our triggers are present.
    const on = wf.on ?? wf.true; // `on` can be parsed as boolean true by some loaders
    expect(on).toBeDefined();
    expect(Object.keys(on)).toEqual(
      expect.arrayContaining([
        "push",
        "pull_request",
        "workflow_dispatch",
        "schedule",
      ]),
    );
  });

  test("sets least-privilege permissions", async () => {
    const wf = await readWorkflow();
    expect(wf.permissions).toMatchObject({
      contents: "read",
      "pull-requests": "write",
    });
  });

  test("defines the assign-labels job on ubuntu-latest", async () => {
    const wf = await readWorkflow();
    expect(wf.jobs).toHaveProperty("assign-labels");
    expect(wf.jobs["assign-labels"]["runs-on"]).toBe("ubuntu-latest");
  });

  test("checks out the repo and sets up Bun via valid action refs", async () => {
    const wf = await readWorkflow();
    const steps = wf.jobs["assign-labels"].steps as Array<{ uses?: string }>;
    const uses = steps.map((s) => s.uses).filter(Boolean);
    expect(uses).toContain("actions/checkout@v4");
    expect(uses).toContain("oven-sh/setup-bun@v2");
  });

  test("invokes the CLI script that actually exists in the repo", async () => {
    const wf = await readWorkflow();
    const steps = wf.jobs["assign-labels"].steps as Array<{ run?: string }>;
    const runScript = steps.map((s) => s.run ?? "").join("\n");
    // The workflow must call our CLI...
    expect(runScript).toContain("src/cli.ts");
    // ...and the referenced files must really be present in the repo.
    expect(existsSync(join(ROOT, "src/cli.ts"))).toBe(true);
    expect(existsSync(join(ROOT, "src/labeler.ts"))).toBe(true);
    expect(existsSync(join(ROOT, ".github/labeler-config.json"))).toBe(true);
    expect(existsSync(join(ROOT, "fixtures/changed-files.txt"))).toBe(true);
  });
});

describe("actionlint", () => {
  test("passes cleanly (exit code 0)", async () => {
    const proc = Bun.spawn(["actionlint", WORKFLOW], {
      stdout: "pipe",
      stderr: "pipe",
    });
    const [out, err] = await Promise.all([
      new Response(proc.stdout).text(),
      new Response(proc.stderr).text(),
    ]);
    const code = await proc.exited;
    if (code !== 0) console.error("actionlint output:\n", out, err);
    expect(code).toBe(0);
  });
});
