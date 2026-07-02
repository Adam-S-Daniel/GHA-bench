/**
 * Dependency License Checker CLI.
 *
 * Usage:
 *   bun run src/cli.ts --manifest <path> --config <path> --licenses <path> [--strict]
 *
 * Reads a dependency manifest (package.json or requirements.txt), resolves
 * each dependency's license via a local JSON license database, classifies it
 * against the allow/deny config, and prints a compliance report.
 *
 * Exit codes: 0 report produced (and no denied licenses, or non-strict mode),
 *             1 denied licenses found while running with --strict,
 *             2 usage or input error.
 */
import { loadConfig } from "./config";
import { loadLicenseLookup } from "./lookup";
import { parseManifestFile } from "./parse";
import { formatReport, generateReport } from "./report";

interface CliOptions {
  manifest: string;
  config: string;
  licenses: string;
  strict: boolean;
}

const USAGE =
  "Usage: bun run src/cli.ts --manifest <path> --config <path> --licenses <path> [--strict]";

/** Parse argv into options; throws with a usage-worthy message on bad input. */
function parseArgs(argv: string[]): CliOptions {
  const opts: Partial<CliOptions> = { strict: false };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]!;
    switch (arg) {
      case "--manifest":
      case "--config":
      case "--licenses": {
        const value = argv[++i];
        if (value === undefined) throw new Error(`Missing value for ${arg}`);
        opts[arg.slice(2) as "manifest" | "config" | "licenses"] = value;
        break;
      }
      case "--strict":
        opts.strict = true;
        break;
      default:
        throw new Error(`Unknown argument: ${arg}`);
    }
  }
  if (!opts.manifest || !opts.config || !opts.licenses) {
    throw new Error("Missing required arguments --manifest, --config, --licenses");
  }
  return opts as CliOptions;
}

async function main(): Promise<number> {
  let opts: CliOptions;
  try {
    opts = parseArgs(Bun.argv.slice(2));
  } catch (err) {
    console.error(`Error: ${(err as Error).message}\n${USAGE}`);
    return 2;
  }

  try {
    const [deps, config, lookup] = await Promise.all([
      parseManifestFile(opts.manifest),
      loadConfig(opts.config),
      loadLicenseLookup(opts.licenses),
    ]);
    const report = generateReport(deps, config, lookup);
    console.log(formatReport(report));
    if (opts.strict && report.summary.denied > 0) {
      console.error(`Error: ${report.summary.denied} denied license(s) found`);
      return 1;
    }
    return 0;
  } catch (err) {
    console.error(`Error: ${(err as Error).message}`);
    return 2;
  }
}

process.exit(await main());
