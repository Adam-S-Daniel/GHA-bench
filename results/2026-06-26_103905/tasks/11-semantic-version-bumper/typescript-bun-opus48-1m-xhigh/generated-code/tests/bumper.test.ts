// RED phase for the orchestrator that wires every module together.
//
// runBump() reads the version file + commit log, computes the next version,
// and (unless dry-run) updates the version file and prepends a changelog
// entry. It returns a structured result for the CLI to print.
import { afterEach, beforeEach, describe, expect, it } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync, readFileSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { runBump } from "../src/bumper.ts";

let dir: string;

beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), "svb-bump-"));
});
afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
});

function setup(version: string, commitLog: string, versionName = "VERSION") {
  const versionPath = join(dir, versionName);
  const commitsPath = join(dir, "commits.txt");
  const changelogPath = join(dir, "CHANGELOG.md");
  writeFileSync(versionPath, version);
  writeFileSync(commitsPath, commitLog);
  return { versionPath, commitsPath, changelogPath };
}

describe("runBump", () => {
  it("bumps a minor version for a feat and writes both files", async () => {
    const { versionPath, commitsPath, changelogPath } = setup(
      "1.1.0",
      "feat: add a thing\n--COMMIT--\nchore: noise",
    );
    const result = await runBump({
      versionFilePath: versionPath,
      commitsPath,
      changelogPath,
      date: "2026-06-27",
    });

    expect(result.previousVersion).toBe("1.1.0");
    expect(result.newVersion).toBe("1.2.0");
    expect(result.bump).toBe("minor");
    expect(result.changed).toBe(true);

    expect(readFileSync(versionPath, "utf8").trim()).toBe("1.2.0");
    expect(readFileSync(changelogPath, "utf8")).toContain("## [1.2.0] - 2026-06-27");
  });

  it("bumps a patch for a fix", async () => {
    const { versionPath, commitsPath, changelogPath } = setup("2.3.4", "fix: oops");
    const result = await runBump({
      versionFilePath: versionPath,
      commitsPath,
      changelogPath,
      date: "2026-06-27",
    });
    expect(result.newVersion).toBe("2.3.5");
    expect(result.bump).toBe("patch");
  });

  it("bumps a major for a breaking change", async () => {
    const { versionPath, commitsPath, changelogPath } = setup(
      "0.5.7",
      "feat!: overhaul API",
    );
    const result = await runBump({
      versionFilePath: versionPath,
      commitsPath,
      changelogPath,
      date: "2026-06-27",
    });
    expect(result.newVersion).toBe("1.0.0");
    expect(result.bump).toBe("major");
  });

  it("supports package.json as the version source", async () => {
    const { versionPath, commitsPath, changelogPath } = setup(
      JSON.stringify({ name: "demo", version: "4.0.0" }, null, 2),
      "feat: x",
      "package.json",
    );
    const result = await runBump({
      versionFilePath: versionPath,
      commitsPath,
      changelogPath,
      date: "2026-06-27",
    });
    expect(result.newVersion).toBe("4.1.0");
    expect(JSON.parse(readFileSync(versionPath, "utf8")).version).toBe("4.1.0");
  });

  it("makes no change when no commit is release-worthy", async () => {
    const { versionPath, commitsPath, changelogPath } = setup(
      "1.0.0",
      "docs: a\n--COMMIT--\nchore: b",
    );
    const result = await runBump({
      versionFilePath: versionPath,
      commitsPath,
      changelogPath,
      date: "2026-06-27",
    });
    expect(result.bump).toBe("none");
    expect(result.newVersion).toBe("1.0.0");
    expect(result.changed).toBe(false);
    // Version file untouched; no changelog created.
    expect(readFileSync(versionPath, "utf8")).toBe("1.0.0");
    expect(existsSync(changelogPath)).toBe(false);
  });

  it("does not touch any file in dry-run mode", async () => {
    const { versionPath, commitsPath, changelogPath } = setup("1.0.0", "feat: x");
    const result = await runBump({
      versionFilePath: versionPath,
      commitsPath,
      changelogPath,
      date: "2026-06-27",
      dryRun: true,
    });
    expect(result.newVersion).toBe("1.1.0");
    expect(result.changed).toBe(true);
    expect(readFileSync(versionPath, "utf8")).toBe("1.0.0");
    expect(existsSync(changelogPath)).toBe(false);
  });

  it("throws a clear error when the commit log is missing", async () => {
    const versionPath = join(dir, "VERSION");
    writeFileSync(versionPath, "1.0.0");
    await expect(
      runBump({
        versionFilePath: versionPath,
        commitsPath: join(dir, "missing.txt"),
        date: "2026-06-27",
      }),
    ).rejects.toThrow(/commit log not found/i);
  });
});
