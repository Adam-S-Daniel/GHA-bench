'use strict';
// Unit tests for the semantic version bumper.
//
// Built with red/green TDD: each describe() block below was added as a
// failing test first, then the minimum implementation was written in
// src/semver-bump.js to make it pass, then refactored.
//
// Uses only the built-in node:test runner - zero dependencies, so the CI
// container needs nothing beyond Node itself.

const test = require('node:test');
const assert = require('node:assert');

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const {
  parseVersion,
  determineBump,
  bumpVersion,
  parseCommitLog,
  readVersionFile,
  writeVersionFile,
  generateChangelogEntry,
  prependChangelog,
  run,
} = require('../src/semver-bump.js');

// Scratch directory helper so file-IO tests never touch the real project.
const tmpdir = () => fs.mkdtempSync(path.join(os.tmpdir(), 'semver-bump-test-'));

const FIXTURES = path.join(__dirname, '..', 'fixtures');
const fixture = (name) => fs.readFileSync(path.join(FIXTURES, name), 'utf8');

// ---------------------------------------------------------------------------
// Cycle 1: parseVersion - turn "1.2.3" into { major, minor, patch }
// ---------------------------------------------------------------------------
test('parseVersion parses a valid semantic version', () => {
  assert.deepStrictEqual(parseVersion('1.2.3'), { major: 1, minor: 2, patch: 3 });
});

test('parseVersion tolerates surrounding whitespace and a leading "v"', () => {
  assert.deepStrictEqual(parseVersion(' v10.0.7\n'), { major: 10, minor: 0, patch: 7 });
});

test('parseVersion rejects invalid versions with a meaningful error', () => {
  for (const bad of ['1.2', 'banana', '1.2.3.4', '', null]) {
    assert.throws(() => parseVersion(bad), /Invalid semantic version/);
  }
});

// ---------------------------------------------------------------------------
// Cycle 2: determineBump - map conventional commits to a bump type.
// Rules: breaking -> major, feat -> minor, fix -> patch, anything else -> no
// bump. The strongest bump across all commits wins.
// ---------------------------------------------------------------------------
const commit = (subject, body = '') => ({ subject, body });

test('determineBump: feat commits produce a minor bump', () => {
  assert.strictEqual(determineBump([commit('feat: add login')]), 'minor');
  assert.strictEqual(determineBump([commit('feat(api): add pagination')]), 'minor');
});

test('determineBump: fix commits produce a patch bump', () => {
  assert.strictEqual(determineBump([commit('fix: correct token refresh')]), 'patch');
  assert.strictEqual(determineBump([commit('fix(auth): handle expiry')]), 'patch');
});

test('determineBump: breaking changes produce a major bump', () => {
  // "!" after the type marks a breaking change...
  assert.strictEqual(determineBump([commit('feat!: drop node 16')]), 'major');
  assert.strictEqual(determineBump([commit('fix(core)!: rename config key')]), 'major');
  // ...and so does a BREAKING CHANGE footer in the body.
  assert.strictEqual(
    determineBump([commit('feat: new storage layer', 'BREAKING CHANGE: on-disk format changed')]),
    'major'
  );
});

test('determineBump: the strongest bump wins across commits', () => {
  assert.strictEqual(
    determineBump([commit('fix: a'), commit('feat: b'), commit('chore: c')]),
    'minor'
  );
  assert.strictEqual(
    determineBump([commit('fix: a'), commit('feat!: b'), commit('feat: c')]),
    'major'
  );
});

test('determineBump: non-releasing commits produce no bump', () => {
  assert.strictEqual(determineBump([commit('chore: tidy up'), commit('docs: readme')]), null);
  assert.strictEqual(determineBump([]), null);
});

