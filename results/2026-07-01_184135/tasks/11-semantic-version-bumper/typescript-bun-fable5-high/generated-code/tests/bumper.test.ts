/**
 * RED phase (cycle 6): end-to-end orchestration tests for runBumper, plus a
 * subprocess test of the real CLI (src/cli.ts) so the exact stdout contract
 * the CI workflow depends on is pinned down.
 */
import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync, readFileSync, cpSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { runBumper } from "../src/bumper";

const FIXTURES = join(import.meta.dir, "..", "fixtures");
const CLI = join(import.meta.dir, "..", "src", "cli.ts");

let dir: string;
beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), "svb-e2e-"));
  writeFileSync(join(dir, "VERSION"), "1.1.0\n");
  cpSync(FIXTURES, join(dir, "fixtures"), { recursive: true });
});
afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
});

describe("runBumper", () => {
  test("feat commits bump 1.1.0 -> 1.2.0, update files, report result", () => {
    const result = runBumper({
      versionFile: join(dir, "VERSION"),
      commitsFile: join(dir, "fixtures", "commits-feat.log"),
      changelogFile: join(dir, "CHANGELOG.md"),
      date: "2026-07-02",
    });

    expect(result).toEqual({ oldVersion: "1.1.0", newVersion: "1.2.0", bump: "minor" });
    expect(readFileSync(join(dir, "VERSION"), "utf8")).toBe("1.2.0\n");
    const changelog = readFileSync(join(dir, "CHANGELOG.md"), "utf8");
    expect(changelog).toContain("## 1.2.0 (2026-07-02)");
    expect(changelog).toContain("- **api**: add pagination support");
  });

  test("fix commits bump 1.1.0 -> 1.1.1", () => {
    const result = runBumper({
      versionFile: join(dir, "VERSION"),
      commitsFile: join(dir, "fixtures", "commits-fix.log"),
      changelogFile: join(dir, "CHANGELOG.md"),
      date: "2026-07-02",
    });
    expect(result.newVersion).toBe("1.1.1");
    expect(result.bump).toBe("patch");
  });

  test("breaking commits bump 1.1.0 -> 2.0.0", () => {
    const result = runBumper({
      versionFile: join(dir, "VERSION"),
      commitsFile: join(dir, "fixtures", "commits-breaking.log"),
      changelogFile: join(dir, "CHANGELOG.md"),
      date: "2026-07-02",
    });
    expect(result.newVersion).toBe("2.0.0");
    expect(readFileSync(join(dir, "CHANGELOG.md"), "utf8")).toContain(
      "### Breaking Changes",
    );
  });

  test("non-releasable commits leave version and changelog untouched", () => {
    const result = runBumper({
      versionFile: join(dir, "VERSION"),
      commitsFile: join(dir, "fixtures", "commits-none.log"),
      changelogFile: join(dir, "CHANGELOG.md"),
      date: "2026-07-02",
    });
    expect(result).toEqual({ oldVersion: "1.1.0", newVersion: "1.1.0", bump: "none" });
    expect(readFileSync(join(dir, "VERSION"), "utf8")).toBe("1.1.0\n");
    expect(() => readFileSync(join(dir, "CHANGELOG.md"), "utf8")).toThrow();
  });

  test("works against package.json as the version file", () => {
    const pkg = join(dir, "package.json");
    writeFileSync(pkg, JSON.stringify({ name: "demo", version: "0.9.9" }) + "\n");
    const result = runBumper({
      versionFile: pkg,
      commitsFile: join(dir, "fixtures", "commits-feat.log"),
      changelogFile: join(dir, "CHANGELOG.md"),
      date: "2026-07-02",
    });
    expect(result.newVersion).toBe("0.10.0");
    expect(JSON.parse(readFileSync(pkg, "utf8")).version).toBe("0.10.0");
  });
});

describe("cli", () => {
  function runCli(...args: string[]): { code: number; stdout: string; stderr: string } {
    const proc = Bun.spawnSync(["bun", "run", CLI, ...args], { cwd: dir });
    return {
      code: proc.exitCode,
      stdout: proc.stdout.toString(),
      stderr: proc.stderr.toString(),
    };
  }

  test("prints the machine-readable result lines the workflow greps for", () => {
    const { code, stdout } = runCli(
      "--version-file", "VERSION",
      "--commits-file", "fixtures/commits-feat.log",
      "--changelog-file", "CHANGELOG.md",
    );
    expect(code).toBe(0);
    expect(stdout).toContain("OLD_VERSION=1.1.0");
    expect(stdout).toContain("BUMP=minor");
    expect(stdout).toContain("NEW_VERSION=1.2.0");
  });

  test("fails with a helpful message when the commits file is missing", () => {
    const { code, stderr } = runCli(
      "--version-file", "VERSION",
      "--commits-file", "no-such.log",
    );
    expect(code).toBe(1);
    expect(stderr).toContain('Commit log file not found: "no-such.log"');
  });

  test("fails with a helpful message on unknown flags", () => {
    const { code, stderr } = runCli("--bogus");
    expect(code).toBe(1);
    expect(stderr).toContain("Unknown argument: --bogus");
    expect(stderr).toContain("Usage:");
  });
});
