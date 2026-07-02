#!/usr/bin/env node
'use strict';
// Semantic version bumper driven by conventional commits.
//
// Approach:
//   1. Read the current version from a plain VERSION file or a package.json
//      (detected by file name).
//   2. Read commit messages from a commit-log file (one commit per line;
//      "\n\n" inside a message is encoded as literal "\n" — see splitCommits).
//      Using a file instead of `git log` directly keeps the core logic pure
//      and lets tests inject mock commit logs as fixtures.
//   3. Classify commits: breaking change -> major, feat -> minor,
//      fix -> patch; the highest level wins. Anything else is ignored.
//   4. Write the bumped version back, prepend a grouped changelog entry,
//      and print the new version.
//
// Zero dependencies so it runs anywhere node exists (including act containers).

const fs = require('node:fs');
const path = require('node:path');

// --- Cycle 1: version parsing ----------------------------------------------

function parseVersion(raw) {
  const cleaned = String(raw == null ? '' : raw).trim().replace(/^v/, '');
  const m = /^(\d+)\.(\d+)\.(\d+)$/.exec(cleaned);
  if (!m) {
    throw new Error(
      `Invalid semantic version: "${String(raw == null ? '' : raw).trim()}" (expected MAJOR.MINOR.PATCH, e.g. "1.2.3")`
    );
  }
  return { major: Number(m[1]), minor: Number(m[2]), patch: Number(m[3]) };
}

// --- Cycle 2: commit classification ----------------------------------------

// Conventional commit header: type(scope)?!?: subject
const HEADER_RE = /^(\w+)(\(([^)]*)\))?(!)?:\s*(.+)$/;

function classifyCommit(message) {
  const header = message.split('\n', 1)[0];
  const m = HEADER_RE.exec(header);
  const breakingFooter = /(^|\n)BREAKING[ -]CHANGE:/.test(message);
  if (!m) return { level: breakingFooter ? 'major' : null, type: null, scope: null, subject: header };
  const [, type, , scope, bang, subject] = m;
  let level = null;
  if (bang || breakingFooter) level = 'major';
  else if (type === 'feat') level = 'minor';
  else if (type === 'fix') level = 'patch';
  return { level, type, scope: scope || null, subject: subject.trim() };
}

const LEVEL_RANK = { major: 3, minor: 2, patch: 1 };

// Returns 'major' | 'minor' | 'patch' | null (null = nothing releasable).
function determineBump(commitMessages) {
  let best = null;
  for (const msg of commitMessages) {
    const { level } = classifyCommit(msg);
    if (level && (!best || LEVEL_RANK[level] > LEVEL_RANK[best])) best = level;
    if (best === 'major') break; // can't rank higher
  }
  return best;
}

// --- Cycle 3: applying the bump ---------------------------------------------

function bumpVersion(version, bumpType) {
  const v = parseVersion(version);
  switch (bumpType) {
    case 'major':
      return `${v.major + 1}.0.0`;
    case 'minor':
      return `${v.major}.${v.minor + 1}.0`;
    case 'patch':
      return `${v.major}.${v.minor}.${v.patch + 1}`;
    default:
      throw new Error(`Unknown bump type: "${bumpType}" (expected major, minor or patch)`);
  }
}

// --- Cycle 4: version file I/O ----------------------------------------------

function isPackageJson(file) {
  return path.basename(file) === 'package.json';
}

function readVersionFile(file) {
  if (!fs.existsSync(file)) {
    throw new Error(`Version file not found: ${file}`);
  }
  const text = fs.readFileSync(file, 'utf8');
  if (isPackageJson(file)) {
    let pkg;
    try {
      pkg = JSON.parse(text);
    } catch (e) {
      throw new Error(`${file} is not valid JSON: ${e.message}`);
    }
    if (!pkg.version) throw new Error(`${file} has no "version" field`);
    return String(pkg.version).trim();
  }
  return text.trim();
}