// ---------------------------------------------------------------------------
// Cycle 3: bumpVersion - apply the bump type, resetting lower components.
// ---------------------------------------------------------------------------
test('bumpVersion increments the right component and resets lower ones', () => {
  assert.strictEqual(bumpVersion('1.1.0', 'minor'), '1.2.0'); // feat
  assert.strictEqual(bumpVersion('2.3.4', 'patch'), '2.3.5'); // fix
  assert.strictEqual(bumpVersion('2.4.6', 'major'), '3.0.0'); // breaking
  assert.strictEqual(bumpVersion('1.9.9', 'minor'), '1.10.0');
});

test('bumpVersion rejects an unknown bump type', () => {
  assert.throws(() => bumpVersion('1.0.0', 'huge'), /Unknown bump type/);
});

// ---------------------------------------------------------------------------
// Cycle 4: parseCommitLog - parse the mock git-log fixture format.
// Each commit is "<hash> <subject>" followed by optional body lines, with
// commits delimited by a line of "====" (the same shape you get from
// `git log --pretty=format:'%h %s%n%b%n===='`).
// ---------------------------------------------------------------------------
test('parseCommitLog parses the feat fixture into commit objects', () => {
  const commits = parseCommitLog(fixture('commits-feat.log'));
  assert.strictEqual(commits.length, 3);
  assert.deepStrictEqual(commits[0], {
    hash: 'a1b2c3d',
    subject: 'feat: add OAuth login',
    body: 'Adds support for OAuth 2.0 login with Google and GitHub providers.',
  });
  assert.strictEqual(commits[1].subject, 'fix(session): expire idle sessions after 30 minutes');
  assert.strictEqual(commits[1].body, '');
});

test('parseCommitLog + determineBump agree on every fixture', () => {
  assert.strictEqual(determineBump(parseCommitLog(fixture('commits-feat.log'))), 'minor');
  assert.strictEqual(determineBump(parseCommitLog(fixture('commits-fix.log'))), 'patch');
  assert.strictEqual(determineBump(parseCommitLog(fixture('commits-breaking.log'))), 'major');
  assert.strictEqual(determineBump(parseCommitLog(fixture('commits-none.log'))), null);
});

test('parseCommitLog returns [] for empty input and rejects non-strings', () => {
  assert.deepStrictEqual(parseCommitLog(''), []);
  assert.deepStrictEqual(parseCommitLog('\n====\n'), []);
  assert.throws(() => parseCommitLog(undefined), /Commit log must be a string/);
});

// ---------------------------------------------------------------------------
// Cycle 5a: readVersionFile / writeVersionFile - support both package.json
// (the "version" field) and a plain-text VERSION file.
// ---------------------------------------------------------------------------
test('readVersionFile reads the version field from package.json', () => {
  const dir = tmpdir();
  const file = path.join(dir, 'package.json');
  fs.writeFileSync(file, JSON.stringify({ name: 'demo', version: '1.1.0' }, null, 2) + '\n');
  assert.strictEqual(readVersionFile(file), '1.1.0');
});

test('readVersionFile reads a plain VERSION file', () => {
  const dir = tmpdir();
  const file = path.join(dir, 'VERSION');
  fs.writeFileSync(file, '2.3.4\n');
  assert.strictEqual(readVersionFile(file), '2.3.4');
});

test('readVersionFile fails with meaningful errors', () => {
  const dir = tmpdir();
  assert.throws(() => readVersionFile(path.join(dir, 'nope')), /Version file not found/);

  const badJson = path.join(dir, 'package.json');
  fs.writeFileSync(badJson, '{ not json');
  assert.throws(() => readVersionFile(badJson), /not valid JSON/);

  fs.writeFileSync(badJson, '{"name": "no-version"}');
  assert.throws(() => readVersionFile(badJson), /has no "version" field/);
});

test('writeVersionFile updates package.json in place, preserving other fields', () => {
  const dir = tmpdir();
  const file = path.join(dir, 'package.json');
  fs.writeFileSync(file, JSON.stringify({ name: 'demo', version: '1.1.0', license: 'MIT' }, null, 2) + '\n');
  writeVersionFile(file, '1.2.0');
  const pkg = JSON.parse(fs.readFileSync(file, 'utf8'));
  assert.strictEqual(pkg.version, '1.2.0');
  assert.strictEqual(pkg.name, 'demo');
  assert.strictEqual(pkg.license, 'MIT');
});

