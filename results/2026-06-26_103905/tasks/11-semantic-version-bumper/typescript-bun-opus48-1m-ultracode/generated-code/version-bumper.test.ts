// Unit tests for the semantic version bumper.
//
// Methodology: strict red/green TDD. Each `describe` block below was written as
// a FAILING test first, then the minimum code in `version-bumper.ts` was added
// to make it pass, then refactored. The commit history of this file walks
// through that cycle.
//
// These are the FAST, pure-logic tests. They never touch git, Docker, or act —
// they exercise the exported functions directly. The end-to-end pipeline is
// validated separately through GitHub Actions via `act` (see act-harness.test.ts).

import { describe, expect, test } from "bun:test";
import {
  parseVersion,
  formatVersion,
  parseCommit,
  determineBump,
  bumpVersion,
  splitCommits,
  parseCommitLog,
  generateChangelog,
  extractVersion,
  applyVersionToContent,
  prependChangelog,
  readVersionFile,
  writeVersionFile,
  updateChangelogFile,
  parseArgs,
  runBump,
  readCommitsFromGit,
} from "./version-bumper.ts";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

describe("parseVersion", () => {
  test("parses a plain semver string into its numeric components", () => {
    expect(parseVersion("1.2.3")).toEqual({ major: 1, minor: 2, patch: 3 });
  });

  test("tolerates a leading 'v' and surrounding whitespace", () => {
    expect(parseVersion("  v0.10.42 \n")).toEqual({
      major: 0,
      minor: 10,
      patch: 42,
    });
  });

  test("throws a meaningful error on an invalid version", () => {
    expect(() => parseVersion("1.2")).toThrow(/Invalid semantic version/);
    expect(() => parseVersion("not-a-version")).toThrow(
      /Invalid semantic version/,
    );
  });
});

describe("formatVersion", () => {
  test("renders a SemVer back to MAJOR.MINOR.PATCH", () => {
    expect(formatVersion({ major: 2, minor: 0, patch: 7 })).toBe("2.0.7");
  });

  test("round-trips with parseVersion", () => {
    expect(formatVersion(parseVersion("1.4.9"))).toBe("1.4.9");
  });
});

describe("parseCommit", () => {
  test("extracts type and description from a feat commit", () => {
    const c = parseCommit("feat: add login page");
    expect(c.type).toBe("feat");
    expect(c.description).toBe("add login page");
    expect(c.scope).toBeNull();
    expect(c.breaking).toBe(false);
  });

  test("captures the scope when present", () => {
    const c = parseCommit("fix(api): handle null response");
    expect(c.type).toBe("fix");
    expect(c.scope).toBe("api");
    expect(c.description).toBe("handle null response");
  });

  test("flags a breaking change via the '!' marker", () => {
    const c = parseCommit("feat(config)!: drop v1 format");
    expect(c.type).toBe("feat");
    expect(c.scope).toBe("config");
    expect(c.breaking).toBe(true);
  });

  test("flags a breaking change via a 'BREAKING CHANGE:' footer", () => {
    const c = parseCommit(
      "feat: new auth flow\n\nBREAKING CHANGE: old tokens are rejected",
    );
    expect(c.breaking).toBe(true);
    expect(c.description).toBe("new auth flow");
  });

  test("also accepts the hyphenated 'BREAKING-CHANGE:' footer", () => {
    const c = parseCommit("fix: tweak\n\nBREAKING-CHANGE: behavior shifted");
    expect(c.breaking).toBe(true);
  });

  test("marks a non-conventional message with a null type", () => {
    const c = parseCommit("just some random commit");
    expect(c.type).toBeNull();
    expect(c.breaking).toBe(false);
  });
});

describe("determineBump", () => {
  test("returns 'minor' when the strongest signal is a feat", () => {
    const commits = [parseCommit("feat: a"), parseCommit("fix: b")];
    expect(determineBump(commits)).toBe("minor");
  });

  test("returns 'patch' when only fixes are present", () => {
    const commits = [parseCommit("fix: a"), parseCommit("docs: b")];
    expect(determineBump(commits)).toBe("patch");
  });

  test("returns 'major' when any commit is breaking, even amongst feats/fixes", () => {
    const commits = [
      parseCommit("feat: a"),
      parseCommit("fix!: b"),
      parseCommit("feat: c"),
    ];
    expect(determineBump(commits)).toBe("major");
  });

  test("returns 'none' when no commit warrants a release", () => {
    const commits = [parseCommit("docs: a"), parseCommit("chore: b")];
    expect(determineBump(commits)).toBe("none");
  });
});

