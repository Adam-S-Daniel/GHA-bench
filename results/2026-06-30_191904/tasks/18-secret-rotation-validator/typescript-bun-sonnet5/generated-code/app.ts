#!/usr/bin/env bun
// Secret Rotation Validator CLI.
//
// Given a JSON config describing mock secrets (name, last-rotated date,
// rotation policy in days, required-by services), reports which secrets
// are expired, expiring soon (within a warning window), or ok — as either
// a markdown table or JSON.
//
// Usage:
//   bun run app.ts --config <path> [--format markdown|json] [--warning-window <days>] [--now <YYYY-MM-DD>]
import { loadConfigFile, SecretConfigError } from "./src/config.ts";
import { parseIsoDate } from "./src/dateUtils.ts";
import { formatReport } from "./src/format.ts";
import { generateReport } from "./src/report.ts";
import type { OutputFormat } from "./src/types.ts";

/** Thrown for invalid or missing CLI arguments. */
export class CliUsageError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "CliUsageError";
  }
}

export interface CliOptions {
  configPath: string;
  format: OutputFormat;
  warningWindowDays?: number;
  now: Date;
}

export interface RunResult {
  exitCode: number;
  output: string;
}

/** Parses CLI flags into a validated CliOptions object. */
export function parseArgs(argv: string[]): CliOptions {
  let configPath: string | undefined;
  let format: OutputFormat = "markdown";
  let warningWindowDays: number | undefined;
  let now: Date = new Date();

  for (let i = 0; i < argv.length; i++) {
    const flag = argv[i];
    const value = argv[i + 1];
    switch (flag) {
      case "--config":
        if (value === undefined) throw new CliUsageError("--config requires a value");
        configPath = value;
        i++;
        break;
      case "--format":
        if (value !== "markdown" && value !== "json") {
          throw new CliUsageError(`--format must be "markdown" or "json", got ${JSON.stringify(value)}`);
        }
        format = value;
        i++;
        break;
      case "--warning-window": {
        if (value === undefined) throw new CliUsageError("--warning-window requires a value");
        const parsed = Number(value);
        if (!Number.isFinite(parsed) || parsed < 0) {
          throw new CliUsageError(`--warning-window must be a non-negative number, got ${JSON.stringify(value)}`);
        }
        warningWindowDays = parsed;
        i++;
        break;
      }
      case "--now":
        if (value === undefined) throw new CliUsageError("--now requires a value");
        now = parseIsoDate(value);
        i++;
        break;
      default:
        throw new CliUsageError(`Unrecognized argument: ${flag}`);
    }
  }

  if (configPath === undefined) {
    throw new CliUsageError("Missing required argument: --config <path>");
  }

  return { configPath, format, warningWindowDays, now };
}

/**
 * Runs the full pipeline (load config -> generate report -> format output)
 * without touching process.exit or stdio, so it's directly unit-testable.
 */
export async function run(options: CliOptions): Promise<RunResult> {
  try {
    const config = await loadConfigFile(options.configPath);
    const report = generateReport(config, options.now, options.warningWindowDays);
    return { exitCode: 0, output: formatReport(report, options.format) };
  } catch (cause) {
    if (cause instanceof SecretConfigError) {
      return { exitCode: 1, output: `Error: ${cause.message}` };
    }
    throw cause;
  }
}

async function main(): Promise<void> {
  let options: CliOptions;
  try {
    options = parseArgs(Bun.argv.slice(2));
  } catch (cause) {
    if (cause instanceof CliUsageError) {
      console.error(`Error: ${cause.message}`);
      console.error("Usage: bun run app.ts --config <path> [--format markdown|json] [--warning-window <days>] [--now <YYYY-MM-DD>]");
      process.exit(1);
    }
    throw cause;
  }

  const result = await run(options);
  if (result.exitCode === 0) {
    console.log(result.output);
  } else {
    console.error(result.output);
  }
  process.exit(result.exitCode);
}

if (import.meta.main) {
  main();
}
