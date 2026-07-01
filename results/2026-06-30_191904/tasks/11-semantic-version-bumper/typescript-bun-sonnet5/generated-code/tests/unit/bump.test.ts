// Unit tests for src/bump.ts — the orchestration layer that reads a version
// file + a commit log, computes the next version, and writes the version
// file + changelog back out. This is the logic bump-version.ts's CLI wraps;
// testing it directly (rather than shelling out to the CLI) keeps these
// tests fast or "bun test" while the end-to-end pipeline behavior is
// verified separately through the GitHub Actions workflow via act.
import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { runBump } from "../../src/bump.ts";

let dir: string;

beforeEach(async () => {
  dir = await mkdtemp(join(tmpdir(), "svb-bump-"));
});

afterEach(async () => {
  await rm(dir, { recursive: true, force: true });
});

const FEAT_FIX_LOG = `commit 1111111111111111111111111111111111111111
Author: A <a@example.com>
Date:   Mon Jan 5 10:00:00 2026 +0000

    feat(auth): add OAuth login support

commit 2222222222222222222222222222222222222222
Author: A <a@example.com>
Date:   Mon Jan 5 09:00:00 2026 +0000

    fix(parser): handle trailing commas correctly
`;

async function writePackageJson(version: string): Promise<string> {
  const path = join(dir, "package.json");
  await Bun.write(path, JSON.stringify({ name: "demo", version }, null, 2));
  return path;
}

async function writeCommitLog(contents: string): Promise<string> {
  const path = join(dir, "commits.log");
  await Bun.write(path, contents);
  return path;
}

describe("runBump", () => {
  test("bumps minor when the highest-precedence commit is a feat, and writes the version file", async () => {
    const versionFilePath = await writePackageJson("1.2.3");
    const commitsLogPath = await writeCommitLog(FEAT_FIX_LOG);
    const changelogPath = join(dir, "CHANGELOG.md");

    const result = await runBump({
      versionFilePath,
      commitsLogPath,
      changelogPath,
      date: "2026-01-05",
    });

    expect(result.previousVersion).toBe("1.2.3");
    expect(result.newVersion).toBe("1.3.0");
    expect(result.bumpType).toBe("minor");

    const updated = JSON.parse(await Bun.file(versionFilePath).text());
    expect(updated.version).toBe("1.3.0");
  });

  test("writes a changelog entry prepended above any existing content", async () => {
    const versionFilePath = await writePackageJson("1.2.3");
    const commitsLogPath = await writeCommitLog(FEAT_FIX_LOG);
    const changelogPath = join(dir, "CHANGELOG.md");
    await Bun.write(changelogPath, "# Changelog\n\n## [1.2.3] - 2026-01-01\n\nOlder entry.\n");

    await runBump({ versionFilePath, commitsLogPath, changelogPath, date: "2026-01-05" });

    const changelog = await Bun.file(changelogPath).text();
    expect(changelog).toBe(
      `# Changelog

## [1.3.0] - 2026-01-05

### Features

- auth: add OAuth login support (1111111)

### Fixes

- parser: handle trailing commas correctly (2222222)

## [1.2.3] - 2026-01-01

Older entry.
`,
    );
  });

  test("creates a new changelog file with a header when none exists", async () => {
    const versionFilePath = await writePackageJson("1.2.3");
    const commitsLogPath = await writeCommitLog(FEAT_FIX_LOG);
    const changelogPath = join(dir, "CHANGELOG.md");

    await runBump({ versionFilePath, commitsLogPath, changelogPath, date: "2026-01-05" });

    const changelog = await Bun.file(changelogPath).text();
    expect(changelog.startsWith("# Changelog\n\n## [1.3.0] - 2026-01-05\n")).toBe(true);
  });

  test("a breaking-change commit bumps major regardless of other commits", async () => {
    const versionFilePath = await writePackageJson("1.2.3");
    const commitsLogPath = await writeCommitLog(
      `commit 3333333333333333333333333333333333333333
Author: A <a@example.com>
Date:   Mon Jan 5 10:00:00 2026 +0000

    feat(api)!: redesign response envelope
`,
    );
    const changelogPath = join(dir, "CHANGELOG.md");

    const result = await runBump({ versionFilePath, commitsLogPath, changelogPath, date: "2026-01-05" });

    expect(result.newVersion).toBe("2.0.0");
    expect(result.bumpType).toBe("major");
  });

  test("a fix-only log bumps patch", async () => {
    const versionFilePath = await writePackageJson("1.2.3");
    const commitsLogPath = await writeCommitLog(
      `commit 4444444444444444444444444444444444444444
Author: A <a@example.com>
Date:   Mon Jan 5 10:00:00 2026 +0000

    fix: correct rounding error
`,
    );
    const changelogPath = join(dir, "CHANGELOG.md");

    const result = await runBump({ versionFilePath, commitsLogPath, changelogPath, date: "2026-01-05" });

    expect(result.newVersion).toBe("1.2.4");
    expect(result.bumpType).toBe("patch");
  });

  test("when no commit is conventional, the version and changelog are left untouched", async () => {
    const versionFilePath = await writePackageJson("1.2.3");
    const commitsLogPath = await writeCommitLog(
      `commit 5555555555555555555555555555555555555555
Author: A <a@example.com>
Date:   Mon Jan 5 10:00:00 2026 +0000

    chore: bump lockfile
`,
    );
    const changelogPath = join(dir, "CHANGELOG.md");

    const result = await runBump({ versionFilePath, commitsLogPath, changelogPath, date: "2026-01-05" });

    expect(result.newVersion).toBe("1.2.3");
    expect(result.bumpType).toBe("none");
    expect(await Bun.file(versionFilePath).text()).toContain('"version": "1.2.3"');
    expect(await Bun.file(changelogPath).exists()).toBe(false);
  });

  test("raises a clear error when the commit log file does not exist", async () => {
    const versionFilePath = await writePackageJson("1.2.3");
    const changelogPath = join(dir, "CHANGELOG.md");

    await expect(
      runBump({
        versionFilePath,
        commitsLogPath: join(dir, "missing.log"),
        changelogPath,
        date: "2026-01-05",
      }),
    ).rejects.toThrow(/commit log not found/i);
  });
});
