// TDD Cycle 4: End-to-end orchestration in runBump() — reading a version file
// (plain text OR package.json), computing the next version, writing files, and
// prepending the changelog. Uses a fresh temp dir per test for isolation.
import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { mkdtemp, readFile, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { runBump } from "../src/bumper.ts";

let dir: string;

beforeEach(async () => {
  dir = await mkdtemp(join(tmpdir(), "bumper-"));
});
afterEach(async () => {
  await rm(dir, { recursive: true, force: true });
});

describe("runBump with a plain VERSION file", () => {
  test("a feat commit bumps minor and updates the file", async () => {
    const versionFile = join(dir, "VERSION");
    const commitLog = join(dir, "commits.log");
    const changelog = join(dir, "CHANGELOG.md");
    await writeFile(versionFile, "1.1.0\n");
    await writeFile(commitLog, "feat: add a thing\nfix: patch a thing");

    const result = await runBump({
      versionFile,
      commitLog,
      changelogFile: changelog,
      date: "2026-06-27",
    });

    expect(result.previousVersion).toBe("1.1.0");
    expect(result.newVersion).toBe("1.2.0");
    expect(result.bump).toBe("minor");
    // file updated on disk
    expect((await readFile(versionFile, "utf8")).trim()).toBe("1.2.0");
    // changelog created with the new entry at the top
    const cl = await readFile(changelog, "utf8");
    expect(cl).toContain("## [1.2.0] - 2026-06-27");
    expect(cl).toContain("add a thing");
  });

  test("a breaking commit bumps major", async () => {
    const versionFile = join(dir, "VERSION");
    const commitLog = join(dir, "commits.log");
    await writeFile(versionFile, "0.5.2");
    await writeFile(commitLog, "feat!: overhaul everything");
    const result = await runBump({ versionFile, commitLog, date: "2026-06-27" });
    expect(result.newVersion).toBe("1.0.0");
    expect(result.bump).toBe("major");
  });

  test("no release-worthy commits leaves the version unchanged", async () => {
    const versionFile = join(dir, "VERSION");
    const commitLog = join(dir, "commits.log");
    await writeFile(versionFile, "3.4.5");
    await writeFile(commitLog, "chore: housekeeping\ndocs: tweak");
    const result = await runBump({ versionFile, commitLog, date: "2026-06-27" });
    expect(result.bump).toBe("none");
    expect(result.newVersion).toBe("3.4.5");
    // file content stays the same
    expect((await readFile(versionFile, "utf8")).trim()).toBe("3.4.5");
  });
});

describe("runBump with package.json", () => {
  test("reads and writes the .version field, preserving other fields", async () => {
    const pkgPath = join(dir, "package.json");
    const commitLog = join(dir, "commits.log");
    await writeFile(
      pkgPath,
      JSON.stringify({ name: "demo", version: "2.0.0", scripts: { test: "bun test" } }, null, 2) + "\n",
    );
    await writeFile(commitLog, "fix: a small bug");

    const result = await runBump({ versionFile: pkgPath, commitLog, date: "2026-06-27" });
    expect(result.newVersion).toBe("2.0.1");

    const pkg = JSON.parse(await readFile(pkgPath, "utf8"));
    expect(pkg.version).toBe("2.0.1");
    expect(pkg.name).toBe("demo"); // untouched
    expect(pkg.scripts.test).toBe("bun test"); // untouched
  });
});

describe("runBump error handling", () => {
  test("throws a clear error when the version file is missing", async () => {
    await expect(
      runBump({ versionFile: join(dir, "nope"), commitLog: join(dir, "nope2"), date: "2026-06-27" }),
    ).rejects.toThrow(/version file/i);
  });

  test("throws a clear error when the version file has an invalid version", async () => {
    const versionFile = join(dir, "VERSION");
    const commitLog = join(dir, "commits.log");
    await writeFile(versionFile, "garbage");
    await writeFile(commitLog, "feat: x");
    await expect(runBump({ versionFile, commitLog, date: "2026-06-27" })).rejects.toThrow(
      /invalid semantic version/i,
    );
  });

  test("dryRun computes the version without writing files", async () => {
    const versionFile = join(dir, "VERSION");
    const commitLog = join(dir, "commits.log");
    await writeFile(versionFile, "1.0.0");
    await writeFile(commitLog, "feat: x");
    const result = await runBump({ versionFile, commitLog, date: "2026-06-27", dryRun: true });
    expect(result.newVersion).toBe("1.1.0");
    // unchanged on disk because dryRun
    expect((await readFile(versionFile, "utf8")).trim()).toBe("1.0.0");
  });
});
