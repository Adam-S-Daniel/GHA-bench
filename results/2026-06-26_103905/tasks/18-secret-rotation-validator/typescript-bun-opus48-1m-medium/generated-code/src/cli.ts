// Command-line interface for the secret-rotation validator.
//
// Usage:
//   bun run src/cli.ts --input secrets.json [--warning 14]
//        [--format markdown|json] [--now 2026-06-27] [--fail-on-expired]
//
// The orchestration is split into `parseArgs` (pure) and `run` (pure given an
// injected file reader) so the behaviour is fully unit-testable. The thin
// real-world wrapper at the bottom wires in Bun's file system + process.
import { readFileSync } from "node:fs";
import { parseConfig } from "./config";
import { renderReport, type OutputFormat } from "./report";
import { validateSecrets } from "./validator";

/** Parsed, validated CLI options. */
export interface CliOptions {
  input: string;
  warningWindowDays: number;
  format: OutputFormat;
  /** Optional ISO date string overriding "now" (for deterministic runs). */
  now?: string;
  /** When true, exit non-zero if any secret is expired. */
  failOnExpired: boolean;
}

/** Result of a run, returned instead of touching process directly. */
export interface RunResult {
  stdout: string;
  stderr: string;
  exitCode: number;
}

const DEFAULT_WARNING_DAYS = 14;
const VALID_FORMATS: OutputFormat[] = ["markdown", "json"];

/** Parse argv (without the node/bun + script prefix) into CliOptions. */
export function parseArgs(argv: string[]): CliOptions {
  const opts: CliOptions = {
    input: "",
    warningWindowDays: DEFAULT_WARNING_DAYS,
    format: "markdown",
    failOnExpired: false,
  };

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    switch (arg) {
      case "--input":
      case "-i":
        opts.input = requireValue(argv, ++i, arg);
        break;
      case "--warning":
      case "-w": {
        const raw = requireValue(argv, ++i, arg);
        const n = Number(raw);
        if (!Number.isFinite(n) || n < 0) {
          throw new Error(`--warning must be a non-negative number, got "${raw}"`);
        }
        opts.warningWindowDays = n;
        break;
      }
      case "--format":
      case "-f": {
        const raw = requireValue(argv, ++i, arg) as OutputFormat;
        if (!VALID_FORMATS.includes(raw)) {
          throw new Error(
            `--format must be one of ${VALID_FORMATS.join(", ")}, got "${raw}"`,
          );
        }
        opts.format = raw;
        break;
      }
      case "--now":
        opts.now = requireValue(argv, ++i, arg);
        break;
      case "--fail-on-expired":
        opts.failOnExpired = true;
        break;
      case "--help":
      case "-h":
        // Help is handled by the caller; flag it via a sentinel input.
        opts.input = "--help";
        break;
      default:
        throw new Error(`Unknown argument: "${arg}"`);
    }
  }

  if (opts.input === "") {
    throw new Error("Missing required --input <file> argument");
  }
  return opts;
}

/** Pull the value following a flag, erroring if it is absent. */
function requireValue(argv: string[], index: number, flag: string): string {
  const value = argv[index];
  if (value === undefined) {
    throw new Error(`Missing value for ${flag}`);
  }
  return value;
}

const HELP = `secret-rotation-validator

Identify expired/expiring secrets and produce a rotation report.

Options:
  -i, --input <file>     Path to the secrets JSON config (required)
  -w, --warning <days>   Warning window in days (default: ${DEFAULT_WARNING_DAYS})
  -f, --format <fmt>     Output format: markdown | json (default: markdown)
      --now <date>       Override the reference "now" (ISO date)
      --fail-on-expired  Exit non-zero if any secret is expired
  -h, --help             Show this help
`;

/**
 * Run the validator. Pure given an injected `readFile`; returns the streams
 * and exit code rather than writing to the process so callers (and tests)
 * stay in control.
 *
 * Exit codes:
 *   0  success (or success with no expired secrets under --fail-on-expired)
 *   1  expired secrets found under --fail-on-expired
 *   2  usage / parse / I/O error
 */
export function run(
  argv: string[],
  readFile: (path: string) => string,
): RunResult {
  let opts: CliOptions;
  try {
    opts = parseArgs(argv);
  } catch (err) {
    return { stdout: "", stderr: message(err), exitCode: 2 };
  }

  if (opts.input === "--help") {
    return { stdout: HELP, stderr: "", exitCode: 0 };
  }

  let text: string;
  try {
    text = readFile(opts.input);
  } catch (err) {
    return {
      stdout: "",
      stderr: `Could not read input file "${opts.input}": ${message(err)}`,
      exitCode: 2,
    };
  }

  let stdout: string;
  let report;
  try {
    const secrets = parseConfig(text);
    const now = opts.now ? new Date(opts.now) : new Date();
    if (Number.isNaN(now.getTime())) {
      throw new Error(`Invalid --now date: "${opts.now}"`);
    }
    report = validateSecrets(secrets, {
      now,
      warningWindowDays: opts.warningWindowDays,
    });
    stdout = renderReport(report, opts.format);
  } catch (err) {
    return { stdout: "", stderr: message(err), exitCode: 2 };
  }

  const exitCode =
    opts.failOnExpired && report.summary.expired > 0 ? 1 : 0;
  return { stdout, stderr: "", exitCode };
}

/** Safely extract a message from an unknown thrown value. */
function message(err: unknown): string {
  return err instanceof Error ? err.message : String(err);
}

// Real entrypoint: only runs when executed directly (not when imported by
// tests). Wires up the actual file system and process streams.
if (import.meta.main) {
  const result = run(Bun.argv.slice(2), (path) => readFileSync(path, "utf8"));
  if (result.stdout) process.stdout.write(result.stdout);
  if (result.stderr) process.stderr.write(result.stderr + "\n");
  process.exit(result.exitCode);
}
