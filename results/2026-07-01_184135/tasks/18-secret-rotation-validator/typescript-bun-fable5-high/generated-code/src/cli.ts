/**
 * secret-rotation-validator CLI.
 *
 * Usage:
 *   bun run src/cli.ts --config <file.json> [--window <days>] \
 *     [--format markdown|json] [--now YYYY-MM-DD]
 *
 * --now exists so CI runs are reproducible: the pipeline pins a reference
 * date and can assert exact output. Without it, today's date (UTC) is used.
 *
 * Exit codes: 0 on success (even if secrets are expired — reporting is the
 * job; failing the build on expired secrets is a policy choice left to the
 * workflow), 1 on any usage/config error, with the reason on stderr.
 */
import { parseConfig } from "./config";
import { OUTPUT_FORMATS, formatReport, type OutputFormat } from "./format";
import { generateReport } from "./report";

interface CliOptions {
  configPath: string;
  warningWindowDays: number;
  format: OutputFormat;
  referenceDate: string;
}

const USAGE =
  "usage: bun run src/cli.ts --config <file.json> [--window <days>] [--format markdown|json] [--now YYYY-MM-DD]";

/** Parse argv into options, throwing on anything malformed. */
export function parseArgs(argv: string[]): CliOptions {
  let configPath: string | undefined;
  let warningWindowDays = 14;
  let format: OutputFormat = "markdown";
  // Default reference date: today in UTC.
  let referenceDate = new Date().toISOString().slice(0, 10);

  for (let i = 0; i < argv.length; i++) {
    const flag = argv[i]!;
    const value = argv[i + 1];
    const require = (): string => {
      if (value === undefined) throw new Error(`option ${flag} needs a value`);
      i++;
      return value;
    };

    switch (flag) {
      case "--config":
        configPath = require();
        break;
      case "--window": {
        const raw = require();
        const days = Number(raw);
        if (!Number.isInteger(days) || days <= 0) {
          throw new Error(`--window must be a positive integer (got "${raw}")`);
        }
        warningWindowDays = days;
        break;
      }
      case "--format": {
        const raw = require();
        if (!(OUTPUT_FORMATS as readonly string[]).includes(raw)) {
          throw new Error(
            `--format must be one of: ${OUTPUT_FORMATS.join(", ")} (got "${raw}")`,
          );
        }
        format = raw as OutputFormat;
        break;
      }
      case "--now":
        referenceDate = require();
        break;
      default:
        throw new Error(`unknown option "${flag}"\n${USAGE}`);
    }
  }

  if (!configPath) {
    throw new Error(`missing required option --config\n${USAGE}`);
  }
  return { configPath, warningWindowDays, format, referenceDate };
}

/** Full pipeline: read file -> validate -> evaluate -> format. */
export async function run(argv: string[]): Promise<string> {
  const options = parseArgs(argv);

  let jsonText: string;
  try {
    jsonText = await Bun.file(options.configPath).text();
  } catch {
    throw new Error(
      `cannot read config file "${options.configPath}" (does it exist?)`,
    );
  }

  const secrets = parseConfig(jsonText);
  const report = generateReport(secrets, {
    referenceDate: options.referenceDate,
    warningWindowDays: options.warningWindowDays,
  });
  return formatReport(report, options.format);
}

// Only execute when invoked directly (bun run src/cli.ts), not when imported.
if (import.meta.main) {
  try {
    console.log(await run(Bun.argv.slice(2)));
  } catch (err) {
    console.error(`Error: ${err instanceof Error ? err.message : String(err)}`);
    process.exit(1);
  }
}