describe("bumpVersion", () => {
  const base: SemVerLike = { major: 1, minor: 4, patch: 2 };

  test("major bump resets minor and patch", () => {
    expect(formatVersion(bumpVersion(base, "major"))).toBe("2.0.0");
  });

  test("minor bump resets patch", () => {
    expect(formatVersion(bumpVersion(base, "minor"))).toBe("1.5.0");
  });

  test("patch bump increments only patch", () => {
    expect(formatVersion(bumpVersion(base, "patch"))).toBe("1.4.3");
  });

  test("none bump leaves the version untouched", () => {
    expect(formatVersion(bumpVersion(base, "none"))).toBe("1.4.2");
  });
});

// Local alias so the test file does not need to import the SemVer type name
// just for an inline literal.
type SemVerLike = { major: number; minor: number; patch: number };

describe("splitCommits", () => {
  test("splits a log on the '--- COMMIT ---' delimiter", () => {
    const log = [
      "feat: one",
      "--- COMMIT ---",
      "fix: two",
      "--- COMMIT ---",
      "chore: three",
    ].join("\n");
    expect(splitCommits(log)).toEqual(["feat: one", "fix: two", "chore: three"]);
  });

  test("splits a log on the NUL/record-separator (git --format=%B%x1e) form", () => {
    const log = "feat: one\x1efix: two\x1e";
    expect(splitCommits(log)).toEqual(["feat: one", "fix: two"]);
  });

  test("treats a single message with no delimiter as one commit", () => {
    expect(splitCommits("feat: just one")).toEqual(["feat: just one"]);
  });

  test("preserves a multi-line body within a delimited commit", () => {
    const log =
      "feat: x\n\nBREAKING CHANGE: y\n--- COMMIT ---\nfix: z";
    expect(splitCommits(log)).toEqual(["feat: x\n\nBREAKING CHANGE: y", "fix: z"]);
  });

  test("ignores empty/whitespace-only segments", () => {
    expect(splitCommits("\n--- COMMIT ---\nfeat: a\n--- COMMIT ---\n   ")).toEqual([
      "feat: a",
    ]);
  });
});

describe("parseCommitLog", () => {
  test("parses a delimited log into structured commits", () => {
    const log = "feat(ui): a\n--- COMMIT ---\nfix: b";
    const commits = parseCommitLog(log);
    expect(commits).toHaveLength(2);
    expect(commits[0]!.type).toBe("feat");
    expect(commits[0]!.scope).toBe("ui");
    expect(commits[1]!.type).toBe("fix");
  });
});

describe("generateChangelog", () => {
  const date = "2026-06-28";

  test("groups breaking/feat/fix commits into the expected sections", () => {
    const commits = parseCommitLog(
      [
        "feat(auth): add login page",
        "--- COMMIT ---",
        "fix(api): handle null response",
        "--- COMMIT ---",
        "feat!: drop v1 config\n\nBREAKING CHANGE: removed",
      ].join("\n"),
    );
    const entry = generateChangelog("2.0.0", commits, date);
    expect(entry).toBe(
      [
        "## [2.0.0] - 2026-06-28",
        "",
        "### BREAKING CHANGES",
        "",
        "- drop v1 config",
        "",
        "### Features",
        "",
        "- **auth:** add login page",
        "- drop v1 config",
        "",
        "### Bug Fixes",
        "",
        "- **api:** handle null response",
        "",
      ].join("\n"),
    );
  });

  test("omits empty sections (patch release with only a fix)", () => {
    const commits = parseCommitLog("fix: correct rounding");
    const entry = generateChangelog("1.0.1", commits, date);
    expect(entry).toBe(
      [
        "## [1.0.1] - 2026-06-28",
        "",
        "### Bug Fixes",
        "",
        "- correct rounding",
        "",
      ].join("\n"),
    );
  });

  test("falls back to a generic note when there is nothing to list", () => {
    const commits = parseCommitLog("chore: tidy up");
    const entry = generateChangelog("1.0.0", commits, date);
    expect(entry).toContain("## [1.0.0] - 2026-06-28");
    expect(entry).toContain("_No user-facing changes._");
  });
});

