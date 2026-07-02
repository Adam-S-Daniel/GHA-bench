import { existsSync, readFileSync } from "node:fs";
import { generateComplianceReport } from "./checker";
import { createNodeModulesLicenseLookup } from "./license-lookup";
import { parsePackageJson, parseRequirementsTxt } from "./parser";
import { formatReport } from "./report";
import type { ComplianceReport, LicenseConfig } from "./types";

/** Parses and validates a license-config JSON string into a LicenseConfig. */
export function loadLicenseConfig(content: string): LicenseConfig {
  let data: unknown;
  try {
    data = JSON.parse(content);
  } catch (err) {
    throw new Error(`Failed to parse license config: invalid JSON (${(err as Error).message})`);
  }

  const config = data as Partial<LicenseConfig>;
  if (!Array.isArray(config.allowList) || !Array.isArray(config.denyList)) {
    throw new Error("Invalid license config: expected an object with allowList[] and denyList[] arrays");
  }
  return { allowList: config.allowList, denyList: config.denyList };
}

/** Non-zero exit code whenever any dependency is on the deny-list. */
export function resolveExitCode(report: ComplianceReport): number {
  return report.summary.denied > 0 ? 1 : 0;
}

async function main(): Promise<void> {
  const manifestPath = process.argv[2];
  const configPath = process.argv[3];

  if (!manifestPath || !configPath) {
    console.error("Usage: bun run cli.ts <manifest-file> <license-config.json>");
    process.exit(2);
  }

  if (!existsSync(manifestPath)) {
    console.error(`Manifest file not found: ${manifestPath}`);
    process.exit(2);
  }
  if (!existsSync(configPath)) {
    console.error(`License config file not found: ${configPath}`);
    process.exit(2);
  }

  const manifestContent = readFileSync(manifestPath, "utf-8");
  const config = loadLicenseConfig(readFileSync(configPath, "utf-8"));

  const deps = manifestPath.endsWith(".json")
    ? parsePackageJson(manifestContent)
    : parseRequirementsTxt(manifestContent);

  const lookup = createNodeModulesLicenseLookup(process.cwd());
  const report = await generateComplianceReport(deps, config, lookup);

  console.log(formatReport(report));
  process.exit(resolveExitCode(report));
}

if (import.meta.main) {
  main().catch((err) => {
    console.error(`Error: ${(err as Error).message}`);
    process.exit(2);
  });
}
