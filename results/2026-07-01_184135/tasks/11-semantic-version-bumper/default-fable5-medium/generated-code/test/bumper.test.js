'use strict';
// Unit tests for the semantic version bumper.
//
// TDD log (red/green cycles are recorded as comments next to each block):
//   Cycle 1: parseVersion       — red: module missing        -> green: implement parseVersion
//   Cycle 2: determineBump      — red: not a function        -> green: implement determineBump
//   Cycle 3: bumpVersion        — red: not a function        -> green: implement bumpVersion
//   Cycle 4: version file I/O   — red: not a function        -> green: implement read/writeVersionFile
//   Cycle 5: changelog          — red: not a function        -> green: implement generateChangelogEntry
//   Cycle 6: CLI end-to-end     — red: run() missing         -> green: implement run()
//
// Tests use only node's built-in test runner — no external deps, so the
// suite runs identically on the host and inside the act container.

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const bumper = require('../src/bumper.js');

// ---------------------------------------------------------------------------
// Cycle 1: parseVersion — turn "1.2.3" into {major, minor, patch}
// ---------------------------------------------------------------------------
test('parseVersion parses a valid semver string', () => {
  assert.deepEqual(bumper.parseVersion('1.2.3'), { major: 1, minor: 2, patch: 3 });
});

test('parseVersion tolerates surrounding whitespace and a leading "v"', () => {
  assert.deepEqual(bumper.parseVersion(' v10.0.7\n'), { major: 10, minor: 0, patch: 7 });
});

test('parseVersion rejects malformed input with a helpful message', () => {
  assert.throws(() => bumper.parseVersion('1.2'), /Invalid semantic version: "1\.2"/);
  assert.throws(() => bumper.parseVersion('a.b.c'), /Invalid semantic version/);
  assert.throws(() => bumper.parseVersion(''), /Invalid semantic version/);
});

// ---------------------------------------------------------------------------
// Cycle 2: determineBump — classify conventional commits into a bump level
// ---------------------------------------------------------------------------
test('determineBump: feat commits produce a minor bump', () => {
  assert.equal(bumper.determineBump(['feat: add login page', 'chore: tidy']), 'minor');
});

test('determineBump: fix commits produce a patch bump', () => {
  assert.equal(bumper.determineBump(['fix: null pointer in parser']), 'patch');
});

test('determineBump: breaking changes win over everything', () => {
  // "!" marker form
  assert.equal(bumper.determineBump(['feat!: drop node 14', 'fix: typo']), 'major');
  // "BREAKING CHANGE:" footer form
  assert.equal(
    bumper.determineBump(['fix: rework api\n\nBREAKING CHANGE: endpoints renamed']),
    'major'
  );
});

test('determineBump: feat outranks fix', () => {
  assert.equal(bumper.determineBump(['fix: small bug', 'feat: new thing']), 'minor');
});

test('determineBump: no releasable commits returns null', () => {
  assert.equal(bumper.determineBump(['chore: bump deps', 'docs: readme']), null);
  assert.equal(bumper.determineBump([]), null);
});

test('determineBump: scoped commits are recognised', () => {
  assert.equal(bumper.determineBump(['feat(auth): oauth support']), 'minor');
  assert.equal(bumper.determineBump(['fix(core)!: change return type']), 'major');
});

// ---------------------------------------------------------------------------
// Cycle 3: bumpVersion — apply a bump level to a version string
// ---------------------------------------------------------------------------
test('bumpVersion applies major/minor/patch correctly', () => {
  assert.equal(bumper.bumpVersion('1.1.0', 'minor'), '1.2.0');
  assert.equal(bumper.bumpVersion('1.1.0', 'patch'), '1.1.1');
  assert.equal(bumper.bumpVersion('1.1.9', 'major'), '2.0.0');
});

test('bumpVersion resets lower components', () => {
  assert.equal(bumper.bumpVersion('2.3.4', 'major'), '3.0.0');
  assert.equal(bumper.bumpVersion('2.3.4', 'minor'), '2.4.0');
});

test('bumpVersion rejects an unknown bump type', () => {
  assert.throws(() => bumper.bumpVersion('1.0.0', 'huge'), /Unknown bump type: "huge"/);
});

// ---------------------------------------------------------------------------
// Cycle 4: version file I/O — plain VERSION file and package.json
// ---------------------------------------------------------------------------
function tmpdir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'bumper-test-'));
}

test('readVersionFile reads a plain VERSION file', () => {
  const dir = tmpdir();
  const file = path.join(dir, 'VERSION');
  fs.writeFileSync(file, '1.4.2\n');
  assert.equal(bumper.readVersionFile(file), '1.4.2');
});

test('readVersionFile reads the version field of package.json', () => {
  const dir = tmpdir();
  const file = path.join(dir, 'package.json');
  fs.writeFileSync(file, JSON.stringify({ name: 'x', version: '0.3.1' }, null, 2));
  assert.equal(bumper.readVersionFile(file), '0.3.1');
});

test('readVersionFile errors clearly on a missing file', () => {
  assert.throws(
    () => bumper.readVersionFile('/nonexistent/VERSION'),
    /Version file not found: \/nonexistent\/VERSION/
  );
});