describe("extractVersion", () => {
  test("returns the trimmed contents of a plain version file", () => {
    expect(extractVersion("  3.1.4\n", false)).toBe("3.1.4");
  });

  test("reads the .version field out of package.json", () => {
    const pkg = JSON.stringify({ name: "demo", version: "4.5.6" });
    expect(extractVersion(pkg, true)).toBe("4.5.6");
  });

  test("throws when package.json has no version field", () => {
    expect(() => extractVersion(JSON.stringify({ name: "demo" }), true)).toThrow(
      /no "version" field/,
    );
  });

  test("throws on malformed JSON", () => {
    expect(() => extractVersion("{ not json", true)).toThrow(/Failed to parse JSON/);
  });
});

describe("applyVersionToContent", () => {
  test("a plain version file is replaced with the new version plus newline", () => {
    expect(applyVersionToContent("1.0.0\n", false, "1.1.0")).toBe("1.1.0\n");
  });

  test("package.json keeps every other field and only the version changes", () => {
    const pkg = `{\n  "name": "demo",\n  "version": "1.0.0",\n  "type": "module"\n}\n`;
    const updated = applyVersionToContent(pkg, true, "2.0.0");
    expect(updated).toBe(
      `{\n  "name": "demo",\n  "version": "2.0.0",\n  "type": "module"\n}\n`,
    );
  });

  test("throws when package.json has no version field to update", () => {
    expect(() => applyVersionToContent(`{"name":"x"}`, true, "1.0.0")).toThrow(
      /no "version" field/,
    );
  });

  test("updates the TOP-LEVEL version, not a nested one that appears earlier", () => {
    // A nested "version" precedes the real top-level "version" textually. A
    // naive first-match replace would corrupt the nested key and leave the real
    // version stale; the parse-and-reserialize approach targets the right one.
    const pkg = `{\n  "publishConfig": { "version": "9.9.9" },\n  "version": "1.0.0"\n}\n`;
    const out = applyVersionToContent(pkg, true, "1.1.0");
    const reparsed = JSON.parse(out);
    expect(reparsed.version).toBe("1.1.0");
    expect(reparsed.publishConfig.version).toBe("9.9.9");
  });
});

