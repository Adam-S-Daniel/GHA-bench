// CLI entry point: wire parsing -> license lookup -> report together.
import { readFileSync } from "node:fs";
import { basename } from "node:path";
import { generateReport } from "./checker.ts";
import { parseManifest } from "./parser.ts";
import { createDbLookup, formatReport, type ReportFormat } from "./report.ts";
import type { LicenseConfig, ManifestType } from "./types.ts";

interface CliArgs {
  manifest: string;
  config: string;
  db: string;
  format: ReportFormat;
}

/** Minimal `--flag value` argument parser with required-arg validation. */
function parseArgs(argv: string[]): CliArgs {
  const map = new Map<string, string>();
  for (let i = 0; i < argv.length; i += 2) {
    const flag = argv[i];
    const value = argv[i + 1];
    if (flag === undefined || !flag.startsWith("--") || value === undefined) {
      throw new Error(`Malformed arguments near "${flag ?? ""}"`);
    }
    map.set(flag.slice(2), value);
  }

  const require = (key: string): string => {
    const v = map.get(key);
    if (v === undefined) throw new Error(`Missing required argument: --${key}`);
    return v;
  };

  const format = (map.get("format") ?? "text") as ReportFormat;
  if (format !== "text" && format !== "json") {
    throw new Error(`Invalid --format "${format}" (expected text|json)`);
  }

  return {
    manifest: require("manifest"),
    config: require("config"),
    db: require("db"),
    format,
  };
}

/** Read a file, wrapping failures with a meaningful, context-rich message. */
function readFileOrThrow(path: string, label: string): string {
  try {
    return readFileSync(path, "utf8");
  } catch (err) {
    const reason = err instanceof Error ? err.message : String(err);
    throw new Error(`Cannot read ${label} at "${path}": ${reason}`);
  }
}

/** Infer the manifest type from its filename. */
function manifestTypeFor(path: string): ManifestType {
  const base = basename(path).toLowerCase();
  if (base === "package.json") return "package.json";
  if (base === "requirements.txt") return "requirements.txt";
  throw new Error(`Cannot determine manifest type from filename "${base}"`);
}

/**
 * Run the checker. Returns a process exit code: 0 when compliant,
 * 1 when any dependency is denied or unknown. `emit` receives the
 * formatted report (injected so tests can capture output).
 */
export function runCli(argv: string[], emit: (line: string) => void): number {
  const args = parseArgs(argv);

  const manifestContent = readFileOrThrow(args.manifest, "manifest");
  const configContent = readFileOrThrow(args.config, "config");
  const dbContent = readFileOrThrow(args.db, "license database");

  let config: LicenseConfig;
  try {
    config = JSON.parse(configContent) as LicenseConfig;
  } catch (err) {
    throw new Error(`Invalid config JSON: ${(err as Error).message}`);
  }
  if (!Array.isArray(config.allow) || !Array.isArray(config.deny)) {
    throw new Error('Config must contain "allow" and "deny" arrays');
  }

  let db: Record<string, string | null>;
  try {
    db = JSON.parse(dbContent) as Record<string, string | null>;
  } catch (err) {
    throw new Error(`Invalid license database JSON: ${(err as Error).message}`);
  }

  const deps = parseManifest(manifestContent, manifestTypeFor(args.manifest));
  const report = generateReport(deps, createDbLookup(db), config);

  emit(formatReport(report, args.format));

  return report.summary.compliant ? 0 : 1;
}

// When executed directly (not imported), run against real argv and exit.
if (import.meta.main) {
  try {
    const code = runCli(Bun.argv.slice(2), (line) => console.log(line));
    process.exit(code);
  } catch (err) {
    console.error(`Error: ${err instanceof Error ? err.message : String(err)}`);
    process.exit(2);
  }
}
