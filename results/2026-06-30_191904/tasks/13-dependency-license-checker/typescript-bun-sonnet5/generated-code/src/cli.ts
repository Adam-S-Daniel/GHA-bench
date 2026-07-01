import { appendFileSync } from "node:fs";
import { loadLicenseConfig } from "./config";
import { createMockLicenseLookup, loadLicenseMapFromFile } from "./licenseLookup";
import { parseManifest } from "./manifestParser";
import { formatReportMarkdown, formatReportText, generateReport } from "./report";
import { resolveManifestPath } from "./resolveManifest";

/** Default fixture locations used when no explicit paths are passed. */
const DEFAULT_MANIFEST_CANDIDATES = ["fixtures/package.json", "fixtures/requirements.txt"];
const DEFAULT_CONFIG_PATH = "fixtures/license-policy.json";
const DEFAULT_LOOKUP_PATH = "fixtures/license-data.json";

interface CliOptions {
  manifest?: string;
  config: string;
  lookup: string;
}

/** Parses `--manifest <path> --config <path> --lookup <path>` style flags. */
export function parseArgs(argv: readonly string[]): CliOptions {
  const options: CliOptions = { config: DEFAULT_CONFIG_PATH, lookup: DEFAULT_LOOKUP_PATH };

  for (let i = 0; i < argv.length; i += 1) {
    const flag = argv[i];
    const value = argv[i + 1];
    if (value === undefined) {
      throw new Error(`Missing value for flag: ${flag}`);
    }
    if (flag === "--manifest") options.manifest = value;
    else if (flag === "--config") options.config = value;
    else if (flag === "--lookup") options.lookup = value;
    else throw new Error(`Unknown flag: ${flag}`);
    i += 1;
  }

  return options;
}

async function main(): Promise<void> {
  const options = parseArgs(process.argv.slice(2));

  const manifestPath = resolveManifestPath(options.manifest, DEFAULT_MANIFEST_CANDIDATES);
  const dependencies = parseManifest(manifestPath);
  const config = loadLicenseConfig(options.config);
  const licenseMap = loadLicenseMapFromFile(options.lookup);
  const lookup = createMockLicenseLookup(licenseMap);

  const report = await generateReport(dependencies, lookup, config);

  console.log(formatReportText(report));

  const summaryPath = process.env.GITHUB_STEP_SUMMARY;
  if (summaryPath) {
    appendFileSync(summaryPath, `${formatReportMarkdown(report)}\n`);
  }
}

main().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : String(error);
  console.error(`Error: ${message}`);
  process.exit(1);
});
