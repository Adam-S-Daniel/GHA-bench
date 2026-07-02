/**
 * CLI entry point for the secret rotation validator.
 *
 * Usage:
 *   bun run src/cli.ts [--config <path>] [--warning-days <n>]
 *                      [--format markdown|json] [--now YYYY-MM-DD]
 *                      [--fail-on-expired]
 *
 * runCli is a pure function (args in, result out) so the argument parsing
 * and error paths are unit-testable; only the bottom of this file touches
 * process.argv / process.exit.
 */
import { loadConfig } from "./config";
import { buildReport } from "./validator";
import { formatJson, formatMarkdown } from "./format";

const USAGE = `Usage: bun run src/cli.ts [options]
  --config <path>       Secrets configuration JSON (default: fixtures/secrets.json)
  --warning-days <n>    Warning window in days (default: 14)
  --format <fmt>        Output format: markdown | json (default: markdown)
  --now <YYYY-MM-DD>    Evaluate as of this date (default: today, UTC)
  --fail-on-expired     Exit with code 2 if any secret is expired`;

export interface CliResult {
  exitCode: number;
  stdout: string;
  stderr: string;
}

interface CliOptions {
  config: string;
  warningDays: number;
  format: "markdown" | "json";
  now: Date;
  failOnExpired: boolean;
}

/** Parse argv into options, throwing descriptive errors for bad input. */
function parseArgs(args: string[]): CliOptions {
  const options: CliOptions = {
    config: "fixtures/secrets.json",
    warningDays: 14,
    format: "markdown",
    now: new Date(),
    failOnExpired: false,
  };

  // Each value-taking flag consumes the next argument; validate eagerly so
  // the error message points at the exact flag the user got wrong.
  const takeValue = (flag: string, i: number): string => {
    const value = args[i + 1];
    if (value === undefined) {
      throw new Error(`Option ${flag} requires a value`);
    }
    return value;
  };

  for (let i = 0; i < args.length; i++) {
    const arg = args[i]!;
    switch (arg) {
      case "--config":
        options.config = takeValue(arg, i++);
        break;
      case "--warning-days": {
        const raw = takeValue(arg, i++);
        const parsed = Number(raw);
        if (!Number.isInteger(parsed) || parsed < 0) {
          throw new Error(
            `Invalid --warning-days "${raw}" (expected a non-negative integer)`,
          );
        }
        options.warningDays = parsed;
        break;
      }
      case "--format": {
        const raw = takeValue(arg, i++);
        if (raw !== "markdown" && raw !== "json") {
          throw new Error(
            `Invalid --format "${raw}" (expected "markdown" or "json")`,
          );
        }
        options.format = raw;
        break;
      }
      case "--now": {
        const raw = takeValue(arg, i++);
        const ms = /^\d{4}-\d{2}-\d{2}$/.test(raw)
          ? Date.parse(`${raw}T00:00:00Z`)
          : NaN;
        if (Number.isNaN(ms)) {
          throw new Error(`Invalid --now date: "${raw}" (expected YYYY-MM-DD)`);
        }
        options.now = new Date(ms);
        break;
      }
      case "--fail-on-expired":
        options.failOnExpired = true;
        break;
      default:
        throw new Error(`Unknown option: ${arg}`);
    }
  }
  return options;
}

/** Run the validator end-to-end. Never throws; errors become exitCode 1. */
export function runCli(args: string[]): CliResult {
  let options: CliOptions;
  try {
    options = parseArgs(args);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return { exitCode: 1, stdout: "", stderr: `Error: ${message}\n${USAGE}` };
  }

  try {
    const secrets = loadConfig(options.config);
    const report = buildReport(secrets, options.now, options.warningDays);
    const output =
      options.format === "json" ? formatJson(report) : formatMarkdown(report);

    if (options.failOnExpired && report.expired.length > 0) {
      return {
        exitCode: 2,
        stdout: output,
        stderr: `Error: ${report.expired.length} secret(s) are expired — rotation required`,
      };
    }
    return { exitCode: 0, stdout: output, stderr: "" };
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return { exitCode: 1, stdout: "", stderr: `Error: ${message}` };
  }
}

// Only execute when run directly (`bun run src/cli.ts`), not when imported.
if (import.meta.main) {
  const result = runCli(process.argv.slice(2));
  if (result.stdout) console.log(result.stdout);
  if (result.stderr) console.error(result.stderr);
  process.exit(result.exitCode);
}
