#!/usr/bin/env bun
/**
 * pr-label-assigner CLI.
 *
 * Reads a path-to-label rule config and a list of changed file paths, then
 * prints the final label set. This is the entry point invoked by the GitHub
 * Actions workflow.
 *
 * Usage:
 *   bun run src/cli.ts --config <config.json> --files <files.txt>
 *   bun run src/cli.ts --config <config.json> < files.txt   (files from stdin)
 *
 * Options:
 *   --config <path>   JSON rule config (default: .github/labeler-config.json)
 *   --files  <path>   Newline-delimited changed-file list (default: stdin)
 *   --help            Show usage.
 *
 * Output (stdout):
 *   A human-readable summary, plus a machine-parseable line:
 *     LABELS=api,tests,documentation
 *   (empty label set prints `LABELS=`). Errors go to stderr with a non-zero
 *   exit code so CI fails loudly.
 */
import { assignLabels, parseConfig } from "./labeler.ts";

interface CliOptions {
  config: string;
  files?: string;
  help: boolean;
}

/** Parse argv into structured options. Throws on unknown/incomplete flags. */
export function parseArgs(argv: string[]): CliOptions {
  const opts: CliOptions = {
    config: ".github/labeler-config.json",
    help: false,
  };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    switch (arg) {
      case "--help":
      case "-h":
        opts.help = true;
        break;
      case "--config":
      case "-c":
        opts.config = requireValue(argv, ++i, arg);
        break;
      case "--files":
      case "-f":
        opts.files = requireValue(argv, ++i, arg);
        break;
      default:
        throw new Error(`Unknown argument: ${arg}`);
    }
  }
  return opts;
}

function requireValue(argv: string[], i: number, flag: string): string {
  const value = argv[i];
  if (value === undefined) throw new Error(`Missing value for ${flag}`);
  return value;
}

const USAGE = `pr-label-assigner — assign PR labels from changed file paths.

Usage:
  bun run src/cli.ts --config <config.json> --files <files.txt>
  bun run src/cli.ts --config <config.json> < files.txt

Options:
  -c, --config <path>  JSON rule config (default: .github/labeler-config.json)
  -f, --files  <path>  Newline-delimited changed-file list (default: stdin)
  -h, --help           Show this help.`;

/** Read newline-delimited file paths from a file or from stdin. */
async function readFileList(path: string | undefined): Promise<string[]> {
  const raw =
    path === undefined
      ? await new Response(Bun.stdin.stream()).text()
      : await Bun.file(path).text();
  return raw
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.length > 0);
}

/** Main entry point. Returns a process exit code. */
export async function main(argv: string[]): Promise<number> {
  let opts: CliOptions;
  try {
    opts = parseArgs(argv);
  } catch (err) {
    console.error(`Error: ${err instanceof Error ? err.message : err}`);
    console.error(`\n${USAGE}`);
    return 2;
  }

  if (opts.help) {
    console.log(USAGE);
    return 0;
  }

  // Load and validate the rule config.
  let rules;
  try {
    const configFile = Bun.file(opts.config);
    if (!(await configFile.exists())) {
      throw new Error(`config file not found: ${opts.config}`);
    }
    rules = parseConfig(await configFile.text());
  } catch (err) {
    console.error(
      `Error reading config: ${err instanceof Error ? err.message : err}`,
    );
    return 1;
  }

  // Load the changed-file list.
  let files: string[];
  try {
    files = await readFileList(opts.files);
  } catch (err) {
    console.error(
      `Error reading file list: ${err instanceof Error ? err.message : err}`,
    );
    return 1;
  }

  // Compute and report labels.
  const labels = assignLabels(files, rules);
  console.log(`Changed files (${files.length}):`);
  for (const f of files) console.log(`  - ${f}`);
  console.log(`Assigned ${labels.length} label(s):`);
  for (const l of labels) console.log(`  * ${l}`);
  // Machine-parseable line for CI consumption.
  console.log(`LABELS=${labels.join(",")}`);
  return 0;
}

// Run only when executed directly (not when imported by tests).
if (import.meta.main) {
  process.exit(await main(Bun.argv.slice(2)));
}
