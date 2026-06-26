// Orchestration layer: read version + commits from disk, compute the bump,
// write the version file back, and prepend a changelog entry.
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { basename } from "node:path";
import { parseVersion, formatVersion, bumpVersion, type BumpType } from "./semver";
import { parseCommits, determineBump } from "./commits";
import { generateChangelog } from "./changelog";

/** How the version was stored, so we can write it back in the same shape. */
export type VersionFileKind = "json" | "plain";

export interface VersionRead {
  version: string;
  kind: VersionFileKind;
}

export interface BumpOptions {
  /** Path to package.json or a plain VERSION file. */
  versionFile: string;
  /** Path to a newline-delimited commit log fixture. */
  commitsFile: string;
  /** Path to the changelog file to create/prepend. */
  changelogFile: string;
  /** ISO date string used in the changelog header (injected for testability). */
  date: string;
}

export interface BumpResult {
  previousVersion: string;
  newVersion: string;
  bump: BumpType | null;
  changelogEntry: string | null;
}

/**
 * Read the current version from either a package.json (its `version` field)
 * or a plain text file containing just the version string.
 */
export function readVersion(path: string): VersionRead {
  if (!existsSync(path)) {
    throw new Error(`Version file not found: ${path}`);
  }
  const raw = readFileSync(path, "utf8");
  if (basename(path) === "package.json" || path.endsWith(".json")) {
    let pkg: { version?: unknown };
    try {
      pkg = JSON.parse(raw);
    } catch {
      throw new Error(`Could not parse JSON version file: ${path}`);
    }
    if (typeof pkg.version !== "string") {
      throw new Error(`No "version" string found in ${path}`);
    }
    return { version: pkg.version, kind: "json" };
  }
  return { version: raw.trim(), kind: "plain" };
}

/** Persist a new version string back to disk, preserving the file shape. */
function writeVersion(path: string, newVersion: string, kind: VersionFileKind): void {
  if (kind === "json") {
    const pkg = JSON.parse(readFileSync(path, "utf8"));
    pkg.version = newVersion;
    // Preserve 2-space indentation and trailing newline (npm convention).
    writeFileSync(path, JSON.stringify(pkg, null, 2) + "\n");
  } else {
    writeFileSync(path, newVersion + "\n");
  }
}

/** Prepend a changelog entry, keeping any existing content below it. */
function prependChangelog(path: string, entry: string): void {
  const header = "# Changelog\n\n";
  if (existsSync(path)) {
    const existing = readFileSync(path, "utf8");
    // Keep an existing top-level title if present; otherwise add ours.
    if (existing.startsWith("# ")) {
      const firstBreak = existing.indexOf("\n\n");
      const title = firstBreak === -1 ? existing : existing.slice(0, firstBreak + 2);
      const rest = firstBreak === -1 ? "" : existing.slice(firstBreak + 2);
      writeFileSync(path, title + entry + "\n" + rest);
    } else {
      writeFileSync(path, header + entry + "\n" + existing);
    }
  } else {
    writeFileSync(path, header + entry);
  }
}

/**
 * Run the full bump pipeline. Returns a {@link BumpResult}; when no commits
 * warrant a release, nothing is written and `bump` is null.
 */
export function runBump(options: BumpOptions): BumpResult {
  const { versionFile, commitsFile, changelogFile, date } = options;

  const { version: currentStr, kind } = readVersion(versionFile);
  const current = parseVersion(currentStr);

  if (!existsSync(commitsFile)) {
    throw new Error(`Commits file not found: ${commitsFile}`);
  }
  const commits = parseCommits(readFileSync(commitsFile, "utf8"));
  const bump = determineBump(commits);

  if (bump === null) {
    return {
      previousVersion: currentStr,
      newVersion: formatVersion(current),
      bump: null,
      changelogEntry: null,
    };
  }

  const next = bumpVersion(current, bump);
  const newVersion = formatVersion(next);
  const entry = generateChangelog(newVersion, commits, date);

  writeVersion(versionFile, newVersion, kind);
  prependChangelog(changelogFile, entry);

  return {
    previousVersion: currentStr,
    newVersion,
    bump,
    changelogEntry: entry,
  };
}