test('writeVersionFile rewrites a plain VERSION file with a trailing newline', () => {
  const dir = tmpdir();
  const file = path.join(dir, 'VERSION');
  fs.writeFileSync(file, '2.3.4\n');
  writeVersionFile(file, '2.3.5');
  assert.strictEqual(fs.readFileSync(file, 'utf8'), '2.3.5\n');
});

// ---------------------------------------------------------------------------
// Cycle 5b: changelog generation - one markdown entry per release, commits
// grouped by kind, prepended to CHANGELOG.md.
// ---------------------------------------------------------------------------
test('generateChangelogEntry groups commits under the right headings', () => {
  const commits = parseCommitLog(fixture('commits-breaking.log'));
  const entry = generateChangelogEntry('3.0.0', commits, '2026-07-01');
  assert.match(entry, /^## 3\.0\.0 \(2026-07-01\)$/m);
  assert.match(entry, /### Breaking Changes/);
  assert.match(entry, /### Features/);
  assert.match(entry, /### Bug Fixes/);
  // Breaking commit is listed with its hash; the "!" subject lands under Breaking.
  assert.match(entry, /- switch storage engine to sqlite \(f0e1d2c\)/);
  assert.match(entry, /- add export command \(b3a4c5d\)/);
  assert.match(entry, /- handle empty config files \(d6c7b8a\)/);
});

test('generateChangelogEntry omits empty sections', () => {
  const entry = generateChangelogEntry('2.3.5', parseCommitLog(fixture('commits-fix.log')), '2026-07-01');
  assert.doesNotMatch(entry, /### Features/);
  assert.doesNotMatch(entry, /### Breaking Changes/);
  assert.match(entry, /- correct token refresh race condition \(1a2b3c4\)/);
});

test('prependChangelog creates the file, then inserts newest entries first', () => {
  const dir = tmpdir();
  const file = path.join(dir, 'CHANGELOG.md');
  prependChangelog(file, '## 1.2.0 (2026-07-01)\n\n- first\n');
  prependChangelog(file, '## 1.3.0 (2026-07-02)\n\n- second\n');
  const text = fs.readFileSync(file, 'utf8');
  assert.match(text, /^# Changelog/); // header written once
  assert.ok(text.indexOf('1.3.0') < text.indexOf('1.2.0'), 'newest entry comes first');
});

// ---------------------------------------------------------------------------
// Cycle 6: run() - the end-to-end pipeline: read version, classify commits,
// bump, rewrite the version file, prepend the changelog, report the result.
// ---------------------------------------------------------------------------

// Build a throwaway project directory with a version file and a commits log.
function makeProject({ versionFileName, versionContent, commitsFixture }) {
  const dir = tmpdir();
  fs.writeFileSync(path.join(dir, versionFileName), versionContent);
  fs.writeFileSync(path.join(dir, 'commits.log'), fixture(commitsFixture));
  return dir;
}

test('run: feat commits bump package.json 1.1.0 -> 1.2.0 and write a changelog', () => {
  const dir = makeProject({
    versionFileName: 'package.json',
    versionContent: JSON.stringify({ name: 'demo', version: '1.1.0' }, null, 2) + '\n',
    commitsFixture: 'commits-feat.log',
  });
  const result = run({ cwd: dir, commitsFile: 'commits.log' });
  assert.deepStrictEqual(
    { previous: result.previousVersion, next: result.newVersion, bump: result.bumpType, released: result.released },
    { previous: '1.1.0', next: '1.2.0', bump: 'minor', released: true }
  );
  assert.strictEqual(JSON.parse(fs.readFileSync(path.join(dir, 'package.json'), 'utf8')).version, '1.2.0');
  const changelog = fs.readFileSync(path.join(dir, 'CHANGELOG.md'), 'utf8');
  assert.match(changelog, /## 1\.2\.0 /);
  assert.match(changelog, /add OAuth login \(a1b2c3d\)/);
});

test('run: fix commits bump a VERSION file 2.3.4 -> 2.3.5', () => {
  const dir = makeProject({
    versionFileName: 'VERSION',
    versionContent: '2.3.4\n',
    commitsFixture: 'commits-fix.log',
  });
  const result = run({ cwd: dir, commitsFile: 'commits.log' });
  assert.strictEqual(result.newVersion, '2.3.5');
  assert.strictEqual(fs.readFileSync(path.join(dir, 'VERSION'), 'utf8'), '2.3.5\n');
});

test('run: breaking commits bump a VERSION file 2.4.6 -> 3.0.0', () => {
  const dir = makeProject({
    versionFileName: 'VERSION',
    versionContent: '2.4.6\n',
    commitsFixture: 'commits-breaking.log',
  });
  assert.strictEqual(run({ cwd: dir, commitsFile: 'commits.log' }).newVersion, '3.0.0');
});

test('run: prefers package.json over VERSION when both exist', () => {
  const dir = makeProject({
    versionFileName: 'package.json',
    versionContent: JSON.stringify({ name: 'demo', version: '0.1.0' }, null, 2) + '\n',
    commitsFixture: 'commits-feat.log',
  });
  fs.writeFileSync(path.join(dir, 'VERSION'), '9.9.9\n');
  assert.strictEqual(run({ cwd: dir, commitsFile: 'commits.log' }).newVersion, '0.2.0');
});

test('run: no releasable commits leaves everything untouched', () => {
  const dir = makeProject({
    versionFileName: 'VERSION',
    versionContent: '1.0.0\n',
    commitsFixture: 'commits-none.log',
  });
  const result = run({ cwd: dir, commitsFile: 'commits.log' });
  assert.deepStrictEqual(
    { next: result.newVersion, released: result.released, bump: result.bumpType },
    { next: '1.0.0', released: false, bump: null }
  );
  assert.strictEqual(fs.readFileSync(path.join(dir, 'VERSION'), 'utf8'), '1.0.0\n');
  assert.ok(!fs.existsSync(path.join(dir, 'CHANGELOG.md')), 'no changelog for no release');
});

test('run: meaningful errors for missing inputs', () => {
  const empty = tmpdir();
  assert.throws(() => run({ cwd: empty, commitsFile: 'commits.log' }), /No version file found/);

  const dir = makeProject({
    versionFileName: 'VERSION',
    versionContent: '1.0.0\n',
    commitsFixture: 'commits-feat.log',
  });
  assert.throws(() => run({ cwd: dir, commitsFile: 'missing.log' }), /Commits file not found/);
});

// ---------------------------------------------------------------------------
// Cycle 6b: the CLI wrapper - spawn the real script the way CI does and
// check stdout carries the new version.
// ---------------------------------------------------------------------------
test('CLI prints the new version on stdout and exits 0', () => {
  const { execFileSync } = require('node:child_process');
  const dir = makeProject({
    versionFileName: 'package.json',
    versionContent: JSON.stringify({ name: 'demo', version: '1.1.0' }, null, 2) + '\n',
    commitsFixture: 'commits-feat.log',
  });
  const script = path.join(__dirname, '..', 'src', 'semver-bump.js');
  const stdout = execFileSync('node', [script, '--commits-file', 'commits.log'], {
    cwd: dir,
    encoding: 'utf8',
  });
  assert.strictEqual(stdout.trim(), '1.2.0');
});

test('CLI exits non-zero with a helpful message on error', () => {
  const { spawnSync } = require('node:child_process');
  const script = path.join(__dirname, '..', 'src', 'semver-bump.js');
  const res = spawnSync('node', [script, '--commits-file', 'commits.log'], {
    cwd: tmpdir(),
    encoding: 'utf8',
  });
  assert.notStrictEqual(res.status, 0);
  assert.match(res.stderr, /No version file found/);
});
