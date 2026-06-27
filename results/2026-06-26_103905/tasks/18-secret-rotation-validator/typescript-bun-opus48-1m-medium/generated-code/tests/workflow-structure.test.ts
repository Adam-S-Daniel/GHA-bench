// Workflow structure tests: parse the YAML and assert the expected shape,
// verify it references real script files, and that actionlint passes cleanly.
// These run as part of `bun test` and are fast (no act, no Docker).
import { describe, expect, it } from "bun:test";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

const ROOT = join(import.meta.dir, "..");
const WORKFLOW_PATH = join(ROOT, ".github/workflows/secret-rotation-validator.yml");

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const workflow: any = (Bun as any).YAML.parse(readFileSync(WORKFLOW_PATH, "utf8"));

describe("workflow triggers", () => {
  it("defines the expected trigger events", () => {
    const on = workflow.on;
    expect(on).toHaveProperty("push");
    expect(on).toHaveProperty("pull_request");
    expect(on).toHaveProperty("schedule");
    expect(on).toHaveProperty("workflow_dispatch");
  });

  it("uses a valid cron schedule", () => {
    expect(workflow.on.schedule[0].cron).toBe("0 6 * * 1");
  });
});

describe("workflow permissions and env", () => {
  it("declares read-only contents permission", () => {
    expect(workflow.permissions.contents).toBe("read");
  });

  it("pins a deterministic reference date and config path", () => {
    expect(workflow.env.REPORT_NOW).toBe("2026-06-27");
    expect(workflow.env.CONFIG_PATH).toBe("fixtures/secrets.json");
  });
});

describe("workflow jobs", () => {
  it("has a test job and a validate job, with validate depending on test", () => {
    expect(workflow.jobs).toHaveProperty("test");
    expect(workflow.jobs).toHaveProperty("validate");
    expect(workflow.jobs.validate.needs).toBe("test");
  });

  it("checks out the repo and sets up Bun in both jobs", () => {
    for (const jobName of ["test", "validate"]) {
      const uses = workflow.jobs[jobName].steps.map((s: { uses?: string }) => s.uses).filter(Boolean);
      expect(uses).toContain("actions/checkout@v4");
      expect(uses.some((u: string) => u.startsWith("oven-sh/setup-bun@"))).toBe(true);
    }
  });

  it("runs the CLI script via bun run in the validate job", () => {
    const runSteps = workflow.jobs.validate.steps
      .map((s: { run?: string }) => s.run)
      .filter(Boolean)
      .join("\n");
    expect(runSteps).toContain("bun run src/cli.ts");
    expect(runSteps).toContain("--format markdown");
    expect(runSteps).toContain("--format json");
  });
});

describe("referenced files exist", () => {
  it("references the CLI entry point and config that exist on disk", () => {
    expect(existsSync(join(ROOT, "src/cli.ts"))).toBe(true);
    expect(existsSync(join(ROOT, "fixtures/secrets.json"))).toBe(true);
  });
});

// actionlint is available on the dev host but not inside the CI/act container,
// so skip this check when the binary is absent rather than failing the suite.
// Bun.spawnSync throws (not just non-zero) when the executable is missing.
function actionlintAvailable(): boolean {
  try {
    return Bun.spawnSync(["actionlint", "--version"]).exitCode === 0;
  } catch {
    return false;
  }
}
const hasActionlint = actionlintAvailable();

describe("actionlint", () => {
  it.skipIf(!hasActionlint)("passes with exit code 0", () => {
    const proc = Bun.spawnSync(["actionlint", WORKFLOW_PATH]);
    if (proc.exitCode !== 0) {
      // Surface actionlint's complaint in the test failure.
      throw new Error(new TextDecoder().decode(proc.stdout) + new TextDecoder().decode(proc.stderr));
    }
    expect(proc.exitCode).toBe(0);
  });
});