describe("prependChangelog", () => {
  const entryA = "## [1.0.0] - 2026-06-01\n\n### Features\n\n- first\n";
  const entryB = "## [1.1.0] - 2026-06-28\n\n### Features\n\n- second\n";

  test("creates a header and the entry for an empty changelog", () => {
    const out = prependChangelog("", entryA);
    expect(out).toContain("# Changelog");
    expect(out).toContain("## [1.0.0]");
    // The header must appear exactly once.
    expect(out.match(/# Changelog/g)).toHaveLength(1);
  });

  test("inserts new entries newest-first, above existing ones", () => {
    const withA = prependChangelog("", entryA);
    const withB = prependChangelog(withA, entryB);
    expect(withB.indexOf("## [1.1.0]")).toBeLessThan(withB.indexOf("## [1.0.0]"));
    expect(withB.match(/# Changelog/g)).toHaveLength(1);
  });
});

describe("file IO round-trips", () => {
  function freshDir(): string {
    return mkdtempSync(join(tmpdir(), "svb-test-"));
  }

  test("readVersionFile / writeVersionFile round-trip a plain file", async () => {
    const dir = freshDir();
    const file = join(dir, "version.txt");
    writeFileSync(file, "1.2.3\n");

    const parsed = await readVersionFile(file);
    expect(parsed.version).toBe("1.2.3");
    expect(parsed.isJson).toBe(false);

    await writeVersionFile(parsed, "1.3.0");
    expect(readFileSync(file, "utf8")).toBe("1.3.0\n");
  });

  test("readVersionFile detects package.json by extension and preserves fields", async () => {
    const dir = freshDir();
    const file = join(dir, "package.json");
    writeFileSync(file, `{\n  "name": "demo",\n  "version": "0.9.0"\n}\n`);

    const parsed = await readVersionFile(file);
    expect(parsed.isJson).toBe(true);
    expect(parsed.version).toBe("0.9.0");

    await writeVersionFile(parsed, "1.0.0");
    const after = JSON.parse(readFileSync(file, "utf8"));
    expect(after.name).toBe("demo");
    expect(after.version).toBe("1.0.0");
  });

  test("readVersionFile throws a clear error when the file is missing", async () => {
    const dir = freshDir();
    await expect(readVersionFile(join(dir, "nope.txt"))).rejects.toThrow(
      /Version file not found/,
    );
  });

  test("updateChangelogFile creates the file then prepends to it", async () => {
    const dir = freshDir();
    const file = join(dir, "CHANGELOG.md");

    await updateChangelogFile(file, "## [1.0.0] - 2026-06-01\n\n### Features\n\n- a\n");
    await updateChangelogFile(file, "## [1.1.0] - 2026-06-28\n\n### Features\n\n- b\n");

    const content = readFileSync(file, "utf8");
    expect(content.indexOf("## [1.1.0]")).toBeLessThan(content.indexOf("## [1.0.0]"));
    expect(content.match(/# Changelog/g)).toHaveLength(1);
  });
});

describe("parseArgs", () => {
  test("applies sensible defaults when given no flags", () => {
    const opts = parseArgs([]);
    expect(opts.versionFile).toBe("version.txt");
    expect(opts.changelogFile).toBe("CHANGELOG.md");
    expect(opts.commitsFile).toBeNull();
    expect(opts.dryRun).toBe(false);
  });

  test("parses every supported flag", () => {
    const opts = parseArgs([
      "--version-file",
      "package.json",
      "--commits",
      "commits.log",
      "--changelog",
      "CHANGES.md",
      "--date",
      "2026-01-02",
      "--dry-run",
    ]);
    expect(opts.versionFile).toBe("package.json");
    expect(opts.commitsFile).toBe("commits.log");
    expect(opts.changelogFile).toBe("CHANGES.md");
    expect(opts.date).toBe("2026-01-02");
    expect(opts.dryRun).toBe(true);
  });

  test("supports --no-changelog to disable changelog writing", () => {
    expect(parseArgs(["--no-changelog"]).changelogFile).toBeNull();
  });

  test("throws a helpful error on an unknown flag", () => {
    expect(() => parseArgs(["--bogus"])).toThrow(/Unknown argument/);
  });

  test("throws when a value-taking flag is missing its value", () => {
    expect(() => parseArgs(["--version-file"])).toThrow(/expects a value/);
  });
});

describe("runBump (end-to-end orchestration over fixtures)", () => {
  function scenario(version: string, commitsLog: string): {
    dir: string;
    versionFile: string;
    commitsFile: string;
    changelogFile: string;
  } {
    const dir = mkdtempSync(join(tmpdir(), "svb-run-"));
    const versionFile = join(dir, "version.txt");
    const commitsFile = join(dir, "commits.log");
    const changelogFile = join(dir, "CHANGELOG.md");
    writeFileSync(versionFile, `${version}\n`);
    writeFileSync(commitsFile, commitsLog);
    return { dir, versionFile, commitsFile, changelogFile };
  }

  const TODAY = "2026-06-28";

  test("feat commit drives a minor bump and writes both files", async () => {
    const s = scenario("1.1.0", "feat: add dark mode");
    const result = await runBump(
      {
        versionFile: s.versionFile,
        commitsFile: s.commitsFile,
        changelogFile: s.changelogFile,
        gitRange: null,
        date: null,
        dryRun: false,
      },
      TODAY,
    );
    expect(result.previousVersion).toBe("1.1.0");
    expect(result.newVersion).toBe("1.2.0");
    expect(result.bump).toBe("minor");
    expect(result.changed).toBe(true);
    expect(readFileSync(s.versionFile, "utf8")).toBe("1.2.0\n");
    expect(readFileSync(s.changelogFile, "utf8")).toContain("## [1.2.0] - 2026-06-28");
  });

  test("fix commit drives a patch bump", async () => {
    const s = scenario("1.1.0", "fix: stop crash on empty input");
    const result = await runBump(
      {
        versionFile: s.versionFile,
        commitsFile: s.commitsFile,
        changelogFile: s.changelogFile,
        gitRange: null,
        date: null,
        dryRun: false,
      },
      TODAY,
    );
    expect(result.newVersion).toBe("1.1.1");
    expect(result.bump).toBe("patch");
  });

  test("breaking change drives a major bump", async () => {
    const s = scenario(
      "1.1.0",
      "feat!: rewrite public API\n\nBREAKING CHANGE: everything moved",
    );
    const result = await runBump(
      {
        versionFile: s.versionFile,
        commitsFile: s.commitsFile,
        changelogFile: s.changelogFile,
        gitRange: null,
        date: null,
        dryRun: false,
      },
      TODAY,
    );
    expect(result.newVersion).toBe("2.0.0");
    expect(result.bump).toBe("major");
  });

  test("no releasable commits leaves the version file untouched", async () => {
    const s = scenario("1.1.0", "chore: bump deps\n--- COMMIT ---\ndocs: typo");
    const result = await runBump(
      {
        versionFile: s.versionFile,
        commitsFile: s.commitsFile,
        changelogFile: s.changelogFile,
        gitRange: null,
        date: null,
        dryRun: false,
      },
      TODAY,
    );
    expect(result.bump).toBe("none");
    expect(result.changed).toBe(false);
    expect(result.newVersion).toBe("1.1.0");
    // Version file is byte-for-byte unchanged; no changelog created.
    expect(readFileSync(s.versionFile, "utf8")).toBe("1.1.0\n");
    expect(existsSync(s.changelogFile)).toBe(false);
  });

  test("--dry-run computes the bump but writes nothing", async () => {
    const s = scenario("1.1.0", "feat: add dark mode");
    const result = await runBump(
      {
        versionFile: s.versionFile,
        commitsFile: s.commitsFile,
        changelogFile: s.changelogFile,
        gitRange: null,
        date: null,
        dryRun: true,
      },
      TODAY,
    );
    expect(result.newVersion).toBe("1.2.0");
    expect(readFileSync(s.versionFile, "utf8")).toBe("1.1.0\n"); // untouched
    expect(existsSync(s.changelogFile)).toBe(false);
  });

  test("works against a package.json version file", async () => {
    const dir = mkdtempSync(join(tmpdir(), "svb-pkg-"));
    const versionFile = join(dir, "package.json");
    const commitsFile = join(dir, "commits.log");
    writeFileSync(versionFile, `{\n  "name": "demo",\n  "version": "0.4.0"\n}\n`);
    writeFileSync(commitsFile, "fix: patch it");
    const result = await runBump(
      {
        versionFile,
        commitsFile,
        changelogFile: null,
        gitRange: null,
        date: null,
        dryRun: false,
      },
      TODAY,
    );
    expect(result.newVersion).toBe("0.4.1");
    expect(JSON.parse(readFileSync(versionFile, "utf8")).version).toBe("0.4.1");
  });

  test("throws a clear error when the commits file is missing", async () => {
    const s = scenario("1.0.0", "feat: x");
    await expect(
      runBump(
        {
          versionFile: s.versionFile,
          commitsFile: join(s.dir, "does-not-exist.log"),
          changelogFile: null,
          gitRange: null,
          date: null,
          dryRun: false,
        },
        TODAY,
      ),
    ).rejects.toThrow(/Commit log file not found/);
  });
});

describe("readCommitsFromGit", () => {
  test("reads conventional commits from a real temporary git repo", async () => {
    const dir = mkdtempSync(join(tmpdir(), "svb-git-"));
    const git = (...args: string[]) =>
      spawnSync("git", args, { cwd: dir, encoding: "utf8" });
    git("init", "-q");
    git("config", "user.email", "t@example.com");
    git("config", "user.name", "Test");
    writeFileSync(join(dir, "a.txt"), "a");
    git("add", ".");
    git("commit", "-q", "-m", "feat: first feature");
    writeFileSync(join(dir, "b.txt"), "b");
    git("add", ".");
    git("commit", "-q", "-m", "fix: a bug");

    const log = await readCommitsFromGit(null, dir);
    const commits = parseCommitLog(log);
    const types = commits.map((c) => c.type).sort();
    expect(types).toEqual(["feat", "fix"]);
  });
});
