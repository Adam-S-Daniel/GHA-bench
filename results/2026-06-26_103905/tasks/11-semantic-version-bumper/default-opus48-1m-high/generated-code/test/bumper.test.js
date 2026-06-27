// Unit tests for the semantic version bumper core library.
//
// Written test-first (red/green TDD): each `describe` block below was added as a
// failing test before the corresponding code existed in ../src/bumper.js.
// Run with: `node --test`

import { test, describe } from "node:test";
import assert from "node:assert/strict";

import {
  parseCommits,
  determineBump,
  bumpVersion,
  readVersion,
  writeVersion,
  generateChangelog,
  bump,
} from "../src/bumper.js";

import fs from "node:fs";
import os from "node:os";
import path from "node:path";

// Helper: create a throwaway temp dir for filesystem tests.
function tmpDir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), "svb-"));
}

describe("parseCommits", () => {
  test("parses a single conventional commit header", () => {
    const log = "feat: add login page";
    const commits = parseCommits(log);
    assert.equal(commits.length, 1);
    assert.deepEqual(commits[0], {
      type: "feat",
      scope: null,
      breaking: false,
      description: "add login page",
    });
  });

  test("parses a scope from the header", () => {
    const commits = parseCommits("fix(auth): handle expired tokens");
    assert.equal(commits[0].type, "fix");
    assert.equal(commits[0].scope, "auth");
    assert.equal(commits[0].description, "handle expired tokens");
  });

  test("flags a breaking change via the `!` shorthand", () => {
    const commits = parseCommits("feat(api)!: drop v1 endpoints");
    assert.equal(commits[0].breaking, true);
  });

  test("flags a breaking change via the BREAKING CHANGE footer", () => {
    const log = "feat: new config format\n\nBREAKING CHANGE: config keys renamed";
    const commits = parseCommits(log);
    assert.equal(commits[0].breaking, true);
  });

  test("splits multiple commits on the --==COMMIT==-- delimiter", () => {
    const log = ["feat: a", "--==COMMIT==--", "fix: b"].join("\n");
    const commits = parseCommits(log);
    assert.equal(commits.length, 2);
    assert.equal(commits[0].type, "feat");
    assert.equal(commits[1].type, "fix");
  });

  test("ignores blank entries and non-conventional lines", () => {
    const log = ["feat: real", "--==COMMIT==--", "   ", "--==COMMIT==--", "Merge branch 'x'"].join("\n");
    const commits = parseCommits(log);
    // Only the conventional commit is kept; junk is dropped.
    assert.equal(commits.length, 1);
    assert.equal(commits[0].description, "real");
  });
});

describe("determineBump", () => {
  const c = (type, breaking = false) => ({ type, scope: null, breaking, description: "x" });

  test("breaking change wins -> major", () => {
    assert.equal(determineBump([c("fix"), c("feat", true)]), "major");
  });

  test("feat without breaking -> minor", () => {
    assert.equal(determineBump([c("fix"), c("feat")]), "minor");
  });

  test("only fixes -> patch", () => {
    assert.equal(determineBump([c("fix"), c("fix")]), "patch");
  });

  test("only non-bumping types (chore/docs) -> null", () => {
    assert.equal(determineBump([c("chore"), c("docs")]), null);
  });

  test("empty list -> null", () => {
    assert.equal(determineBump([]), null);
  });
});

describe("bumpVersion", () => {
  test("major bump zeroes minor and patch", () => {
    assert.equal(bumpVersion("1.4.2", "major"), "2.0.0");
  });

  test("minor bump zeroes patch", () => {
    assert.equal(bumpVersion("1.4.2", "minor"), "1.5.0");
  });

  test("patch bump increments patch", () => {
    assert.equal(bumpVersion("1.4.2", "patch"), "1.4.3");
  });

  test("tolerates a leading v", () => {
    assert.equal(bumpVersion("v2.0.0", "minor"), "2.1.0");
  });

  test("rejects a malformed version with a clear error", () => {
    assert.throws(() => bumpVersion("1.2", "patch"), /Invalid semantic version/);
  });

  test("rejects an unknown bump type", () => {
    assert.throws(() => bumpVersion("1.2.3", "mega"), /Unknown bump type/);
  });
});

describe("readVersion / writeVersion", () => {
  test("reads the version field from a package.json", () => {
    const dir = tmpDir();
    const file = path.join(dir, "package.json");
    fs.writeFileSync(file, JSON.stringify({ name: "x", version: "1.2.3" }, null, 2));
    assert.equal(readVersion(file), "1.2.3");
  });

  test("reads a plain VERSION file", () => {
    const dir = tmpDir();
    const file = path.join(dir, "VERSION");
    fs.writeFileSync(file, "0.9.1\n");
    assert.equal(readVersion(file), "0.9.1");
  });

  test("gives a clear error when the file is missing", () => {
    assert.throws(() => readVersion("/no/such/file"), /Version file not found/);
  });

  test("gives a clear error when package.json has no version", () => {
    const dir = tmpDir();
    const file = path.join(dir, "package.json");
    fs.writeFileSync(file, JSON.stringify({ name: "x" }));
    assert.throws(() => readVersion(file), /no "version" field/);
  });

  test("writeVersion preserves package.json keys and updates only version", () => {
    const dir = tmpDir();
    const file = path.join(dir, "package.json");
    fs.writeFileSync(file, JSON.stringify({ name: "x", version: "1.2.3", scripts: {} }, null, 2));
    writeVersion(file, "2.0.0");
    const parsed = JSON.parse(fs.readFileSync(file, "utf8"));
    assert.equal(parsed.version, "2.0.0");
    assert.equal(parsed.name, "x");
    assert.deepEqual(parsed.scripts, {});
  });

  test("writeVersion writes a bare version to a plain file", () => {
    const dir = tmpDir();
    const file = path.join(dir, "VERSION");
    fs.writeFileSync(file, "1.0.0\n");
    writeVersion(file, "1.0.1");
    assert.equal(fs.readFileSync(file, "utf8").trim(), "1.0.1");
  });
});

