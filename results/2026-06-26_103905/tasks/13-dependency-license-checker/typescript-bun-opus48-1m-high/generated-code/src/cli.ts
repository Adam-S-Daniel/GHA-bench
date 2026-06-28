/**
 * Command-line entry point.
 *
 * Usage:
 *   bun run src/cli.ts --manifest <file> --policy <file> --database <file>
 *                      [--format text|json]
 *
 * --manifest  path to package.json or requirements.txt (type inferred by name)
 * --policy    JSON file with { allow: [], deny: [], failOnUnknown?: bool }
 * --database  JSON file mapping "name@version" or "name" to a license id;
 *             this is the mock/offline license lookup source.
 * --format    "text" (default) human report, or "json" machine report.
 *
 * runCli() returns { output, exitCode } and never calls process.exit, so it is
 * fully unit-testable. The thin main guard at the bottom wires it to the real
 * process. Exit codes: 0 compliant, 1 non-compliant, 2 usage/IO/parse error.
 */
import { basename } from "node:path";
import { parseManifest } from "./parser.ts";
import { loadPolicy } from "./policy.ts";
import { createDatabaseLookup, loadDatabase } from "./lookup.ts";
import { formatReport, generateReport } from "./report.ts";
import type { ManifestType } from "./types.ts";

interface CliArgs {
  manifest: string;
  policy: string;
  database: string;
  format: "text" | "json";
}

const USAGE =
  "Usage: bun run src/cli.ts --manifest <file> --policy <file> --database <file> [--format text|json]";

/** A typed error carrying the desired process exit code. */
class CliError extends Error {
  constructor(message: string, readonly exitCode: number) {
    super(message);
  }
}

/** Minimal flag parser for the handful of options we accept. */
function parseArgs(argv: string[]): CliArgs {
  const opts: Record<string, string> = {};
  for (let i = 0; i < argv.length; i += 2) {
    const flag = argv[i];
    const value = argv[i + 1];
    if (!flag.startsWith("--") || value === undefined) {
      throw new CliError(USAGE, 2);
    }
    opts[flag.slice(2)] = value;
  }

  for (const required of ["manifest", "policy", "database"]) {
    if (!opts[required]) throw new CliError(USAGE, 2);
  }

  const format = opts.format ?? "text";
  if (format !== "text" && format !== "json") {
    throw new CliError(`${USAGE}\nInvalid --format: ${format}`, 2);
  }

  return {
    manifest: opts.manifest!,
    policy: opts.policy!,
    database: opts.database!,
    format,
  };
}

/** Infer the manifest type from the file name. */
function inferManifestType(path: string): ManifestType {
  const name = basename(path).toLowerCase();
  if (name === "package.json" || name.endsWith(".package.json")) {
    return "package.json";
  }
  if (name === "requirements.txt" || name.endsWith(".requirements.txt")) {
    return "requirements.txt";
  }
  throw new CliError(
    `Error: cannot infer manifest type from "${path}" (expected package.json or requirements.txt)`,
    2,
  );
}

/** Read a file, raising a labeled CliError if it cannot be read. */
async function readFileLabeled(path: string, label: string): Promise<string> {
  const file = Bun.file(path);
  if (!(await file.exists())) {
    throw new CliError(`Error: ${label} file not found: ${path}`, 2);
  }
  try {
    return await file.text();
  } catch (err) {
    const reason = err instanceof Error ? err.message : String(err);
    throw new CliError(`Error: failed to read ${label} file ${path}: ${reason}`, 2);
  }
}

/**
 * Orchestrate the whole pipeline. Returns the rendered output and an exit code
 * instead of exiting, so tests can assert on both.
 */
export async function runCli(
  argv: string[],
): Promise<{ output: string; exitCode: number }> {
  try {
    const args = parseArgs(argv);
    const type = inferManifestType(args.manifest);

    const manifestText = await readFileLabeled(args.manifest, "manifest");
    const policyText = await readFileLabeled(args.policy, "policy");
    const databaseText = await readFileLabeled(args.database, "database");

    const deps = parseManifest(manifestText, type);
    const policy = loadPolicy(policyText);
    const lookup = createDatabaseLookup(loadDatabase(databaseText));

    const report = generateReport(deps, lookup, policy);

    const output =
      args.format === "json"
        ? JSON.stringify(report, null, 2)
        : formatReport(report);

    return { output, exitCode: report.compliant ? 0 : 1 };
  } catch (err) {
    if (err instanceof CliError) {
      return { output: err.message, exitCode: err.exitCode };
    }
    const reason = err instanceof Error ? err.message : String(err);
    return { output: `Error: ${reason}`, exitCode: 2 };
  }
}

// Real process entry point. Bun sets import.meta.main for the executed file.
if (import.meta.main) {
  const { output, exitCode } = await runCli(Bun.argv.slice(2));
  console.log(output);
  process.exit(exitCode);
}
