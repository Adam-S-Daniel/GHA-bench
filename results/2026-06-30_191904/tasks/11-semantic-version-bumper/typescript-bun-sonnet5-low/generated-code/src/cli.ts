// CLI entry point: reads a version file and a commit-log file, determines
// the next semantic version, writes it back, and prepends a changelog entry.
import {
  parseVersion,
  formatVersion,
  determineBumpType,
  bumpVersion,
  generateChangelogEntry,
  readVersionFile,
  writeVersionFile,
} from "./versionBumper";

export interface RunOptions {
  versionFile: string;
  commitsFile: string;
  changelogFile: string;
}

export interface RunResult {
  previousVersion: string;
  newVersion: string;
  bumpType: string;
}

/** Parses a raw commit-log file (one message per line, blank lines separate). */
function parseCommitLog(raw: string): string[] {
  return raw
    .split(/\n{2,}/)
    .map((block) => block.trim())
    .filter((block) => block.length > 0);
}

/** Runs the full version-bump flow and returns the outcome. */
export async function runVersionBump(options: RunOptions): Promise<RunResult> {
  const { versionFile, commitsFile, changelogFile } = options;

  const commitLogFile = Bun.file(commitsFile);
  if (!(await commitLogFile.exists())) {
    throw new Error(`Commit log file not found: "${commitsFile}".`);
  }
  const rawCommits = await commitLogFile.text();
  const commits = parseCommitLog(rawCommits);
  if (commits.length === 0) {
    throw new Error("No commits found in the commit log file.");
  }

  const bumpType = determineBumpType(commits);
  if (bumpType === "none") {
    throw new Error(
      "No version bump required: no feat/fix/breaking-change commits were found.",
    );
  }

  const previousVersionString = await readVersionFile(versionFile);
  const previousVersion = parseVersion(previousVersionString);
  const newVersion = bumpVersion(previousVersion, bumpType);
  const newVersionString = formatVersion(newVersion);

  await writeVersionFile(versionFile, newVersion);

  const entry = generateChangelogEntry(newVersionString, commits);
  const changelogFileHandle = Bun.file(changelogFile);
  const existingChangelog = (await changelogFileHandle.exists())
    ? await changelogFileHandle.text()
    : "# Changelog\n";
  const [header, ...rest] = existingChangelog.split("\n\n");
  const body = rest.join("\n\n");
  const updatedChangelog = body
    ? `${header}\n\n${entry}\n\n${body}`
    : `${header}\n\n${entry}\n`;
  await Bun.write(changelogFile, updatedChangelog);

  return {
    previousVersion: previousVersionString,
    newVersion: newVersionString,
    bumpType,
  };
}

// Allow running as a standalone script: `bun run src/cli.ts`
if (import.meta.main) {
  const versionFile = process.env.VERSION_FILE ?? "version.json";
  const commitsFile = process.env.COMMITS_FILE ?? "commits.txt";
  const changelogFile = process.env.CHANGELOG_FILE ?? "CHANGELOG.md";

  try {
    const result = await runVersionBump({ versionFile, commitsFile, changelogFile });
    console.log(`Previous version: ${result.previousVersion}`);
    console.log(`Bump type: ${result.bumpType}`);
    console.log(`New version: ${result.newVersion}`);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(`Error: ${message}`);
    process.exit(1);
  }
}
