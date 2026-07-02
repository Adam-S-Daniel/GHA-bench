'use strict';
// Semantic version bumper.
//
// Reads the current version from a version file (package.json or a plain
// VERSION file), inspects conventional commit messages to decide the bump
// type (breaking -> major, feat -> minor, fix -> patch), rewrites the
// version file, prepends a changelog entry, and prints the new version.
//
// Developed test-first; see test/semver-bump.test.js for the TDD cycles.

/**
 * Parse a semantic version string ("1.2.3", optionally "v"-prefixed) into
 * its numeric components. Throws with a meaningful message on bad input.
 */
function parseVersion(raw) {
  if (typeof raw !== 'string') {
    throw new Error(`Invalid semantic version: expected a string, got ${raw === null ? 'null' : typeof raw}`);
  }
  const match = raw.trim().match(/^v?(\d+)\.(\d+)\.(\d+)$/);
  if (!match) {
    throw new Error(`Invalid semantic version: "${raw.trim()}" (expected MAJOR.MINOR.PATCH, e.g. "1.2.3")`);
  }
  return { major: Number(match[1]), minor: Number(match[2]), patch: Number(match[3]) };
}

// Conventional-commit subject: "type(optional scope)!: description".
const CONVENTIONAL_SUBJECT = /^(?<type>[a-zA-Z]+)(?:\([^)]*\))?(?<bang>!)?:\s/;

/**
 * Decide the bump type for a single commit ({ subject, body }):
 * 'major' for breaking changes ("!" marker or BREAKING CHANGE footer),
 * 'minor' for feat, 'patch' for fix, null otherwise.
 */
function classifyCommit({ subject = '', body = '' }) {
  if (/BREAKING[ -]CHANGE:/.test(body)) return 'major';
  const match = subject.match(CONVENTIONAL_SUBJECT);
  if (!match) return null;
  if (match.groups.bang) return 'major';
  const type = match.groups.type.toLowerCase();
  if (type === 'feat') return 'minor';
  if (type === 'fix') return 'patch';
  return null;
}

/**
 * Fold classifyCommit over all commits; the strongest bump wins.
 * Returns null when nothing warrants a release.
 */
function determineBump(commits) {
  const rank = { major: 3, minor: 2, patch: 1 };
  let best = null;
  for (const c of commits) {
    const bump = classifyCommit(c);
    if (bump && (!best || rank[bump] > rank[best])) best = bump;
  }
  return best;
}

/** Apply a bump type to a version string, resetting lower components. */
function bumpVersion(version, bumpType) {
  const { major, minor, patch } = parseVersion(version);
  switch (bumpType) {
    case 'major': return `${major + 1}.0.0`;
    case 'minor': return `${major}.${minor + 1}.0`;
    case 'patch': return `${major}.${minor}.${patch + 1}`;
    default:
      throw new Error(`Unknown bump type: "${bumpType}" (expected major, minor or patch)`);
  }
}

/**
 * Parse a commit log in our mock/git format: each commit is
 * "<hash> <subject>" followed by optional body lines, delimited by "====".
 * (Produced from a real repo with `git log --pretty=format:'%h %s%n%b%n===='`.)
 */
function parseCommitLog(text) {
  if (typeof text !== 'string') {
    throw new Error('Commit log must be a string (did the commits file fail to load?)');
  }
  const commits = [];
  for (const block of text.split(/^====\s*$/m)) {
    const lines = block.split('\n').map((l) => l.trimEnd());
    while (lines.length && lines[0] === '') lines.shift();
    while (lines.length && lines[lines.length - 1] === '') lines.pop();
    if (!lines.length) continue;
    const headline = lines[0].match(/^(\S+)\s+(.*)$/);
    // A block without "<hash> <subject>" shape is malformed input.
    if (!headline) {
      throw new Error(`Malformed commit entry (expected "<hash> <subject>"): "${lines[0]}"`);
    }
    commits.push({ hash: headline[1], subject: headline[2], body: lines.slice(1).join('\n') });
  }
  return commits;
}

const fs = require('node:fs');
const path = require('node:path');

const isPackageJson = (file) => path.basename(file) === 'package.json';

/**
 * Read the current version from a version file. package.json uses its
 * "version" field; any other file is treated as a plain version string.
 */
function readVersionFile(file) {
  if (!fs.existsSync(file)) {
    throw new Error(`Version file not found: ${file}`);
  }
  const raw = fs.readFileSync(file, 'utf8');
  if (!isPackageJson(file)) return raw.trim();

  let pkg;
  try {
    pkg = JSON.parse(raw);
  } catch (err) {
    throw new Error(`${file} is not valid JSON: ${err.message}`);
  }
  if (typeof pkg.version !== 'string') {
    throw new Error(`${file} has no "version" field to bump`);
  }
  return pkg.version;
}

/**
 * Write the new version back. For package.json we only swap the version
 * field (preserving all other fields and 2-space formatting); plain files
 * are rewritten with the bare version plus a trailing newline.
 */
function writeVersionFile(file, newVersion) {
  if (isPackageJson(file)) {
    const pkg = JSON.parse(fs.readFileSync(file, 'utf8'));
    pkg.version = newVersion;
    fs.writeFileSync(file, JSON.stringify(pkg, null, 2) + '\n');
  } else {
    fs.writeFileSync(file, newVersion + '\n');
  }
}

/** Strip the conventional prefix for changelog display: "feat(x)!: y" -> "y". */
const describeCommit = (c) => `${c.subject.replace(CONVENTIONAL_SUBJECT, '')} (${c.hash})`;

