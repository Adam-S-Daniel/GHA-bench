/**
 * dependency-license-checker CLI.
 *
 * Usage:
 *   bun run src/cli.ts --manifest <package.json|requirements.txt> \
 *                      --config <license-config.json> \
 *                      --licenses <licenses.json> [--strict]
 *
 * Exit codes:
 *   0 — report generated (denied entries are reported but do not fail)
 *   1 — usage / input error (missing files, malformed JSON, ...)
 *   2 — --strict was set and at least one dependency has a denied license
 */
import { checkCompliance } from "./checker";
import { loadLicenseConfig } from "./config";
import { loadFileLicenseLookup } from "./lookup";
import { parseManifest } from "./manifest";
import { formatReport } from "./report";

const USAGE = `Usage: bun run src/cli.ts --manifest <path> --config <path> --licenses <path> [--strict]

Options:
  --manifest  Dependency manifest to scan (package.json or requirements.txt)
  --config    JSON file with { "allow": [...], "deny": [...] } license lists
  --licenses  JSON license database mapping package name -> SPDX license
  --strict    Exit with code 2 if any dependency has a denied license`;

interface CliOptions {
  manifest: string;
  config: string;
  licenses: string;
  strict: boolean;
}

/** Parse argv into options, throwing meaningful errors for bad input. */
function parseArgs(argv: string[]): CliOptions {
  const values: Record<string, string> = {};
  let strict = false;

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--strict") {
      strict = true;
    } else if (arg === "--manifest" || arg === "--config" || arg === "--licenses") {
      const value = argv[++i];
      if (value === undefined || value.startsWith("--")) {
        throw new Error(`Option ${arg} requires a file path argument`);
      }
      values[arg.slice(2)] = value;
    } else {
      throw new Error(`Unknown option: ${arg}`);
    }
  }

  for (const required of ["manifest", "config", "licenses"]) {
    if (!values[required]) {
      throw new Error(`Missing required option: --${required}`);
    }
  }
  return { manifest: values.manifest, config: values.config, licenses: values.licenses, strict };
}

async function main(argv: string[]): Promise<number> {
  const options = parseArgs(argv);

  const manifestFile = Bun.file(options.manifest);
  if (!(await manifestFile.exists())) {
    throw new Error(`Manifest file not found: ${options.manifest}`);
  }

  const [config, lookup] = await Promise.all([
    loadLicenseConfig(options.config),
    loadFileLicenseLookup(options.licenses),
  ]);

  const deps = parseManifest(await manifestFile.text(), options.manifest);
  const report = await checkCompliance(deps, config, lookup);
  console.log(formatReport(report));

  if (options.strict && report.summary.denied > 0) {
    console.error(`Strict mode: ${report.summary.denied} denied license(s) found`);
    return 2;
  }
  return 0;
}

try {
  process.exit(await main(process.argv.slice(2)));
} catch (err) {
  console.error(`Error: ${(err as Error).message}`);
  console.error(USAGE);
  process.exit(1);
}
