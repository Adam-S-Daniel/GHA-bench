// Workflow STRUCTURE tests (fast, no Docker).
// These parse the YAML, assert the expected triggers/jobs/steps, verify the
// referenced script paths exist, and confirm actionlint passes cleanly.
//
// NOTE: these live under meta/ (not tests/) so the CI workflow's
// `bun test tests/` step does NOT run them inside the act container — they
// depend on the actionlint binary and on the repo layout from the host.
import { describe, expect, test } from "bun:test";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { load } from "js-yaml";

const ROOT = join(import.meta.dir, "..");
const WORKFLOW = join(ROOT, ".github", "workflows", "semantic-version-bumper.yml");

interface Step {
  name?: string;
  uses?: string;
  run?: string;
  id?: string;
}
interface Job {
  "runs-on"?: string;
  needs?: string | string[];
  steps?: Step[];
}
interface Workflow {
  name?: string;
  on?: Record<string, unknown>;
  permissions?: Record<string, string>;
  env?: Record<string, string>;
  jobs?: Record<string, Job>;
}

const wf = load(readFileSync(WORKFLOW, "utf8")) as Workflow;

describe("workflow file", () => {
  test("exists and is valid YAML", () => {
    expect(existsSync(WORKFLOW)).toBe(true);
    expect(wf).toBeTypeOf("object");
  });

  test("declares the expected trigger events", () => {
    const on = wf.on ?? {};
    expect(Object.keys(on)).toEqual(
      expect.arrayContaining(["push", "pull_request", "schedule", "workflow_dispatch"]),
    );
  });

  test("uses least-privilege contents:read permission", () => {
    expect(wf.permissions?.contents).toBe("read");
  });

  test("defines env defaults for version/commits/changelog files", () => {
    expect(wf.env?.VERSION_FILE).toBeDefined();
    expect(wf.env?.COMMITS_FILE).toBeDefined();
    expect(wf.env?.CHANGELOG_FILE).toBe("CHANGELOG.md");
  });
});

describe("jobs and dependencies", () => {
  test("has a 'bump' job and a 'report' job that depends on it", () => {
    expect(wf.jobs?.bump).toBeDefined();
    expect(wf.jobs?.report).toBeDefined();
    expect(wf.jobs?.report?.needs).toBe("bump");
  });

  test("bump job checks out, sets up bun, and runs the CLI", () => {
    const steps = wf.jobs?.bump?.steps ?? [];
    const uses = steps.map((s) => s.uses).filter(Boolean);
    expect(uses).toContain("actions/checkout@v4");
    expect(uses.some((u) => u?.startsWith("oven-sh/setup-bun@"))).toBe(true);

    const runScript = steps.map((s) => s.run ?? "").join("\n");
    expect(runScript).toContain("src/cli.ts");
  });
});

describe("referenced files exist", () => {
  test("the CLI script and its imports are present", () => {
    expect(existsSync(join(ROOT, "src", "cli.ts"))).toBe(true);
    expect(existsSync(join(ROOT, "src", "bumper.ts"))).toBe(true);
    expect(existsSync(join(ROOT, "src", "semver.ts"))).toBe(true);
    expect(existsSync(join(ROOT, "src", "commits.ts"))).toBe(true);
    expect(existsSync(join(ROOT, "src", "changelog.ts"))).toBe(true);
  });

  test("the default commits fixture and version file exist", () => {
    expect(existsSync(join(ROOT, "commits.txt"))).toBe(true);
    expect(existsSync(join(ROOT, "package.json"))).toBe(true);
  });
});

describe("actionlint", () => {
  test("passes with exit code 0", () => {
    const proc = Bun.spawnSync(["actionlint", WORKFLOW]);
    if (proc.exitCode !== 0) {
      // Surface actionlint's complaint in the failure message.
      throw new Error(new TextDecoder().decode(proc.stdout) + new TextDecoder().decode(proc.stderr));
    }
    expect(proc.exitCode).toBe(0);
  });
});
