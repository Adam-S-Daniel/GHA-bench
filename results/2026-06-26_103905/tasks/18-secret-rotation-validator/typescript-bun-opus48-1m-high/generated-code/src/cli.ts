// CLI plumbing for the Secret Rotation Validator.
//
// This module is split from the executable entry point (validate.ts) so the
// argument parser and the core run() are unit-testable without spawning a
// process or touching the filesystem.

import { formatReport, type OutputFormat } from "./report.ts";
import {
  generateReport,
  parseConfig,
  type RotationReport,
} from "./validator.ts";

/** Severity threshold at which the process should exit non-zero. */
export type FailOn = "none" | "warning" | "expired";

/** Parsed, validated CLI options. */
export interface CliOptions {
  config: string;
  format: OutputFormat;
  warningWindow?: number;
  now?: string;
  output?: string;
  failOn: FailOn;
  help: boolean;
}

const FORMATS: readonly OutputFormat[] = ["markdown", "json"];
const FAIL_ON: readonly FailOn[] = ["none", "warning", "expired"];

export const HELP_TEXT = `Secret Rotation Validator

Usage: bun run validate.ts [options]

Options:
  --config <path>          Path to the secrets config JSON (default: secrets.json)
  --format <markdown|json> Output format (default: markdown)
  --warning-window <days>  Override the config's warning window
  --now <YYYY-MM-DD>       Reference "today" date (default: current UTC date)
  --output <path>          Write the report to a file as well as stdout
  --fail-on <none|warning|expired>
                           Exit non-zero when a secret at/above this urgency
                           exists (default: none)
  -h, --help               Show this help text
`;

/**
 * Parse process arguments (argv without node/script) into CliOptions.
 * Supports both "--flag value" and "--flag=value" styles. Throws Error with a
 * precise message on any malformed or unknown argument.
 */
export function parseArgs(argv: string[]): CliOptions {
  const opts: CliOptions = {
    config: "secrets.json",
    format: "markdown",
    failOn: "none",
    help: false,
  };

  // Pull a value for a flag, either the inline "=value" or the next token.
  let i = 0;
  const takeValue = (flag: string, inline?: string): string => {
    if (inline !== undefined) return inline;
    const next = argv[i + 1];
    if (next === undefined) {
      throw new Error(`Missing value for ${flag}`);
    }
    i += 1;
    return next;
  };

  for (; i < argv.length; i++) {
    const token = argv[i];
    const eq = token.indexOf("=");
    const flag = eq === -1 ? token : token.slice(0, eq);
    const inline = eq === -1 ? undefined : token.slice(eq + 1);

    switch (flag) {
      case "-h":
      case "--help":
        opts.help = true;
        break;
      case "--config":
        opts.config = takeValue(flag, inline);
        break;
      case "--output":
        opts.output = takeValue(flag, inline);
        break;
      case "--now":
        opts.now = takeValue(flag, inline);
        break;
      case "--format": {
        const value = takeValue(flag, inline);
        if (!FORMATS.includes(value as OutputFormat)) {
          throw new Error(
            `Invalid --format '${value}'. Supported: ${FORMATS.join(", ")}`,
          );
        }
        opts.format = value as OutputFormat;
        break;
      }
      case "--fail-on": {
        const value = takeValue(flag, inline);
        if (!FAIL_ON.includes(value as FailOn)) {
          throw new Error(
            `Invalid --fail-on '${value}'. Supported: ${FAIL_ON.join(", ")}`,
          );
        }
        opts.failOn = value as FailOn;
        break;
      }
      case "--warning-window": {
        const value = takeValue(flag, inline);
        const n = Number(value);
        if (!Number.isInteger(n) || n < 0) {
          throw new Error(
            `Invalid --warning-window '${value}': expected a non-negative integer`,
          );
        }
        opts.warningWindow = n;
        break;
      }
      default:
        throw new Error(`Unknown argument: ${token}`);
    }
  }

  return opts;
}

/** Result of a CLI run, kept pure so callers decide how to emit/exit. */
export interface RunResult {
  report: RotationReport;
  output: string;
  exitCode: number;
}

/** Return today's date (UTC) as an ISO calendar date. */
export function todayUtc(): string {
  return new Date().toISOString().slice(0, 10);
}

/**
 * Build the report from already-loaded raw config + options and decide the
 * exit code based on --fail-on. Pure: no I/O, fully testable.
 */
export function runReport(rawConfig: unknown, opts: CliOptions): RunResult {
  const config = parseConfig(rawConfig);
  const now = opts.now ?? todayUtc();
  const report = generateReport(config, now, opts.warningWindow);
  const output = formatReport(report, opts.format);

  let exitCode = 0;
  if (opts.failOn === "expired" && report.summary.expired > 0) {
    exitCode = 1;
  } else if (
    opts.failOn === "warning" &&
    report.summary.expired + report.summary.warning > 0
  ) {
    exitCode = 1;
  }

  return { report, output, exitCode };
}
