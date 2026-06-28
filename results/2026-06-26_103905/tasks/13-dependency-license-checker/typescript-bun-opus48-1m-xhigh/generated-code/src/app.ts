#!/usr/bin/env bun
/**
 * dependency-license-checker — CLI entry point.
 *
 * Reads a manifest, a license-policy config, and a (mocked) license database,
 * then prints a compliance report. Pure logic lives in src/lib.ts; this file is
 * just I/O, argument parsing, error handling, and exit codes.
 *
 * Usage:
 *   bun run src/app.ts --manifest <path> --config <path> \
 *       [--licenses <path>] [--format text|json] [--type <name>] \
 *       [--strict] [--fail-on-unknown]
 *
 * Exit codes:
 *   0  report generated (and compliant, or gating disabled)
 *   1  gating enabled (--strict / --fail-on-unknown) and a violation was found
 *   2  a usage or runtime error occurred (missing file, bad JSON, ...)
 */
import {
  parseManifest,
  loadPolicy,
  createLookupFromMap,
  buildReport,
  formatReportText,
  formatReportJson,
  formatReportKv,
  type LicenseLookup,
} from "./lib";

type OutputFormat = "text" | "json" | "kv";

interface CliOptions {
  manifest?: string;
  config?: string;
  licenses?: string;
  type?: string;
  format: OutputFormat;
  strict: boolean;
  failOnUnknown: boolean;
}

/** Minimal flag parser: supports "--key value" and boolean "--flag". */
export function parseArgs(argv: string[]): CliOptions {
  const opts: CliOptions = { format: "text", strict: false, failOnUnknown: false };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]!;
    switch (arg) {
      case "--manifest":
        opts.manifest = argv[++i];
        break;
      case "--config":
        opts.config = argv[++i];
        break;
      case "--licenses":
        opts.licenses = argv[++i];
        break;
      case "--type":
        opts.type = argv[++i];
        break;
      case "--format": {
        const value = argv[++i];
        if (value !== "text" && value !== "json" && value !== "kv") {
          throw new Error(`--format must be "text", "json", or "kv" (got "${value ?? ""}")`);
        }
        opts.format = value;
        break;
      }
      case "--strict":
        opts.strict = true;
        break;
      case "--fail-on-unknown":
        opts.failOnUnknown = true;
        break;
      default:
        throw new Error(`Unknown argument: ${arg}`);
    }
  }
  return opts;
}

/** Read a file, surfacing a clear error if it is missing/unreadable. */
async function readFileOrThrow(path: string, label: string): Promise<string> {
  const file = Bun.file(path);
  if (!(await file.exists())) {
    throw new Error(`${label} file not found: ${path}`);
  }
  return file.text();
}

/** Run the checker. Returns the process exit code. */
export async function main(argv: string[]): Promise<number> {
  let opts: CliOptions;
  try {
    opts = parseArgs(argv);
  } catch (err) {
    console.error(`Error: ${err instanceof Error ? err.message : String(err)}`);
    return 2;
  }

  if (!opts.manifest) {
    console.error("Error: --manifest <path> is required");
    return 2;
  }
  if (!opts.config) {
    console.error("Error: --config <path> is required");
    return 2;
  }

  try {
    // 1. Parse the manifest into a normalized dependency list.
    const manifestText = await readFileOrThrow(opts.manifest, "Manifest");
    const deps = parseManifest(manifestText, opts.type ?? opts.manifest);

    // 2. Load the allow/deny policy.
    const policy = loadPolicy(await readFileOrThrow(opts.config, "Config"));

    // 3. Build the license lookup. A JSON file acts as the mocked "registry";
    //    without one, every license resolves to unknown.
    let lookup: LicenseLookup = () => null;
    if (opts.licenses) {
      const map = JSON.parse(await readFileOrThrow(opts.licenses, "Licenses")) as Record<
        string,
        string
      >;
      lookup = createLookupFromMap(map);
    }

    // 4. Build + print the report in the requested format.
    const report = buildReport(deps, lookup, policy);
    const rendered =
      opts.format === "json"
        ? formatReportJson(report)
        : opts.format === "kv"
          ? formatReportKv(report)
          : formatReportText(report);
    console.log(rendered);

    // 5. Optional gating: turn violations into a non-zero exit code.
    if (opts.strict && !report.compliant) {
      console.error(`Compliance check FAILED: ${report.summary.denied} denied license(s).`);
      return 1;
    }
    if (opts.failOnUnknown && report.summary.unknown > 0) {
      console.error(`Compliance check FAILED: ${report.summary.unknown} unknown license(s).`);
      return 1;
    }
    return 0;
  } catch (err) {
    console.error(`Error: ${err instanceof Error ? err.message : String(err)}`);
    return 2;
  }
}

// Only execute when run directly (not when imported by a test).
if (import.meta.main) {
  process.exit(await main(Bun.argv.slice(2)));
}
