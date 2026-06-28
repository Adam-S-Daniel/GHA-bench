// Core library for the semantic version bumper.
//
// The parsing/decision helpers are pure functions; the read/write helpers touch
// the filesystem but are kept tiny and focused so they're still easy to test
// against temp files. The thin CLI wrapper in ./cli.js wires everything to
// process arguments.

import fs from "node:fs";
import path from "node:path";

// Commits in a fixture / git-dump log are separated by this delimiter line.
// (Produce one with: `git log --format='%B%n--==COMMIT==--'`.)
export const COMMIT_DELIMITER = "--==COMMIT==--";

// Conventional-commit header: type(scope)!: description
//   group 1: type        (required, e.g. feat, fix, chore)
//   group 2: scope        (optional, inside parentheses)
//   group 3: "!"          (optional breaking-change marker)
//   group 4: description  (required)
const HEADER_RE = /^([a-zA-Z]+)(?:\(([^)]*)\))?(!)?:\s*(.+)$/;

/**
 * Parse a raw commit log into structured conventional-commit objects.
 *
 * Non-conventional entries (merge commits, blank blocks, free-form messages)
 * are silently skipped so the caller only ever sees commits that can influence
 * the version bump.
 *
 * @param {string} log raw log text, commits separated by COMMIT_DELIMITER
 * @returns {Array<{type:string, scope:string|null, breaking:boolean, description:string}>}
 */
export function parseCommits(log) {
  if (typeof log !== "string") {
    throw new TypeError("parseCommits expects the commit log as a string");
  }

  const blocks = log.split(COMMIT_DELIMITER);
  const commits = [];

  for (const block of blocks) {
    const trimmed = block.trim();
    if (!trimmed) continue;

    const lines = trimmed.split("\n");
    const header = lines[0].trim();
    const body = lines.slice(1).join("\n");

    const match = HEADER_RE.exec(header);
    if (!match) continue; // not a conventional commit -> ignore

    const [, type, scope, bang, description] = match;
    const breaking =
      bang === "!" || /^BREAKING[ -]CHANGE:/m.test(body);

    commits.push({
      type: type.toLowerCase(),
      scope: scope ? scope.trim() : null,
      breaking,
      description: description.trim(),
    });
  }

  return commits;
}

// Precedence of bumps: a single breaking change forces a major; otherwise any
// feat triggers a minor; otherwise any fix triggers a patch. Everything else
// (chore, docs, style, refactor, test, ci, ...) does not move the version.
const BUMP_RANK = { major: 3, minor: 2, patch: 1 };

/**
 * Decide the bump level implied by a set of parsed commits.
 *
 * @param {Array} commits output of parseCommits
 * @returns {"major"|"minor"|"patch"|null} null when nothing warrants a bump
 */
export function determineBump(commits) {
  let best = null;
  for (const commit of commits) {
    let level = null;
    if (commit.breaking) level = "major";
    else if (commit.type === "feat") level = "minor";
    else if (commit.type === "fix") level = "patch";

    if (level && (!best || BUMP_RANK[level] > BUMP_RANK[best])) {
      best = level;
    }
  }
  return best;
}

// Strict SemVer core (major.minor.patch). Pre-release / build metadata is out
// of scope for this bumper; we keep the surface small and reject anything else.
const VERSION_RE = /^v?(\d+)\.(\d+)\.(\d+)$/;

/**
 * Apply a bump level to a version string.
 *
 * @param {string} version e.g. "1.4.2" (an optional leading "v" is tolerated)
 * @param {"major"|"minor"|"patch"} bumpType
 * @returns {string} the new version, without any leading "v"
 */
export function bumpVersion(version, bumpType) {
  const match = VERSION_RE.exec(String(version).trim());
  if (!match) {
    throw new Error(
      `Invalid semantic version: "${version}". Expected MAJOR.MINOR.PATCH (e.g. 1.2.3).`
    );
  }

  let [major, minor, patch] = match.slice(1).map(Number);

  switch (bumpType) {
    case "major":
      major += 1;
      minor = 0;
      patch = 0;
      break;
    case "minor":
      minor += 1;
      patch = 0;
      break;
    case "patch":
      patch += 1;
      break;
    default:
      throw new Error(
        `Unknown bump type: "${bumpType}". Expected "major", "minor" or "patch".`
      );
  }

  return `${major}.${minor}.${patch}`;
}

// A file is treated as a package.json when its basename is "package.json";
// anything else (VERSION, .version, version.txt, ...) is a plain version file.
function isPackageJson(filePath) {
  return path.basename(filePath) === "package.json";
}

/**
 * Read the current version from either a package.json or a plain version file.
 *
 * @param {string} filePath
 * @returns {string} the version string (e.g. "1.2.3")
 */