function writeVersionFile(file, version) {
  if (isPackageJson(file)) {
    // Surgical string replace of the version value keeps the file's original
    // formatting (indentation, key order) intact.
    const text = fs.readFileSync(file, 'utf8');
    const updated = text.replace(/("version"\s*:\s*")[^"]*(")/, `$1${version}$2`);
    fs.writeFileSync(file, updated);
  } else {
    fs.writeFileSync(file, version + '\n');
  }
}

// --- Cycle 5: changelog -------------------------------------------------------

const SECTION_ORDER = [
  ['major', 'Breaking Changes'],
  ['minor', 'Features'],
  ['patch', 'Fixes'],
];

function generateChangelogEntry(newVersion, commitMessages, date) {
  const groups = { major: [], minor: [], patch: [] };
  for (const msg of commitMessages) {
    const c = classifyCommit(msg);
    if (!c.level) continue;
    const scopePrefix = c.scope ? `**${c.scope}:** ` : '';
    groups[c.level].push(`- ${scopePrefix}${c.subject}`);
  }
  let entry = `## ${newVersion} (${date})\n`;
  for (const [level, title] of SECTION_ORDER) {
    if (groups[level].length === 0) continue;
    entry += `\n### ${title}\n\n${groups[level].join('\n')}\n`;
  }
  return entry;
}

function prependChangelog(file, entry) {
  const header = '# Changelog\n';
  let existing = '';
  if (fs.existsSync(file)) {
    existing = fs.readFileSync(file, 'utf8').replace(/^# Changelog\n+/, '');
  }
  fs.writeFileSync(file, `${header}\n${entry}${existing ? '\n' + existing : ''}`);
}

// --- Cycle 6: orchestration / CLI --------------------------------------------

function splitCommits(text) {
  // Fixture format: one commit per line; multi-line commit bodies are encoded
  // with literal "\n" so a single line can carry a BREAKING CHANGE footer.
  return text
    .split('\n')
    .map((l) => l.trim())
    .filter(Boolean)
    .map((l) => l.replace(/\\n/g, '\n'));
}

function run({ versionFile, commitsFile, changelogFile, date }) {
  const current = readVersionFile(versionFile);
  parseVersion(current); // validate early, with a clear message

  if (!fs.existsSync(commitsFile)) {
    throw new Error(`Commit log file not found: ${commitsFile}`);
  }
  const commits = splitCommits(fs.readFileSync(commitsFile, 'utf8'));
  const bumpType = determineBump(commits);

  if (!bumpType) {
    // Nothing releasable: report the current version and touch nothing.
    return { previousVersion: current, newVersion: current, bumpType: null };
  }

  const newVersion = bumpVersion(current, bumpType);
  writeVersionFile(versionFile, newVersion);
  const entryDate = date || new Date().toISOString().slice(0, 10);
  prependChangelog(changelogFile, generateChangelogEntry(newVersion, commits, entryDate));
  return { previousVersion: current, newVersion, bumpType };
}

// --- CLI entry point ----------------------------------------------------------

function parseArgs(argv) {
  const opts = {
    versionFile: 'VERSION',
    commitsFile: 'commits.txt',
    changelogFile: 'CHANGELOG.md',
    date: undefined,
  };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    const next = () => {
      if (i + 1 >= argv.length) throw new Error(`Missing value for ${arg}`);
      return argv[++i];
    };
    if (arg === '--version-file') opts.versionFile = next();
    else if (arg === '--commits-file') opts.commitsFile = next();
    else if (arg === '--changelog-file') opts.changelogFile = next();
    else if (arg === '--date') opts.date = next();
    else throw new Error(`Unknown argument: ${arg}`);
  }
  return opts;
}

if (require.main === module) {
  try {
    const opts = parseArgs(process.argv.slice(2));
    const result = run(opts);
    if (result.bumpType) {
      console.log(`Bumped ${result.previousVersion} -> ${result.newVersion} (${result.bumpType})`);
    } else {
      console.log(`No releasable commits; version stays at ${result.newVersion}`);
    }
    // Machine-readable line the CI harness asserts on.
    console.log(`NEW_VERSION=${result.newVersion}`);
  } catch (e) {
    console.error(`ERROR: ${e.message}`);
    process.exit(1);
  }
}

module.exports = {
  parseVersion,
  classifyCommit,
  determineBump,
  bumpVersion,
  readVersionFile,
  writeVersionFile,
  generateChangelogEntry,
  prependChangelog,
  splitCommits,
  run,
};