/**
 * Render one markdown changelog entry for a release: commits grouped under
 * Breaking Changes / Features / Bug Fixes, empty sections omitted.
 */
function generateChangelogEntry(newVersion, commits, date) {
  const sections = [
    { title: 'Breaking Changes', match: (bump) => bump === 'major' },
    { title: 'Features', match: (bump) => bump === 'minor' },
    { title: 'Bug Fixes', match: (bump) => bump === 'patch' },
  ];
  let entry = `## ${newVersion} (${date})\n`;
  for (const { title, match } of sections) {
    const lines = commits.filter((c) => match(classifyCommit(c))).map((c) => `- ${describeCommit(c)}`);
    if (lines.length) entry += `\n### ${title}\n\n${lines.join('\n')}\n`;
  }
  return entry;
}

/** Insert a new entry at the top of CHANGELOG.md, creating it if needed. */
function prependChangelog(file, entry) {
  const HEADER = '# Changelog\n';
  const existing = fs.existsSync(file)
    ? fs.readFileSync(file, 'utf8').replace(/^# Changelog\n+/, '')
    : '';
  fs.writeFileSync(file, `${HEADER}\n${entry.trimEnd()}\n${existing ? '\n' + existing : ''}`);
}

/**
 * Locate the version file: an explicit path wins, then package.json, then
 * VERSION. Returning an absolute path keeps the rest of run() cwd-agnostic.
 */
function findVersionFile(cwd, explicit) {
  if (explicit) {
    const file = path.resolve(cwd, explicit);
    if (!fs.existsSync(file)) throw new Error(`Version file not found: ${file}`);
    return file;
  }
  for (const candidate of ['package.json', 'VERSION']) {
    const file = path.join(cwd, candidate);
    if (fs.existsSync(file)) return file;
  }
  throw new Error(`No version file found in ${cwd} (looked for package.json and VERSION)`);
}

/**
 * Read commits since the last release. Tests and CI fixtures pass a commits
 * file; without one we fall back to real `git log` output in the same format.
 */
function loadCommits(cwd, commitsFile) {
  if (commitsFile) {
    const file = path.resolve(cwd, commitsFile);
    if (!fs.existsSync(file)) throw new Error(`Commits file not found: ${file}`);
    return parseCommitLog(fs.readFileSync(file, 'utf8'));
  }
  const { execFileSync } = require('node:child_process');
  let range = 'HEAD';
  try {
    const lastTag = execFileSync('git', ['describe', '--tags', '--abbrev=0'], {
      cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'],
    }).trim();
    range = `${lastTag}..HEAD`;
  } catch {
    // No tags yet: consider the whole history.
  }
  const log = execFileSync('git', ['log', '--pretty=format:%h %s%n%b%n====', range], {
    cwd, encoding: 'utf8',
  });
  return parseCommitLog(log);
}

/**
 * The whole pipeline. Returns { previousVersion, newVersion, bumpType,
 * released, versionFile }. When no commit warrants a release, nothing is
 * written and newVersion === previousVersion.
 */
function run({ cwd = process.cwd(), versionFile, commitsFile, changelogFile = 'CHANGELOG.md', now = new Date() } = {}) {
  const file = findVersionFile(cwd, versionFile);
  const previousVersion = readVersionFile(file);
  parseVersion(previousVersion); // validate early, with a clear error

  const commits = loadCommits(cwd, commitsFile);
  const bumpType = determineBump(commits);
  if (!bumpType) {
    return { previousVersion, newVersion: previousVersion, bumpType: null, released: false, versionFile: file };
  }

  const newVersion = bumpVersion(previousVersion, bumpType);
  writeVersionFile(file, newVersion);
  const date = now.toISOString().slice(0, 10);
  prependChangelog(path.resolve(cwd, changelogFile), generateChangelogEntry(newVersion, commits, date));
  return { previousVersion, newVersion, bumpType, released: true, versionFile: file };
}

/** Tiny flag parser for the CLI - avoids any dependency. */
function parseArgs(argv) {
  const options = {};
  const flags = { '--version-file': 'versionFile', '--commits-file': 'commitsFile', '--changelog': 'changelogFile' };
  for (let i = 0; i < argv.length; i += 2) {
    const key = flags[argv[i]];
    if (!key) throw new Error(`Unknown argument: ${argv[i]} (expected ${Object.keys(flags).join(', ')})`);
    if (argv[i + 1] === undefined) throw new Error(`Missing value for ${argv[i]}`);
    options[key] = argv[i + 1];
  }
  return options;
}

function main() {
  try {
    const result = run(parseArgs(process.argv.slice(2)));
    if (result.released) {
      process.stderr.write(`Bumped ${result.previousVersion} -> ${result.newVersion} (${result.bumpType}) in ${result.versionFile}\n`);
    } else {
      process.stderr.write(`No release needed: no feat/fix/breaking commits found. Version stays at ${result.previousVersion}.\n`);
    }
    // stdout carries exactly the (possibly unchanged) version, for scripting.
    process.stdout.write(result.newVersion + '\n');
  } catch (err) {
    process.stderr.write(`semver-bump error: ${err.message}\n`);
    process.exit(1);
  }
}

if (require.main === module) main();

module.exports = {
  parseVersion,
  classifyCommit,
  determineBump,
  bumpVersion,
  parseCommitLog,
  readVersionFile,
  writeVersionFile,
  generateChangelogEntry,
  prependChangelog,
  run,
};