test('readVersionFile errors clearly on package.json without a version', () => {
  const dir = tmpdir();
  const file = path.join(dir, 'package.json');
  fs.writeFileSync(file, '{"name":"x"}');
  assert.throws(() => bumper.readVersionFile(file), /has no "version" field/);
});

test('readVersionFile errors clearly on invalid JSON in package.json', () => {
  const dir = tmpdir();
  const file = path.join(dir, 'package.json');
  fs.writeFileSync(file, '{not json');
  assert.throws(() => bumper.readVersionFile(file), /not valid JSON/);
});

test('writeVersionFile updates a plain VERSION file', () => {
  const dir = tmpdir();
  const file = path.join(dir, 'VERSION');
  fs.writeFileSync(file, '1.0.0\n');
  bumper.writeVersionFile(file, '1.1.0');
  assert.equal(fs.readFileSync(file, 'utf8'), '1.1.0\n');
});

test('writeVersionFile updates package.json preserving other fields', () => {
  const dir = tmpdir();
  const file = path.join(dir, 'package.json');
  fs.writeFileSync(file, JSON.stringify({ name: 'x', version: '1.0.0', license: 'MIT' }, null, 2) + '\n');
  bumper.writeVersionFile(file, '2.0.0');
  const pkg = JSON.parse(fs.readFileSync(file, 'utf8'));
  assert.equal(pkg.version, '2.0.0');
  assert.equal(pkg.name, 'x');
  assert.equal(pkg.license, 'MIT');
});

// ---------------------------------------------------------------------------
// Cycle 5: changelog entry generation
// ---------------------------------------------------------------------------
test('generateChangelogEntry groups commits by type', () => {
  const commits = [
    'feat(auth): oauth support',
    'fix: crash on empty input',
    'feat!: drop node 14',
    'chore: bump deps',
  ];
  const entry = bumper.generateChangelogEntry('2.0.0', commits, '2026-07-01');
  assert.match(entry, /^## 2\.0\.0 \(2026-07-01\)/);
  assert.match(entry, /### Breaking Changes\n+- drop node 14/);
  assert.match(entry, /### Features\n+- \*\*auth:\*\* oauth support/);
  assert.match(entry, /### Fixes\n+- crash on empty input/);
  // Non-releasable commits stay out of the changelog.
  assert.doesNotMatch(entry, /bump deps/);
});

test('prependChangelog creates the file and keeps newest entry first', () => {
  const dir = tmpdir();
  const file = path.join(dir, 'CHANGELOG.md');
  bumper.prependChangelog(file, '## 1.1.0 (2026-07-01)\n\n### Features\n\n- a\n');
  bumper.prependChangelog(file, '## 1.2.0 (2026-07-02)\n\n### Features\n\n- b\n');
  const text = fs.readFileSync(file, 'utf8');
  assert.match(text, /^# Changelog/);
  assert.ok(text.indexOf('1.2.0') < text.indexOf('1.1.0'), 'newest entry must come first');
});

// ---------------------------------------------------------------------------
// Cycle 6: CLI end-to-end via run() — reads fixture commits, updates files
// ---------------------------------------------------------------------------
test('run() bumps VERSION file from a commit-log fixture and writes changelog', () => {
  const dir = tmpdir();
  const versionFile = path.join(dir, 'VERSION');
  const commitsFile = path.join(dir, 'commits.txt');
  const changelog = path.join(dir, 'CHANGELOG.md');
  fs.writeFileSync(versionFile, '1.1.0\n');
  // Mock commit log: one commit message per line (subject only).
  fs.writeFileSync(commitsFile, 'feat: add search\nchore: ci tweaks\n');

  const result = bumper.run({
    versionFile,
    commitsFile,
    changelogFile: changelog,
    date: '2026-07-01',
  });

  assert.equal(result.newVersion, '1.2.0');
  assert.equal(result.bumpType, 'minor');
  assert.equal(fs.readFileSync(versionFile, 'utf8'), '1.2.0\n');
  assert.match(fs.readFileSync(changelog, 'utf8'), /## 1\.2\.0 \(2026-07-01\)/);
});

test('run() with no releasable commits leaves files untouched', () => {
  const dir = tmpdir();
  const versionFile = path.join(dir, 'VERSION');
  const commitsFile = path.join(dir, 'commits.txt');
  fs.writeFileSync(versionFile, '1.1.0\n');
  fs.writeFileSync(commitsFile, 'chore: nothing interesting\n');

  const result = bumper.run({
    versionFile,
    commitsFile,
    changelogFile: path.join(dir, 'CHANGELOG.md'),
    date: '2026-07-01',
  });

  assert.equal(result.newVersion, '1.1.0');
  assert.equal(result.bumpType, null);
  assert.equal(fs.readFileSync(versionFile, 'utf8'), '1.1.0\n');
  assert.ok(!fs.existsSync(path.join(dir, 'CHANGELOG.md')));
});

test('run() errors meaningfully when the commits fixture is missing', () => {
  const dir = tmpdir();
  fs.writeFileSync(path.join(dir, 'VERSION'), '1.0.0\n');
  assert.throws(
    () =>
      bumper.run({
        versionFile: path.join(dir, 'VERSION'),
        commitsFile: path.join(dir, 'missing.txt'),
        changelogFile: path.join(dir, 'CHANGELOG.md'),
      }),
    /Commit log file not found/
  );
});
