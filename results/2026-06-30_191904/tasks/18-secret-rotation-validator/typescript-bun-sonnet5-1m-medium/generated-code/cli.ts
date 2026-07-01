// CLI entry point: reads a rotation config file, validates it, and prints a
// report in the requested format. Exits non-zero when any secret is expired
// so CI pipelines can fail the build on stale secrets.

import { formatReport } from "./report.ts";
import type { OutputFormat, RotationConfig, RotationReport } from "./types.ts";
import { validateSecrets } from "./validator.ts";

export interface CliOptions {
  configPath: string;
  format: OutputFormat;
  warningDaysOverride?: number;
  /** Overrides the reference date used for expiry math (mainly for deterministic CI runs). */
  now?: Date;
}

/** Parses CLI arguments into structured options, with clear errors on misuse. */
export function parseArgs(argv: string[]): CliOptions {
  const positional: string[] = [];
  let format: OutputFormat = "markdown";
  let warningDaysOverride: number | undefined;
  let now: Date | undefined;

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--format") {
      const value = argv[++i];
      if (value !== "markdown" && value !== "json") {
        throw new Error(`Invalid --format value: "${value}". Expected "markdown" or "json".`);
      }
      format = value;
    } else if (arg === "--warning-days") {
      const value = Number(argv[++i]);
      if (!Number.isFinite(value)) {
        throw new Error(`Invalid --warning-days value: "${argv[i]}". Expected a number.`);
      }
      warningDaysOverride = value;
    } else if (arg === "--now") {
      const value = argv[++i];
      const parsed = value === undefined ? Number.NaN : new Date(value).getTime();
      if (Number.isNaN(parsed)) {
        throw new Error(`Invalid --now value: "${value}". Expected an ISO date string.`);
      }
      now = new Date(parsed);
    } else if (arg !== undefined) {
      positional.push(arg);
    }
  }

  const configPath = positional[0];
  if (!configPath) {
    throw new Error("Missing required config path argument. Usage: cli.ts <config path> [--format markdown|json] [--warning-days N] [--now ISO_DATE]");
  }

  return { configPath, format, warningDaysOverride, now };
}

/** Reads and parses a rotation config JSON file, throwing clear errors on failure. */
export async function loadConfig(configPath: string): Promise<RotationConfig> {
  const file = Bun.file(configPath);
  if (!(await file.exists())) {
    throw new Error(`Config file not found: ${configPath}`);
  }

  let parsed: unknown;
  try {
    parsed = await file.json();
  } catch (error) {
    throw new Error(`Config file "${configPath}" is not valid JSON: ${(error as Error).message}`);
  }

  return parsed as RotationConfig;
}

export interface RunResult {
  report: RotationReport;
  output: string;
  exitCode: number;
}

/** Loads the config, validates secrets, and formats the report. */
export async function runValidator(options: CliOptions, referenceDate: Date): Promise<RunResult> {
  const config = await loadConfig(options.configPath);
  if (options.warningDaysOverride !== undefined) {
    config.warningWindowDays = options.warningDaysOverride;
  }

  const report = validateSecrets(config, referenceDate);
  const output = formatReport(report, options.format);
  const exitCode = report.expired.length > 0 ? 1 : 0;

  return { report, output, exitCode };
}

if (import.meta.main) {
  try {
    const options = parseArgs(Bun.argv.slice(2));
    const result = await runValidator(options, options.now ?? new Date());
    console.log(result.output);
    process.exit(result.exitCode);
  } catch (error) {
    console.error(`Error: ${(error as Error).message}`);
    process.exit(2);
  }
}
