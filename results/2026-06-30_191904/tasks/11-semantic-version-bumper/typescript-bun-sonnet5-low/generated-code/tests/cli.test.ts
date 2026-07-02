// RED: exercises the CLI end-to-end against real files in a scratch directory,
// so it doubles as the integration test the GitHub Actions workflow will run.
import { describe, expect, test, beforeEach, afterEach } from "bun:test";
import { mkdtemp, rm, readFile, writeFile, mkdir } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { runVersionBump } from "../src/cli";

let workDir: string;

beforeEach(async () => {
  workDir = await mkdtemp(join(tmpdir(), "version-bumper-"));
});

afterEach(async () => {
  await rm(workDir, { recursive: true, force: true });
});

async function setup(version: string, commits: string[]): Promise<{
  versionFile: string;
  commitsFile: string;
  changelogFile: string;
}> {
  const versionFile = join(workDir, "version.json");
  const commitsFile = join(workDir, "commits.txt");
  const changelogFile = join(workDir, "CHANGELOG.md");
  await writeFile(versionFile, JSON.stringify({ version }));
  await writeFile(commitsFile, commits.join("\n"));
  return { versionFile, commitsFile, changelogFile };
}

describe("runVersionBump", () => {
  test("bumps minor version on a feat commit and updates the version file", async () => {
    const { versionFile, commitsFile, changelogFile } = await setup("1.1.0", [
      "feat(auth): add OAuth login support",
      "fix(session): correct token refresh timing",
    ]);

    const result = await runVersionBump({ versionFile, commitsFile, changelogFile });

    expect(result.newVersion).toBe("1.2.0");
    const updated = JSON.parse(await readFile(versionFile, "utf8"));
    expect(updated.version).toBe("1.2.0");
  });

  test("bumps patch version when only fixes are present", async () => {
    const { versionFile, commitsFile, changelogFile } = await setup("1.1.0", [
      "fix(parser): handle empty input string",
    ]);

    const result = await runVersionBump({ versionFile, commitsFile, changelogFile });
    expect(result.newVersion).toBe("1.1.1");
  });

  test("bumps major version on a breaking change", async () => {
    const { versionFile, commitsFile, changelogFile } = await setup("1.1.0", [
      "feat(api)!: rename endpoint",
    ]);

    const result = await runVersionBump({ versionFile, commitsFile, changelogFile });
    expect(result.newVersion).toBe("2.0.0");
  });

  test("prepends a changelog entry to an existing CHANGELOG.md", async () => {
    const { versionFile, commitsFile, changelogFile } = await setup("1.1.0", [
      "feat(auth): add OAuth login support",
    ]);
    await writeFile(changelogFile, "# Changelog\n\n## 1.1.0\n\n- initial release\n");

    await runVersionBump({ versionFile, commitsFile, changelogFile });

    const changelog = await readFile(changelogFile, "utf8");
    expect(changelog.indexOf("## 1.2.0")).toBeLessThan(changelog.indexOf("## 1.1.0"));
    expect(changelog).toContain("add OAuth login support");
  });

  test("throws when no commits trigger a bump", async () => {
    const { versionFile, commitsFile, changelogFile } = await setup("1.1.0", [
      "chore: tidy up ci config",
    ]);

    await expect(
      runVersionBump({ versionFile, commitsFile, changelogFile }),
    ).rejects.toThrow(/no version bump required/i);
  });
});
