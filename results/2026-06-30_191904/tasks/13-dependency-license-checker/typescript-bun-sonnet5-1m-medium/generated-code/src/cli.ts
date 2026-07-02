// Orchestrates the full pipeline: read manifest -> parse -> look up licenses
// -> check against policy -> format report. Kept separate from app.ts so it
// can be unit tested without spawning a process or touching argv.

import { parseManifest } from "./parser";
import { FixtureLicenseLookup } from "./licenseLookup";
import { checkCompliance } from "./checker";
import { formatReportText, formatReportJson } from "./report";
import type { ComplianceReport, LicensePolicy } from "./types";

export interface CliOptions {
  manifestPath: string;
  policyPath: string;
  licenseDbPath: string;
  format?: "text" | "json";
}

export interface CliResult {
  report: ComplianceReport;
  output: string;
  exitCode: number;
}

async function readJson<T>(path: string, label: string): Promise<T> {
  const file = Bun.file(path);
  if (!(await file.exists())) {
    throw new Error(`Could not find ${label} at ${path}`);
  }
  try {
    return (await file.json()) as T;
  } catch (err) {
    throw new Error(`${label} at ${path} is not valid JSON (${(err as Error).message})`);
  }
}

export async function runCli(options: CliOptions): Promise<CliResult> {
  const manifestFile = Bun.file(options.manifestPath);
  if (!(await manifestFile.exists())) {
    throw new Error(`Could not find manifest at ${options.manifestPath}`);
  }
  const manifestContent = await manifestFile.text();
  const dependencies = parseManifest(options.manifestPath, manifestContent);

  const policy = await readJson<LicensePolicy>(options.policyPath, "license policy");
  const lookup = await FixtureLicenseLookup.fromFile(options.licenseDbPath);

  const report = await checkCompliance(dependencies, lookup, policy);
  const format = options.format ?? "text";
  const output = format === "json" ? formatReportJson(report) : formatReportText(report);
  const exitCode = report.summary.denied > 0 ? 1 : 0;

  return { report, output, exitCode };
}
