/**
 * Command-line orchestration for the secret rotation validator.
 *
 * Design: `main()` receives an injected {@link CliIO} (file reader, output
 * sinks, and a clock). This keeps the whole flow pure-ish and deterministic for
 * testing — no globals, no real filesystem, no wall clock — while the thin
 * `validate.ts` entrypoint wires in the real Bun-backed implementations.
 *
 * Exit-code contract (conventional for CI gates):
 *   0  success (and the --fail-on policy, if any, is satisfied)
 *   1  the --fail-on threshold was breached (e.g. an expired secret exists)
 *   2  a usage / I/O / validation error occurred
 */
import { parseConfig, parseWarningWindow } from "./config";
import { buildReport, parseDate, formatDate } from "./validator";
import { formatReport } from "./formatters";
import type { OutputFormat, RotationReport } from "./types";

/** When the validator should report failure via a non-zero (1) exit code. */
export type FailOn = "none" | "warning" | "expired";

/** Fully-parsed CLI options. */
export interface CliOptions {
  config?: string;
  warningDays: number;
  format: OutputFormat;
  now?: string;
  failOn: FailOn;
  help: boolean;
}

/** Injected I/O so `main()` can be tested without real side effects. */
export interface CliIO {
  readFile(path: string): Promise<string>;
  stdout(text: string): void;
  stderr(text: string): void;
  now(): Date;
}

export const USAGE = `Usage: bun run validate.ts --config <path> [options]

Identify secrets that are expired or expiring soon and emit a rotation report.

Options:
  --config <path>       Path to the secrets JSON config (required).
  --warning-days <n>    Warning window in days; secrets expiring within this
                        window are flagged "warning" (default: 14).
  --format <fmt>        Output format: markdown | json | github (default: markdown).
  --now <YYYY-MM-DD>    Reference date for the evaluation (default: today, UTC).
  --fail-on <level>     Exit 1 when this urgency is present: none | warning | expired
                        (default: none).
  --help, -h            Show this help.
`;

const VALID_FORMATS: readonly OutputFormat[] = ["markdown", "json", "github"];
const VALID_FAIL_ON: readonly FailOn[] = ["none", "warning", "expired"];

/** Split `--key=value` tokens into `--key`, `value` for uniform parsing. */
function normalize(argv: string[]): string[] {
  const out: string[] = [];
  for (const arg of argv) {
    if (arg.startsWith("--") && arg.includes("=")) {
      const eq = arg.indexOf("=");
      out.push(arg.slice(0, eq), arg.slice(eq + 1));
    } else {
      out.push(arg);
    }
  }
  return out;
}

/** Pull the value following a flag, erroring if it is absent or is another flag. */
function requireValue(argv: string[], index: number, flag: string): string {
  const value = argv[index];
  if (value === undefined || value.startsWith("--")) {
    throw new Error(`Missing value for ${flag}.`);
  }
  return value;
}

function parseFormat(value: string): OutputFormat {
  if (!VALID_FORMATS.includes(value as OutputFormat)) {
    throw new Error(`--format must be one of: ${VALID_FORMATS.join(", ")} (got "${value}").`);
  }
  return value as OutputFormat;
}

function parseFailOn(value: string): FailOn {
  if (!VALID_FAIL_ON.includes(value as FailOn)) {
    throw new Error(`--fail-on must be one of: ${VALID_FAIL_ON.join(", ")} (got "${value}").`);
  }
  return value as FailOn;
}

/** Parse raw argv (already normalized) into {@link CliOptions}; throws on bad input. */
export function parseArgs(rawArgv: string[]): CliOptions {
  const argv = normalize(rawArgv);
  const opts: CliOptions = {
    warningDays: 14,
    format: "markdown",
    failOn: "none",
    help: false,
  };

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]!;
    switch (arg) {
      case "--help":
      case "-h":
        opts.help = true;
        break;
      case "--config":
        opts.config = requireValue(argv, ++i, "--config");
        break;
      case "--warning-days":
        opts.warningDays = parseWarningWindow(requireValue(argv, ++i, "--warning-days"));
        break;
      case "--format":
        opts.format = parseFormat(requireValue(argv, ++i, "--format"));
        break;
      case "--now":
        opts.now = requireValue(argv, ++i, "--now");
        break;
      case "--fail-on":
        opts.failOn = parseFailOn(requireValue(argv, ++i, "--fail-on"));
        break;
      default:
        throw new Error(`Unknown argument: ${arg}`);
    }
  }

  return opts;
}

/** Map the report + policy onto the process exit code (0 ok / 1 policy breach). */
function exitCodeFor(report: RotationReport, failOn: FailOn): number {
  const { expired, warning } = report.summary;
  if (failOn === "expired") return expired > 0 ? 1 : 0;
  if (failOn === "warning") return expired + warning > 0 ? 1 : 0;
  return 0;
}

/**
 * Run the CLI. Returns the intended process exit code. Never throws: all errors
 * are caught and reported to `io.stderr` with a meaningful message.
 */
export async function main(rawArgv: string[], io: CliIO): Promise<number> {
  let opts: CliOptions;
  try {
    opts = parseArgs(rawArgv);
  } catch (err) {
    io.stderr(`Error: ${(err as Error).message}\n\n`);
    io.stderr(USAGE);
    return 2;
  }

  if (opts.help) {
    io.stdout(USAGE);
    return 0;
  }

  if (!opts.config) {
    io.stderr("Error: --config <path> is required.\n\n");
    io.stderr(USAGE);
    return 2;
  }

  let report: RotationReport;
  try {
    const raw = await io.readFile(opts.config);
    let parsed: unknown;
    try {
      parsed = JSON.parse(raw);
    } catch {
      throw new Error(`Config file "${opts.config}" is not valid JSON.`);
    }
    const secrets = parseConfig(parsed);
    // Reference date: explicit --now wins; otherwise truncate the injected
    // clock to UTC midnight so day math is always whole-day and reproducible.
    const now = opts.now ? parseDate(opts.now) : parseDate(formatDate(io.now()));
    report = buildReport(secrets, now, opts.warningDays);
  } catch (err) {
    io.stderr(`Error: ${(err as Error).message}\n`);
    return 2;
  }

  const rendered = formatReport(report, opts.format);
  io.stdout(rendered.endsWith("\n") ? rendered : rendered + "\n");
  return exitCodeFor(report, opts.failOn);
}
