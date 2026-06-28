// src/bumper.ts
// Orchestrates the full "bump" flow and provides the CLI entrypoint.
//
//   bun run src/bumper.ts --version-file VERSION --commits commits.log \
//       [--changelog CHANGELOG.md] [--date 2026-06-27] [--dry-run]
//
// It reads the current version (from a plain file or a package.json), inspects
// the conventional-commit log to choose a bump, writes the new version back,
// prepends a changelog entry, and prints a summary plus machine-readable lines.
import { readFile, writeFile } from "node:fs/promises";
import { basename } from "node:path";
import {
  parseVersion,
  formatVersion,
  bumpVersion,
  type BumpType,
  type SemanticVersion,
} from "./semver.ts";
import { parseCommitLog, determineBump, type ParsedCommit } from "./commits.ts";
import { generateChangelogEntry } from "./changelog.ts";

/** Inputs for a bump run. Paths are resolved by the caller / cwd. */
export interface BumpOptions {
  /** Path to the version source: a plain text file or a package.json. */
  versionFile: string;
  /** Path to the conventional commit log file. */
  commitLog: string;
  /** Optional path to a CHANGELOG.md to prepend the new entry to. */
  changelogFile?: string;
  /** ISO date (yyyy-mm-dd) used in the changelog header. */
  date: string;
  /** When true, compute everything but write nothing to disk. */
  dryRun?: boolean;
}

/** The outcome of a bump run. */
export interface BumpResult {
  previousVersion: string;
  newVersion: string;
  bump: BumpType;
  commits: ParsedCommit[];
  changelogEntry: string;
}

const CHANGELOG_HEADER = "# Changelog\n";

/** True if the path looks like a package.json we should edit structurally. */
function isPackageJson(path: string): boolean {
  return basename(path).toLowerCase() === "package.json";
}

/**
 * Read the current version string from the source file. For package.json we
 * parse JSON and read `.version`; otherwise the file content is the version.
 * Throws a descriptive error if the file cannot be read.
 */
async function readCurrentVersion(versionFile: string): Promise<string> {
  let content: string;
  try {
    content = await readFile(versionFile, "utf8");
  } catch {
    throw new Error(`Could not read version file: "${versionFile}". Does it exist?`);
  }

  if (isPackageJson(versionFile)) {
    let pkg: unknown;
    try {
      pkg = JSON.parse(content);
    } catch {
      throw new Error(`Version file "${versionFile}" is not valid JSON.`);
    }
    const version = (pkg as { version?: unknown }).version;
    if (typeof version !== "string") {
      throw new Error(`package.json "${versionFile}" has no string "version" field.`);
    }
    return version;
  }

  return content;
}

/**
 * Persist the new version to the source file, preserving structure:
 *  - package.json: rewrite only the `.version` field, keep formatting + newline.
 *  - plain file: write "X.Y.Z\n".
 */
async function writeNewVersion(versionFile: string, next: SemanticVersion): Promise<void> {
  const formatted = formatVersion(next);
  if (isPackageJson(versionFile)) {
    const content = await readFile(versionFile, "utf8");
    const pkg = JSON.parse(content) as Record<string, unknown>;
    pkg.version = formatted;
    await writeFile(versionFile, JSON.stringify(pkg, null, 2) + "\n");
  } else {
    await writeFile(versionFile, formatted + "\n");
  }
}

/**
 * Prepend `entry` to the changelog file, creating it with a top-level title if
 * it does not yet exist. New entries go directly under the title, newest-first.
 */
async function prependChangelog(changelogFile: string, entry: string): Promise<void> {
  let existing = "";
  try {
    existing = await readFile(changelogFile, "utf8");
  } catch {
    existing = "";
  }

  if (existing.trim().length === 0) {
    await writeFile(changelogFile, `${CHANGELOG_HEADER}\n${entry}`);
    return;
  }

  // If the file starts with a "# Changelog" title, insert after it; else prepend.
  if (existing.startsWith(CHANGELOG_HEADER)) {
    const rest = existing.slice(CHANGELOG_HEADER.length).replace(/^\n+/, "");
    await writeFile(changelogFile, `${CHANGELOG_HEADER}\n${entry}\n${rest}`);
  } else {
    await writeFile(changelogFile, `${entry}\n${existing}`);
  }
}

/**
 * Run the complete bump pipeline. Pure decision-making is delegated to the
 * semver/commits/changelog modules; this function wires in file I/O.
 */
export async function runBump(options: BumpOptions): Promise<BumpResult> {
  const currentRaw = await readCurrentVersion(options.versionFile);
  const current = parseVersion(currentRaw); // throws on invalid version

  let logContent: string;
  try {
    logContent = await readFile(options.commitLog, "utf8");
  } catch {
    throw new Error(`Could not read commit log: "${options.commitLog}". Does it exist?`);
  }

  const commits = parseCommitLog(logContent);
  const bump = determineBump(commits);
  const next = bumpVersion(current, bump);

  const previousVersion = formatVersion(current);
  const newVersion = formatVersion(next);
  const changelogEntry = generateChangelogEntry(newVersion, commits, options.date);

  // Only touch disk when there is an actual bump and we are not in dry-run mode.
  if (!options.dryRun && bump !== "none") {
    await writeNewVersion(options.versionFile, next);
    if (options.changelogFile) {
      await prependChangelog(options.changelogFile, changelogEntry);
    }
  }

  return { previousVersion, newVersion, bump, commits, changelogEntry };
}

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

/** Minimal flag parser: supports `--flag value` and boolean `--flag`. */
function parseArgs(argv: string[]): Record<string, string | boolean> {
  const out: Record<string, string | boolean> = {};
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]!;
    if (!arg.startsWith("--")) continue;
    const key = arg.slice(2);
    const nextArg = argv[i + 1];
    if (nextArg === undefined || nextArg.startsWith("--")) {
      out[key] = true; // boolean flag
    } else {
      out[key] = nextArg;
      i++;
    }
  }
  return out;
}

/** Today's date as yyyy-mm-dd (UTC) for the changelog header. */
function todayIso(): string {
  return new Date().toISOString().slice(0, 10);
}

async function main(): Promise<void> {
  const args = parseArgs(Bun.argv.slice(2));

  const versionFile = (args["version-file"] as string) ?? "VERSION";
  const commitLog = (args["commits"] as string) ?? "commits.log";
  const changelogFile = (args["changelog"] as string) ?? undefined;
  const date = (args["date"] as string) ?? todayIso();
  const dryRun = Boolean(args["dry-run"]);

  const result = await runBump({ versionFile, commitLog, changelogFile, date, dryRun });

  // Human-readable summary to stderr so stdout stays clean for machine parsing.
  console.error(
    `Bump: ${result.bump} | ${result.previousVersion} -> ${result.newVersion}` +
      (dryRun ? " (dry-run, no files written)" : ""),
  );

  // Machine-readable lines on stdout. These exact prefixes are asserted on by
  // the GitHub Actions test harness, so keep them stable.
  console.log(`PREVIOUS_VERSION=${result.previousVersion}`);
  console.log(`NEW_VERSION=${result.newVersion}`);
  console.log(`BUMP=${result.bump}`);
}

// Only run the CLI when executed directly (not when imported by tests).
if (import.meta.main) {
  main().catch((err: unknown) => {
    const message = err instanceof Error ? err.message : String(err);
    console.error(`Error: ${message}`);
    process.exit(1);
  });
}
