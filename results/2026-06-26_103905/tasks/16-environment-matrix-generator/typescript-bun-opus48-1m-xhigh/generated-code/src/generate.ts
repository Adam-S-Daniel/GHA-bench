#!/usr/bin/env bun
// ---------------------------------------------------------------------------
// Executable entry point: read a matrix configuration, generate the GitHub
// Actions strategy, and emit it as JSON.
//
// Config source resolution (first match wins):
//   1. --config <path>           explicit file
//   2. $MATRIX_CONFIG_FILE        environment variable (used by the workflow)
//   3. stdin                      piped JSON
//
// Output:
//   * The complete strategy JSON is written to stdout (compact, or pretty with
//     --pretty) so it can be piped into `jq` or captured by CI.
//   * With --out <path> the same JSON is also written to that file.
//   * A short human summary is written to stderr (kept off stdout so stdout
//     stays clean JSON).
//
// Errors are reported as `Error: <message>` on stderr with a non-zero exit
// code, so a misconfigured pipeline fails fast with a clear diagnostic.
// ---------------------------------------------------------------------------
import { buildStrategy, formatStrategy } from "./cli.ts";

interface CliOptions {
  configPath?: string;
  outPath?: string;
  pretty: boolean;
  help: boolean;
}

const USAGE = `environment-matrix-generator

Generate a GitHub Actions strategy.matrix (JSON) from an OS/language/feature
configuration with include/exclude rules, max-parallel, fail-fast, and a
max-size safety check.

Usage:
  bun run src/generate.ts [--config <path>] [--out <path>] [--pretty]

Options:
  --config <path>   Read the configuration JSON from <path>.
                    Defaults to $MATRIX_CONFIG_FILE, then stdin.
  --out <path>      Also write the generated strategy JSON to <path>.
  --pretty          Pretty-print the JSON (2-space indent).
  -h, --help        Show this help.
`;

/** Parse argv into structured options, failing on unknown/incomplete flags. */
export function parseArgs(argv: string[]): CliOptions {
  const options: CliOptions = { pretty: false, help: false };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    switch (arg) {
      case "--config":
      case "-c":
        options.configPath = expectValue(argv, ++i, arg);
        break;
      case "--out":
      case "-o":
        options.outPath = expectValue(argv, ++i, arg);
        break;
      case "--pretty":
      case "-p":
        options.pretty = true;
        break;
      case "--help":
      case "-h":
        options.help = true;
        break;
      default:
        throw new Error(`Unknown argument: ${arg}`);
    }
  }
  return options;
}

/** Read the flag's value, erroring if it is missing. */
function expectValue(argv: string[], index: number, flag: string): string {
  const value = argv[index];
  if (value === undefined) {
    throw new Error(`Missing value for ${flag}`);
  }
  return value;
}

/** Resolve and read the configuration text from file, env, or stdin. */
async function readConfigText(options: CliOptions): Promise<string> {
  const path = options.configPath ?? process.env.MATRIX_CONFIG_FILE;
  if (path) {
    const file = Bun.file(path);
    if (!(await file.exists())) {
      throw new Error(`Configuration file not found: ${path}`);
    }
    return await file.text();
  }
  // Fall back to stdin (e.g. `cat config.json | bun run src/generate.ts`).
  return await Bun.stdin.text();
}

/** Program body, kept separate so failures route through one error handler. */
async function main(argv: string[]): Promise<number> {
  const options = parseArgs(argv);

  if (options.help) {
    process.stdout.write(USAGE);
    return 0;
  }

  const text = await readConfigText(options);
  if (text.trim().length === 0) {
    throw new Error(
      "No configuration provided. Pass --config <path>, set " +
        "$MATRIX_CONFIG_FILE, or pipe JSON via stdin.",
    );
  }

  const strategy = buildStrategy(text);
  const rendered = formatStrategy(strategy, options.pretty);

  process.stdout.write(rendered + "\n");

  if (options.outPath) {
    await Bun.write(options.outPath, rendered + "\n");
  }

  // Human-friendly summary on stderr (keeps stdout pure JSON).
  process.stderr.write(
    `Generated ${strategy.count} matrix combination(s)` +
      (strategy["max-parallel"] !== undefined
        ? `, max-parallel=${strategy["max-parallel"]}`
        : "") +
      (strategy["fail-fast"] !== undefined
        ? `, fail-fast=${strategy["fail-fast"]}`
        : "") +
      ".\n",
  );

  return 0;
}

// Only run when executed directly (not when imported by a test).
if (import.meta.main) {
  main(process.argv.slice(2))
    .then((code) => process.exit(code))
    .catch((err: unknown) => {
      const message = err instanceof Error ? err.message : String(err);
      process.stderr.write(`Error: ${message}\n`);
      process.exit(1);
    });
}