export function readVersion(filePath) {
  let raw;
  try {
    raw = fs.readFileSync(filePath, "utf8");
  } catch {
    throw new Error(`Version file not found: ${filePath}`);
  }

  if (isPackageJson(filePath)) {
    let pkg;
    try {
      pkg = JSON.parse(raw);
    } catch (e) {
      throw new Error(`Could not parse ${filePath} as JSON: ${e.message}`);
    }
    if (typeof pkg.version !== "string") {
      throw new Error(`${filePath} has no "version" field`);
    }
    return pkg.version.trim();
  }

  const version = raw.trim();
  if (!version) {
    throw new Error(`Version file is empty: ${filePath}`);
  }
  return version;
}

/**
 * Persist a new version back to the same file, preserving its format.
 * For package.json the surrounding keys/indentation are kept intact.
 *
 * @param {string} filePath
 * @param {string} newVersion
 */
export function writeVersion(filePath, newVersion) {
  if (isPackageJson(filePath)) {
    const pkg = JSON.parse(fs.readFileSync(filePath, "utf8"));
    pkg.version = newVersion;
    // 2-space indent + trailing newline matches npm's own conventions.
    fs.writeFileSync(filePath, JSON.stringify(pkg, null, 2) + "\n");
  } else {
    fs.writeFileSync(filePath, newVersion + "\n");
  }
}

// Conventional-commit type -> changelog section heading. Order here is the
// order sections appear in the output.
const SECTIONS = [
  { heading: "Breaking Changes", match: (c) => c.breaking },
  { heading: "Features", match: (c) => !c.breaking && c.type === "feat" },
  { heading: "Bug Fixes", match: (c) => !c.breaking && c.type === "fix" },
];

/**
 * Build a Markdown changelog entry for a release.
 *
 * @param {string} version the new version being released
 * @param {Array} commits parsed commits (output of parseCommits)
 * @param {string} dateStr ISO date (YYYY-MM-DD) for the release header
 * @returns {string} a Markdown block ending in a single trailing newline
 */
export function generateChangelog(version, commits, dateStr) {
  const lines = [`## [${version}] - ${dateStr}`, ""];

  for (const section of SECTIONS) {
    const matched = commits.filter(section.match);
    if (matched.length === 0) continue; // omit empty sections

    lines.push(`### ${section.heading}`, "");
    for (const c of matched) {
      const prefix = c.scope ? `**${c.scope}:** ` : "";
      lines.push(`- ${prefix}${c.description}`);
    }
    lines.push("");
  }

  return lines.join("\n").trimEnd() + "\n";
}

// Prepend a new changelog entry above any existing content, keeping a stable
// top-of-file title. Creates the file if it does not exist yet.
function prependChangelog(changelogFile, entry) {
  const TITLE = "# Changelog\n";
  let existingBody = "";
  if (fs.existsSync(changelogFile)) {
    let current = fs.readFileSync(changelogFile, "utf8");
    // Drop a leading "# Changelog" title if present; we re-add it ourselves.
    current = current.replace(/^# Changelog\s*\n+/, "");
    existingBody = current;
  }
  const out = `${TITLE}\n${entry}${existingBody ? "\n" + existingBody : ""}`;
  fs.writeFileSync(changelogFile, out);
}

/**
 * End-to-end bump: read current version, decide the next one from the commit
 * log, update the version file, and prepend a changelog entry.
 *
 * @param {object} opts
 * @param {string} opts.versionFile  path to VERSION / package.json
 * @param {string} opts.commitsFile  path to the commit log fixture/dump
 * @param {string} opts.changelogFile path to CHANGELOG.md
 * @param {string} opts.date         ISO date for the changelog header
 * @returns {{oldVersion:string,newVersion:string,bumpType:string,changelogEntry:string}}
 */
export function bump({ versionFile, commitsFile, changelogFile, date }) {
  const oldVersion = readVersion(versionFile);

  let log;
  try {
    log = fs.readFileSync(commitsFile, "utf8");
  } catch {
    throw new Error(`Commit log not found: ${commitsFile}`);
  }

  const commits = parseCommits(log);
  const bumpType = determineBump(commits);
  if (!bumpType) {
    throw new Error(
      "No conventional commits found that warrant a version bump " +
        "(need at least one feat, fix, or breaking change)."
    );
  }

  const newVersion = bumpVersion(oldVersion, bumpType);
  const changelogEntry = generateChangelog(newVersion, commits, date);

  writeVersion(versionFile, newVersion);
  prependChangelog(changelogFile, changelogEntry);

  return { oldVersion, newVersion, bumpType, changelogEntry };
}
