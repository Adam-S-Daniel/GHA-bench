// TDD step 4 (RED): end-to-end orchestration over real files.
import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync, readFileSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { readVersion, runBump } from "../src/bumper";

let dir: string;

beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), "svb-"));
});
afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
});

describe("readVersion", () => {
  test("reads .version from a package.json", () => {
    const p = join(dir, "package.json");
    writeFileSync(p, JSON.stringify({ name: "x", version: "1.2.3" }));
    expect(readVersion(p)).toEqual({ version: "1.2.3", kind: "json" });
  });

  test("reads a plain VERSION file", () => {
    const p = join(dir, "VERSION");
    writeFileSync(p, "0.9.0\n");
    expect(readVersion(p)).toEqual({ version: "0.9.0", kind: "plain" });
  });

  test("throws a clear error when the file is missing", () => {
    expect(() => readVersion(join(dir, "nope.json"))).toThrow(/not found/i);
  });
});

describe("runBump", () => {
  const setup = (version: string, commits: string) => {
    const versionFile = join(dir, "package.json");
    const commitsFile = join(dir, "commits.txt");
    const changelogFile = join(dir, "CHANGELOG.md");
    writeFileSync(versionFile, JSON.stringify({ name: "demo", version }, null, 2));
    writeFileSync(commitsFile, commits);
    return { versionFile, commitsFile, changelogFile };
  };

  test("feat commit bumps 1.1.0 -> 1.2.0 and writes files", () => {
    const { versionFile, commitsFile, changelogFile } = setup(
      "1.1.0",
      "feat: add thing\nfix: small bug\n",
    );

    const result = runBump({ versionFile, commitsFile, changelogFile, date: "2026-06-26" });

    expect(result.bump).toBe("minor");
    expect(result.previousVersion).toBe("1.1.0");
    expect(result.newVersion).toBe("1.2.0");

    // version file updated in place, preserving JSON shape
    const pkg = JSON.parse(readFileSync(versionFile, "utf8"));
    expect(pkg.version).toBe("1.2.0");
    expect(pkg.name).toBe("demo");

    // changelog created with the new entry on top
    const changelog = readFileSync(changelogFile, "utf8");
    expect(changelog).toContain("## 1.2.0 (2026-06-26)");
    expect(changelog).toContain("- add thing");
  });

  test("breaking change bumps major 2.4.1 -> 3.0.0", () => {
    const { versionFile, commitsFile, changelogFile } = setup(
      "2.4.1",
      "feat!: overhaul config format\n",
    );
    const result = runBump({ versionFile, commitsFile, changelogFile, date: "2026-06-26" });
    expect(result.bump).toBe("major");
    expect(result.newVersion).toBe("3.0.0");
  });

  test("fix-only bumps patch 1.0.0 -> 1.0.1", () => {
    const { versionFile, commitsFile, changelogFile } = setup("1.0.0", "fix: a\n");
    const result = runBump({ versionFile, commitsFile, changelogFile, date: "2026-06-26" });
    expect(result.newVersion).toBe("1.0.1");
  });

  test("no releasable commits leaves version untouched", () => {
    const { versionFile, commitsFile, changelogFile } = setup(
      "1.0.0",
      "chore: nothing\ndocs: words\n",
    );
    const result = runBump({ versionFile, commitsFile, changelogFile, date: "2026-06-26" });
    expect(result.bump).toBe(null);
    expect(result.newVersion).toBe("1.0.0");
    expect(JSON.parse(readFileSync(versionFile, "utf8")).version).toBe("1.0.0");
    // no changelog written when nothing changed
    expect(existsSync(changelogFile)).toBe(false);
  });

  test("prepends to an existing changelog rather than clobbering it", () => {
    const { versionFile, commitsFile, changelogFile } = setup("1.0.0", "fix: a\n");
    writeFileSync(changelogFile, "# Changelog\n\n## 1.0.0 (2026-01-01)\n\n- initial\n");
    runBump({ versionFile, commitsFile, changelogFile, date: "2026-06-26" });
    const changelog = readFileSync(changelogFile, "utf8");
    expect(changelog.indexOf("## 1.0.1")).toBeLessThan(changelog.indexOf("## 1.0.0 (2026-01-01)"));
    expect(changelog).toContain("- initial");
  });
});
