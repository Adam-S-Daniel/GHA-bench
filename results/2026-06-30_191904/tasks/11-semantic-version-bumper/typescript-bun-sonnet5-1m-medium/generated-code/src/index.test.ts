import { describe, expect, test, afterEach } from "bun:test";
import { mkdtempSync, rmSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { runVersionBump } from "./index";

// RED: index.ts's runVersionBump does not exist yet.

const tempDirs: string[] = [];

function makeTempProject(initialVersion: string, commitLog: string) {
  const dir = mkdtempSync(join(tmpdir(), "version-bumper-test-"));
  tempDirs.push(dir);

  const packageJsonPath = join(dir, "package.json");
  const commitLogPath = join(dir, "commits.txt");
  const changelogPath = join(dir, "CHANGELOG.md");

  writeFileSync(
    packageJsonPath,
    JSON.stringify({ name: "test-pkg", version: initialVersion }, null, 2) +
      "\n",
  );
  writeFileSync(commitLogPath, commitLog);

  return { dir, packageJsonPath, commitLogPath, changelogPath };
}

afterEach(() => {
  while (tempDirs.length > 0) {
    const dir = tempDirs.pop()!;
    rmSync(dir, { recursive: true, force: true });
  }
});

describe("runVersionBump", () => {
  test("bumps the minor version on a feat commit and writes package.json + CHANGELOG.md", () => {
    const { packageJsonPath, commitLogPath, changelogPath } = makeTempProject(
      "1.0.0",
      "feat: add login page\nchore: tidy up\n",
    );

    const result = runVersionBump({
      packageJsonPath,
      commitLogPath,
      changelogPath,
      date: "2026-07-01",
    });

    expect(result.previousVersion).toBe("1.0.0");
    expect(result.newVersion).toBe("1.1.0");
    expect(result.bumpType).toBe("minor");

    const pkg = JSON.parse(readFileSync(packageJsonPath, "utf-8"));
    expect(pkg.version).toBe("1.1.0");

    const changelog = readFileSync(changelogPath, "utf-8");
    expect(changelog).toContain("## 1.1.0 (2026-07-01)");
    expect(changelog).toContain("- add login page");
  });

  test("bumps the major version on a breaking change and prepends to an existing changelog", () => {
    const { packageJsonPath, commitLogPath, changelogPath } = makeTempProject(
      "1.1.0",
      "feat!: drop legacy endpoint\n",
    );
    writeFileSync(changelogPath, "# Changelog\n\n## 1.1.0 (2026-06-01)\n\n- previous entry\n");

    const result = runVersionBump({
      packageJsonPath,
      commitLogPath,
      changelogPath,
      date: "2026-07-01",
    });

    expect(result.newVersion).toBe("2.0.0");

    const changelog = readFileSync(changelogPath, "utf-8");
    // New entry should appear before the previous one.
    expect(changelog.indexOf("## 2.0.0")).toBeLessThan(
      changelog.indexOf("## 1.1.0 (2026-06-01)"),
    );
  });

  test("throws a meaningful error when package.json has no version field", () => {
    const dir = mkdtempSync(join(tmpdir(), "version-bumper-test-"));
    tempDirs.push(dir);
    const packageJsonPath = join(dir, "package.json");
    const commitLogPath = join(dir, "commits.txt");
    const changelogPath = join(dir, "CHANGELOG.md");
    writeFileSync(packageJsonPath, JSON.stringify({ name: "no-version" }));
    writeFileSync(commitLogPath, "feat: something\n");

    expect(() =>
      runVersionBump({
        packageJsonPath,
        commitLogPath,
        changelogPath,
        date: "2026-07-01",
      }),
    ).toThrow(/missing.*version/i);
  });

  test("throws a meaningful error when the commit log file does not exist", () => {
    const { packageJsonPath, changelogPath } = makeTempProject("1.0.0", "");

    expect(() =>
      runVersionBump({
        packageJsonPath,
        commitLogPath: "/nonexistent/commits.txt",
        changelogPath,
        date: "2026-07-01",
      }),
    ).toThrow(/commit log/i);
  });
});
