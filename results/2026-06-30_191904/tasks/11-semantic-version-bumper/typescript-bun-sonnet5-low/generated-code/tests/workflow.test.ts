// Verifies the workflow YAML has the expected structure and that actionlint
// passes on it, and that the script paths it references actually exist.
import { describe, expect, test } from "bun:test";
import { readFile } from "node:fs/promises";
import { parse } from "yaml";
import { $ } from "bun";

const WORKFLOW_PATH = ".github/workflows/semantic-version-bumper.yml";

describe("semantic-version-bumper workflow", () => {
  test("is valid YAML with expected triggers and jobs", async () => {
    const raw = await readFile(WORKFLOW_PATH, "utf8");
    const doc = parse(raw);

    expect(doc.on).toHaveProperty("push");
    expect(doc.on).toHaveProperty("workflow_dispatch");
    expect(doc.jobs).toHaveProperty("test");
    expect(doc.jobs).toHaveProperty("bump-version");
    expect(doc.jobs["bump-version"].needs).toBe("test");
    expect(doc.permissions.contents).toBe("read");
  });

  test("references script files that exist on disk", async () => {
    const raw = await readFile(WORKFLOW_PATH, "utf8");
    expect(raw).toContain("src/cli.ts");
    const cliFile = Bun.file("src/cli.ts");
    expect(await cliFile.exists()).toBe(true);
    const versionBumperFile = Bun.file("src/versionBumper.ts");
    expect(await versionBumperFile.exists()).toBe(true);
  });

  test("passes actionlint validation", async () => {
    const which = await $`which actionlint`.nothrow().quiet();
    if (which.exitCode !== 0) {
      // actionlint isn't installed in this environment (e.g. minimal act
      // containers); actionlint is run separately in CI/dev environments
      // where it is available.
      return;
    }
    const result = await $`actionlint ${WORKFLOW_PATH}`.nothrow();
    expect(result.exitCode).toBe(0);
  });
});
