// index.ts — the command-line entry point for the semantic version bumper.
//
// The CLI is intentionally thin: argument parsing and result formatting live
// here, while all real work is delegated to runBump(). runCli() returns its
// stdout/stderr/exit-code instead of writing to the console so it can be
// driven directly from tests; the `import.meta.main` guard at the bottom is
// the only place that actually touches process I/O.

import { runBump, type BumpResult } from "./bumper.ts";

/** Fully-resolved CLI options. */
export interface CliOptions {
  versionFilePath: string;
  commitsPath: string;
  changelogPath: string;
  date: string;
  delimiter?: string;
  dryRun: boolean;
  help: boolean;
}

/** Structured result of a CLI invocation. */
export interface CliRun {
  exitCode: number;
  stdout: string[];
  stderr: string[];
}

const USAGE = `Usage: bun run src/index.ts [options]

Determine the next semantic version from conventional commit messages,
update the version file, and generate a changelog entry.

Options:
  -f, --version-file <path>   Version source: package.json or a plain file (required)
  -c, --commits <path>        Commit-log fixture/file to analyse (required)
      --changelog <path>      Changelog file to update (default: CHANGELOG.md)
      --date <YYYY-MM-DD>     Date stamped on the changelog entry (default: today)
      --delimiter <string>    Commit separator line in the log (default: --COMMIT--)
      --dry-run               Compute everything but write no files
  -h, --help                  Show this help and exit`;

/**
 * Parse argv into {@link CliOptions}. `today` supplies the default date so the
 * function stays pure (the clock is read by the caller).
 * @throws Error on unknown options or missing values.
 */
export function parseArgs(argv: string[], today: string): CliOptions {
  const opts: CliOptions = {
    versionFilePath: "",
    commitsPath: "",
    changelogPath: "CHANGELOG.md",
    date: today,
    delimiter: undefined,
    dryRun: false,
    help: false,
  };

  // Read the value following a flag, erroring if it is missing.
  const valueAfter = (i: number, flag: string): string => {
    const v = argv[i + 1];
    if (v === undefined) throw new Error(`Missing value for ${flag}`);
    return v;
  };

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    switch (arg) {
      case "-f":
      case "--version-file":
        opts.versionFilePath = valueAfter(i, arg);
        i++;
        break;
      case "-c":
      case "--commits":
        opts.commitsPath = valueAfter(i, arg);
        i++;
        break;
      case "--changelog":
        opts.changelogPath = valueAfter(i, arg);
        i++;
        break;
      case "--date":
        opts.date = valueAfter(i, arg);
        i++;
        break;
      case "--delimiter":
        opts.delimiter = valueAfter(i, arg);
        i++;
        break;
      case "--dry-run":
        opts.dryRun = true;
        break;
      case "-h":
      case "--help":
        opts.help = true;
        break;
      default:
        throw new Error(`Unknown option: ${arg}`);
    }
  }

  return opts;
}

/** Today's date as YYYY-MM-DD, used as the default changelog date. */
function todayIso(): string {
  return new Date().toISOString().slice(0, 10);
}

/** Format the result into machine-readable + human-readable stdout lines. */
function formatResult(result: BumpResult, dryRun: boolean): string[] {
  const lines: string[] = [];
  // Machine-readable block — easy to grep from CI logs.
  lines.push(`PREVIOUS_VERSION=${result.previousVersion}`);
  lines.push(`NEW_VERSION=${result.newVersion}`);
  lines.push(`BUMP_TYPE=${result.bump}`);
  lines.push(`CHANGED=${result.changed}`);
  // Human-readable summary.
  if (result.changed) {
    lines.push(
      `${dryRun ? "[dry-run] " : ""}Bumped ${result.previousVersion} -> ${result.newVersion} (${result.bump}).`,
    );
  } else {
    lines.push(`No release-worthy commits; version stays at ${result.newVersion}.`);
  }
  return lines;
}

/** Append GitHub Actions step outputs to $GITHUB_OUTPUT, if configured. */
async function writeGithubOutput(
  path: string | undefined,
  result: BumpResult,
): Promise<void> {
  if (!path) return;
  const existing = (await Bun.file(path).exists())
    ? await Bun.file(path).text()
    : "";
  const block =
    `previous-version=${result.previousVersion}\n` +
    `new-version=${result.newVersion}\n` +
    `bump-type=${result.bump}\n` +
    `changed=${result.changed}\n`;
  await Bun.write(path, existing + block);
}

/**
 * Run the CLI end-to-end. Returns structured output instead of printing, so
 * tests can assert on it and the thin `main` wrapper can render it.
 */
export async function runCli(
  argv: string[],
  env: Record<string, string | undefined>,
): Promise<CliRun> {
  let opts: CliOptions;
  try {
    opts = parseArgs(argv, todayIso());
  } catch (err) {
    return { exitCode: 2, stdout: [], stderr: [(err as Error).message, "", USAGE] };
  }

  if (opts.help) {
    return { exitCode: 0, stdout: [USAGE], stderr: [] };
  }

  // Validate required options with a friendly, actionable message.
  const missing: string[] = [];
  if (!opts.versionFilePath) missing.push("--version-file");
  if (!opts.commitsPath) missing.push("--commits");
  if (missing.length > 0) {
    return {
      exitCode: 2,
      stdout: [],
      stderr: [`Missing required option(s): ${missing.join(", ")}`, "", USAGE],
    };
  }

  try {
    const result = await runBump({
      versionFilePath: opts.versionFilePath,
      commitsPath: opts.commitsPath,
      changelogPath: opts.changelogPath,
      date: opts.date,
      delimiter: opts.delimiter,
      dryRun: opts.dryRun,
    });
    await writeGithubOutput(env.GITHUB_OUTPUT, result);
    return { exitCode: 0, stdout: formatResult(result, opts.dryRun), stderr: [] };
  } catch (err) {
    return { exitCode: 1, stdout: [], stderr: [`Error: ${(err as Error).message}`] };
  }
}

// Real entry point: execute, print, and exit. Only runs when invoked directly.
if (import.meta.main) {
  const run = await runCli(Bun.argv.slice(2), process.env);
  if (run.stdout.length > 0) console.log(run.stdout.join("\n"));
  if (run.stderr.length > 0) console.error(run.stderr.join("\n"));
  process.exit(run.exitCode);
}