describe("generateChangelog", () => {
  const commits = [
    { type: "feat", scope: "ui", breaking: false, description: "dark mode" },
    { type: "feat", scope: null, breaking: false, description: "search box" },
    { type: "fix", scope: "api", breaking: false, description: "null guard" },
    { type: "feat", scope: "api", breaking: true, description: "drop v1" },
    { type: "chore", scope: null, breaking: false, description: "bump deps" },
  ];

  test("renders a dated header and grouped sections", () => {
    const md = generateChangelog("1.2.0", commits, "2026-06-27");
    assert.match(md, /^## \[1\.2\.0\] - 2026-06-27/m);
    assert.match(md, /### Breaking Changes/);
    assert.match(md, /### Features/);
    assert.match(md, /### Bug Fixes/);
    // scope is rendered as a bold prefix
    assert.match(md, /- \*\*ui:\*\* dark mode/);
    assert.match(md, /- \*\*api:\*\* drop v1/);
    assert.match(md, /- null guard/.source ? /- \*\*api:\*\* null guard/ : /- null guard/);
    // chore is not a user-facing section
    assert.doesNotMatch(md, /bump deps/);
  });

  test("omits empty sections", () => {
    const md = generateChangelog("1.0.1", [
      { type: "fix", scope: null, breaking: false, description: "typo" },
    ], "2026-06-27");
    assert.match(md, /### Bug Fixes/);
    assert.doesNotMatch(md, /### Features/);
    assert.doesNotMatch(md, /### Breaking Changes/);
  });
});

describe("bump (end-to-end orchestration)", () => {
  // Build a temp project: a version file + a commit log fixture.
  function project(version, log, { pkg = false } = {}) {
    const dir = tmpDir();
    const versionFile = path.join(dir, pkg ? "package.json" : "VERSION");
    if (pkg) {
      fs.writeFileSync(versionFile, JSON.stringify({ name: "demo", version }, null, 2));
    } else {
      fs.writeFileSync(versionFile, version + "\n");
    }
    const commitsFile = path.join(dir, "commits.log");
    fs.writeFileSync(commitsFile, log);
    const changelogFile = path.join(dir, "CHANGELOG.md");
    return { dir, versionFile, commitsFile, changelogFile };
  }

  test("feat bumps minor, updates file, prepends changelog", () => {
    const p = project("1.1.0", "feat: cool thing");
    const result = bump({ ...p, date: "2026-06-27" });

    assert.equal(result.oldVersion, "1.1.0");
    assert.equal(result.newVersion, "1.2.0");
    assert.equal(result.bumpType, "minor");
    assert.equal(readVersion(p.versionFile), "1.2.0");
    assert.match(fs.readFileSync(p.changelogFile, "utf8"), /## \[1\.2\.0\] - 2026-06-27/);
  });

  test("fix bumps patch", () => {
    const p = project("1.1.0", "fix: a bug");
    assert.equal(bump({ ...p, date: "2026-06-27" }).newVersion, "1.1.1");
  });

  test("breaking bumps major", () => {
    const p = project("1.1.0", "feat!: rewrite");
    assert.equal(bump({ ...p, date: "2026-06-27" }).newVersion, "2.0.0");
  });

  test("works against package.json too", () => {
    const p = project("3.4.5", "feat: x", { pkg: true });
    assert.equal(bump({ ...p, date: "2026-06-27" }).newVersion, "3.5.0");
    assert.equal(JSON.parse(fs.readFileSync(p.versionFile, "utf8")).version, "3.5.0");
  });

  test("prepends new entries above older ones in the changelog", () => {
    const p = project("1.0.0", "fix: one");
    bump({ ...p, date: "2026-06-27" }); // -> 1.0.1
    fs.writeFileSync(p.versionFile, "1.0.1\n");
    fs.writeFileSync(p.commitsFile, "feat: two");
    bump({ ...p, date: "2026-06-28" }); // -> 1.1.0
    const md = fs.readFileSync(p.changelogFile, "utf8");
    assert.ok(md.indexOf("[1.1.0]") < md.indexOf("[1.0.1]"), "newest entry first");
  });

  test("throws a meaningful error when no commits warrant a bump", () => {
    const p = project("1.0.0", "chore: tidy up");
    assert.throws(() => bump({ ...p, date: "2026-06-27" }), /No conventional commits/);
  });
});
