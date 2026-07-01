// Orchestrates a full version bump: read the version file + commit log,
// determine the bump type, compute the next version, and (unless the bump
// type is "none") write the version file and prepend a changelog entry.
import { generateChangelogEntry } from "./changelog.ts";
import { determineBumpType, parseCommitLog } from "./commits.ts";
import type { BumpType } from "./semver.ts";
import { bumpVersion, formatVersion, parseVersion } from "./semver.ts";
import { readVersionFile } from "./version-file.ts";

export interface BumpOptions {
  versionFilePath: string;
  commitsLogPath: string;
  changelogPath: string;
  /** ISO date (YYYY-MM-DD) stamped on the changelog entry. */
  date: string;
}

export interface BumpResult {
  previousVersion: string;
  newVersion: string;
  bumpType: BumpType;
  /** The changelog entry text, or null if no entry was written (bumpType "none"). */
  changelogEntry: string | null;
}

async function readCommitLog(path: string): Promise<string> {
  const file = Bun.file(path);
  if (!(await file.exists())) {
    throw new Error(
      `Commit log not found: "${path}". Provide a file containing \`git log\` output.`,
    );
  }
  return file.text();
}

async function prependChangelog(path: string, entry: string): Promise<void> {
  const file = Bun.file(path);
  const exists = await file.exists();
  const existing = exists ? await file.text() : "";

  if (!exists) {
    await Bun.write(path, `# Changelog\n\n${entry}`);
    return;
  }

  // Insert the new entry right after the "# Changelog" title (if present),
  // otherwise at the very top of the file.
  const titleMatch = /^# Changelog\n+/.exec(existing);
  if (titleMatch) {
    const title = titleMatch[0];
    const rest = existing.slice(title.length);
    await Bun.write(path, `${title}${entry}\n${rest}`);
  } else {
    await Bun.write(path, `${entry}\n${existing}`);
  }
}

export async function runBump(options: BumpOptions): Promise<BumpResult> {
  const versionFile = await readVersionFile(options.versionFilePath);
  const rawLog = await readCommitLog(options.commitsLogPath);
  const commits = parseCommitLog(rawLog);

  const bumpType = determineBumpType(commits);
  const previousVersion = parseVersion(versionFile.version);
  const nextVersion = bumpVersion(previousVersion, bumpType);
  const newVersionString = formatVersion(nextVersion);

  if (bumpType === "none") {
    return {
      previousVersion: versionFile.version,
      newVersion: versionFile.version,
      bumpType,
      changelogEntry: null,
    };
  }

  await versionFile.write(newVersionString);
  const changelogEntry = generateChangelogEntry(newVersionString, options.date, commits);
  await prependChangelog(options.changelogPath, changelogEntry);

  return {
    previousVersion: versionFile.version,
    newVersion: newVersionString,
    bumpType,
    changelogEntry,
  };
}
