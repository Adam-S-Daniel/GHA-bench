/**
 * CLI entry point (cycle 6). Run with:
 *
 *   bun run src/cli.ts --version-file VERSION \
 *     --commits-file fixtures/commits-feat.log \
 *     [--changelog-file CHANGELOG.md] [--date YYYY-MM-DD]
 *
 * Output contract (the CI workflow greps these exact lines):
 *   OLD_VERSION=<x.y.z>
 *   BUMP=<major|minor|patch|none>
 *   NEW_VERSION=<x.y.z>
 * The bare new version is also printed last for human eyes.
 */
import { runBumper, type BumperOptions } from "./bumper";

const USAGE = `Usage: bun run src/cli.ts --version-file <path> --commits-file <path> [options]

Options:
  --version-file <path>    VERSION file or package.json to read/update (required)
  --commits-file <path>    commit-log file, messages separated by ====COMMIT==== (required)
  --changelog-file <path>  changelog to prepend the entry to (default: CHANGELOG.md)
  --date <YYYY-MM-DD>      release date stamp (default: today, UTC)
`;

/** Parse argv into BumperOptions; throws on unknown/missing arguments. */
export function parseArgs(argv: string[]): BumperOptions {
  const opts: Partial<Record<string, string>> = {};
  const flagToKey: Record<string, string> = {
    "--version-file": "versionFile",
    "--commits-file": "commitsFile",
    "--changelog-file": "changelogFile",
    "--date": "date",
  };

  for (let i = 0; i < argv.length; i += 2) {
    const flag = argv[i]!;
    const key = flagToKey[flag];
    if (!key) throw new Error(`Unknown argument: ${flag}\n\n${USAGE}`);
    const value = argv[i + 1];
    if (value === undefined) throw new Error(`Missing value for ${flag}\n\n${USAGE}`);
    opts[key] = value;
  }

  if (!opts.versionFile) throw new Error(`--version-file is required\n\n${USAGE}`);
  if (!opts.commitsFile) throw new Error(`--commits-file is required\n\n${USAGE}`);

  return {
    versionFile: opts.versionFile,
    commitsFile: opts.commitsFile,
    changelogFile: opts.changelogFile ?? "CHANGELOG.md",
    date: opts.date ?? new Date().toISOString().slice(0, 10),
  };
}

// Only execute when invoked directly (not when imported by tests).
if (import.meta.main) {
  try {
    const result = runBumper(parseArgs(process.argv.slice(2)));
    console.log(`OLD_VERSION=${result.oldVersion}`);
    console.log(`BUMP=${result.bump}`);
    console.log(`NEW_VERSION=${result.newVersion}`);
    console.log(result.newVersion);
  } catch (err) {
    console.error(`error: ${err instanceof Error ? err.message : String(err)}`);
    process.exit(1);
  }
}
