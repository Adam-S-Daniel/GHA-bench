// Dependency License Checker
// ---------------------------
// Parses a dependency manifest (package.json or requirements.txt), looks up the
// license for each dependency (via an injectable, mockable lookup), checks each
// license against an allow-list / deny-list, and produces a compliance report.
//
// The module exposes a small, pure core (parse / check / report) that is trivial
// to unit-test, plus a thin CLI wrapper at the bottom that wires real files and
// process I/O to that core.

/** A single dependency extracted from a manifest. */
export interface Dependency {
  name: string;
  version: string;
}

/** Supported manifest formats. */
export type ManifestType = "package.json" | "requirements.txt";

/** Allow-list / deny-list configuration for license compliance. */
export interface LicenseConfig {
  /** SPDX license identifiers that are explicitly approved. */
  allow: string[];
  /** SPDX license identifiers that are explicitly forbidden. */
  deny: string[];
}

/** The compliance status of a single dependency's license. */
export type LicenseStatus = "approved" | "denied" | "unknown";

/** One dependency's entry in the compliance report. */
export interface DependencyReportEntry {
  name: string;
  version: string;
  /** The resolved license, or null if the lookup found none. */
  license: string | null;
  status: LicenseStatus;
}

/** A full compliance report over a set of dependencies. */
export interface ComplianceReport {
  entries: DependencyReportEntry[];
  summary: {
    total: number;
    approved: number;
    denied: number;
    unknown: number;
  };
  /** True when no dependency is denied. */
  compliant: boolean;
}

/**
 * A license lookup resolves a dependency to its license identifier (or null
 * when no license is known). Injecting this makes the report generator
 * trivially testable: tests pass a mock, CI passes a database-backed lookup,
 * and a real implementation could query a registry.
 */
export type LicenseLookup = (dep: Dependency) => string | null;

/** Output formats supported by {@link renderReport}. */
export type ReportFormat = "text" | "json";

/**
 * Detect the manifest format from a file path/name.
 *
 * A name containing "package.json" is treated as an npm manifest; any
 * "*.txt" name (e.g. requirements.txt, requirements-dev.txt) is treated as a
 * pip requirements file. Anything else throws.
 */
export function detectManifestType(filename: string): ManifestType {
  const base = filename.split(/[\\/]/).pop() ?? filename;
  if (base === "package.json") return "package.json";
  if (base.endsWith(".txt")) return "requirements.txt";
  throw new Error(
    `Unsupported manifest "${filename}". Expected package.json or a requirements*.txt file.`,
  );
}

/**
 * Classify a single license against the allow/deny configuration.
 *
 * Rules (deny wins over allow so an accidentally double-listed license is
 * treated conservatively):
 *   - missing/empty license            -> "unknown"
 *   - license on the deny-list         -> "denied"
 *   - license on the allow-list        -> "approved"
 *   - anything else                    -> "unknown"
 *
 * Matching is case-insensitive and whitespace-trimmed.
 */
export function checkLicense(
  license: string | null,
  config: LicenseConfig,
): LicenseStatus {
  if (license === null) return "unknown";
  const normalized = license.trim().toLowerCase();
  if (normalized === "") return "unknown";

  const deny = config.deny.map((l) => l.trim().toLowerCase());
  const allow = config.allow.map((l) => l.trim().toLowerCase());

  if (deny.includes(normalized)) return "denied";
  if (allow.includes(normalized)) return "approved";
  return "unknown";
}

/**
 * Build a compliance report by resolving and classifying every dependency.
 *
 * @param deps   Dependencies extracted from a manifest.
 * @param lookup Resolves each dependency to its license (mock in tests).
 * @param config Allow/deny configuration.
 */
export function generateReport(
  deps: Dependency[],
  lookup: LicenseLookup,
  config: LicenseConfig,
): ComplianceReport {
  const entries: DependencyReportEntry[] = deps.map((dep) => {
    const license = lookup(dep);
    const status = checkLicense(license, config);
    return { name: dep.name, version: dep.version, license, status };
  });

  const summary = {
    total: entries.length,
    approved: entries.filter((e) => e.status === "approved").length,
    denied: entries.filter((e) => e.status === "denied").length,
    unknown: entries.filter((e) => e.status === "unknown").length,
  };

  return { entries, summary, compliant: summary.denied === 0 };
}

/**
 * Create a {@link LicenseLookup} backed by a plain object "database". Keys may
 * be either `name` or `name@version`; the version-specific key is preferred.
 * This is the mockable lookup used by the CLI (and the CI workflow), keeping
 * the tool fully deterministic and offline.
 */
export function lookupFromDatabase(
  db: Record<string, string>,
): LicenseLookup {
  return (dep: Dependency): string | null => {
    const versioned = `${dep.name}@${dep.version}`;
    if (Object.prototype.hasOwnProperty.call(db, versioned)) return db[versioned] ?? null;
    if (Object.prototype.hasOwnProperty.call(db, dep.name)) return db[dep.name] ?? null;
    return null;
  };
}

/**
 * Render a report as human-readable text or JSON.
 *
 * The text format emits one stable, greppable line per dependency plus a
 * machine-parseable SUMMARY/RESULT footer, which the CI workflow asserts on.
 */
export function renderReport(
  report: ComplianceReport,
  format: ReportFormat,
): string {
  if (format === "json") {
    return JSON.stringify(report, null, 2);
  }

  const lines: string[] = [];
  lines.push("Dependency License Compliance Report");
  lines.push("====================================");
  for (const e of report.entries) {
    const tag = e.status.toUpperCase();
    const lic = e.license ?? "no license found";
    lines.push(`[${tag}] ${e.name}@${e.version} (${lic})`);
  }
  const { total, approved, denied, unknown } = report.summary;
  lines.push(
    `SUMMARY total=${total} approved=${approved} denied=${denied} unknown=${unknown}`,
  );
  lines.push(`RESULT ${report.compliant ? "COMPLIANT" : "NON-COMPLIANT"}`);
  return lines.join("\n");
}

// ---------------------------------------------------------------------------
// CLI layer
// ---------------------------------------------------------------------------

/** Result of a CLI invocation, captured rather than written directly so that
 * the CLI is testable without spawning subprocesses or inspecting real stdio. */
export interface CliResult {
  code: number;
  stdout: string;
  stderr: string;
}

/** Injectable I/O so tests can supply a virtual filesystem. Defaults use Bun. */
export interface CliIo {
  readText?: (path: string) => Promise<string>;
  writeText?: (path: string, data: string) => Promise<void>;
}

/** Minimal `--key value` / `--key=value` / `--flag` argument parser. */
function parseArgs(argv: string[]): Record<string, string | boolean> {
  const out: Record<string, string | boolean> = {};
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i] as string;
    if (!arg.startsWith("--")) continue;
    const body = arg.slice(2);
    const eq = body.indexOf("=");
    if (eq !== -1) {
      out[body.slice(0, eq)] = body.slice(eq + 1);
      continue;
    }
    const next = argv[i + 1];
    if (next !== undefined && !next.startsWith("--")) {
      out[body] = next;
      i++;
    } else {
      out[body] = true; // boolean flag
    }
  }
  return out;
}

const HELP_TEXT = `Dependency License Checker

Usage:
  bun run license-checker.ts --manifest <path> --config <path> --licenses <path> [options]

Required:
  --manifest <path>   package.json or requirements*.txt to scan
  --config <path>     JSON with { "allow": [...], "deny": [...] } license lists
  --licenses <path>   JSON map of "name" or "name@version" -> license id (mock DB)

Options:
  --type <t>          Force manifest type: "package.json" | "requirements.txt"
  --format <f>        Output format: "text" (default) | "json"
  --output <path>     Also write the rendered report to this file
  --strict            Exit 1 if any dependency is denied
  --fail-on-unknown   With --strict, also fail on "unknown" licenses
  --help              Show this help

Exit codes: 0 ok, 1 compliance failure (--strict), 2 usage/IO error.`;

/**
 * Run the checker as a CLI. Reads the manifest, config and (mock) license
 * database, builds the report, renders it, optionally writes it to a file, and
 * returns an exit code. All output is captured in the returned {@link CliResult}.
 */
export async function runCli(argv: string[], io: CliIo = {}): Promise<CliResult> {
  const readText = io.readText ?? ((p: string) => Bun.file(p).text());
  const writeText =
    io.writeText ?? (async (p: string, d: string) => {
      await Bun.write(p, d);
    });

  const args = parseArgs(argv);

  if (args["help"] === true) {
    return { code: 0, stdout: HELP_TEXT, stderr: "" };
  }

  // --- Validate required arguments -----------------------------------------
  const manifestPath = typeof args["manifest"] === "string" ? args["manifest"] : "";
  const configPath = typeof args["config"] === "string" ? args["config"] : "";
  const licensesPath = typeof args["licenses"] === "string" ? args["licenses"] : "";
  const missing: string[] = [];
  if (!manifestPath) missing.push("--manifest");
  if (!configPath) missing.push("--config");
  if (!licensesPath) missing.push("--licenses");
  if (missing.length > 0) {
    return {
      code: 2,
      stdout: "",
      stderr: `Error: missing required argument(s): ${missing.join(", ")}\n\n${HELP_TEXT}`,
    };
  }

  const format: ReportFormat = args["format"] === "json" ? "json" : "text";

  try {
    // --- Read inputs --------------------------------------------------------
    const manifestText = await readText(manifestPath);
    const configText = await readText(configPath);
    const licensesText = await readText(licensesPath);

    // --- Determine manifest type -------------------------------------------
    const type: ManifestType =
      args["type"] === "package.json" || args["type"] === "requirements.txt"
        ? args["type"]
        : detectManifestType(manifestPath);

    // --- Parse config + license database -----------------------------------
    const config = parseConfig(configText);
    const db = parseLicenseDatabase(licensesText);

    // --- Build the report ---------------------------------------------------
    const deps = parseManifest(manifestText, type);
    const report = generateReport(deps, lookupFromDatabase(db), config);
    const rendered = renderReport(report, format);

    if (typeof args["output"] === "string") {
      await writeText(args["output"], rendered);
    }

    // --- Decide the exit code ----------------------------------------------
    const strict = args["strict"] === true;
    const failOnUnknown = args["fail-on-unknown"] === true;
    const violated =
      report.summary.denied > 0 || (failOnUnknown && report.summary.unknown > 0);

    if (strict && violated) {
      return {
        code: 1,
        stdout: rendered,
        stderr: `Compliance check failed: report is non-compliant (denied=${report.summary.denied}, unknown=${report.summary.unknown}).`,
      };
    }
    return { code: 0, stdout: rendered, stderr: "" };
  } catch (err) {
    return {
      code: 2,
      stdout: "",
      stderr: `Error: ${(err as Error).message}`,
    };
  }
}

/** Parse and validate the allow/deny config JSON. */
function parseConfig(text: string): LicenseConfig {
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch (err) {
    throw new Error(`Failed to parse config JSON: ${(err as Error).message}`);
  }
  const obj = parsed as Record<string, unknown>;
  if (typeof obj !== "object" || obj === null) {
    throw new Error("Config must be a JSON object with 'allow' and 'deny' arrays");
  }
  const allow = obj["allow"];
  const deny = obj["deny"];
  const isStringArray = (v: unknown): v is string[] =>
    Array.isArray(v) && v.every((x) => typeof x === "string");
  if (!isStringArray(allow) || !isStringArray(deny)) {
    throw new Error("Config 'allow' and 'deny' must both be arrays of strings");
  }
  return { allow, deny };
}

/** Parse the mock license database JSON (name|name@version -> license id). */
function parseLicenseDatabase(text: string): Record<string, string> {
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch (err) {
    throw new Error(`Failed to parse licenses JSON: ${(err as Error).message}`);
  }
  if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
    throw new Error("Licenses database must be a JSON object of name -> license");
  }
  const db: Record<string, string> = {};
  for (const [key, value] of Object.entries(parsed as Record<string, unknown>)) {
    db[key] = String(value);
  }
  return db;
}

// ---------------------------------------------------------------------------
// Entrypoint: only runs when executed directly (`bun run license-checker.ts`).
// ---------------------------------------------------------------------------
if (import.meta.main) {
  const result = await runCli(Bun.argv.slice(2));
  if (result.stdout) console.log(result.stdout);
  if (result.stderr) console.error(result.stderr);
  process.exit(result.code);
}

/**
 * Parse a manifest's text content into a list of dependencies.
 *
 * @param content Raw file contents.
 * @param type    Which manifest format `content` is in.
 */
export function parseManifest(content: string, type: ManifestType): Dependency[] {
  if (type === "package.json") {
    return parsePackageJson(content);
  }
  return parseRequirementsTxt(content);
}

/**
 * Parse a package.json. Names/versions are collected from `dependencies`,
 * `devDependencies`, `peerDependencies` and `optionalDependencies` in that
 * order. The version spec is preserved verbatim (e.g. "^1.3.0").
 */
function parsePackageJson(content: string): Dependency[] {
  let parsed: unknown;
  try {
    parsed = JSON.parse(content);
  } catch (err) {
    throw new Error(
      `Failed to parse package.json: ${(err as Error).message}`,
    );
  }
  if (typeof parsed !== "object" || parsed === null) {
    throw new Error("Failed to parse package.json: expected a JSON object");
  }

  const obj = parsed as Record<string, unknown>;
  const sections = [
    "dependencies",
    "devDependencies",
    "peerDependencies",
    "optionalDependencies",
  ] as const;

  const deps: Dependency[] = [];
  const seen = new Set<string>();
  for (const section of sections) {
    const block = obj[section];
    if (typeof block !== "object" || block === null) continue;
    for (const [name, version] of Object.entries(block as Record<string, unknown>)) {
      // De-duplicate by name so a dep listed in two sections appears once.
      if (seen.has(name)) continue;
      seen.add(name);
      deps.push({ name, version: String(version) });
    }
  }
  return deps;
}

/**
 * Parse a requirements.txt (pip) file. Handles `==`, `>=`, `<=`, `~=`, `!=`,
 * `>`, `<` specifiers, extras (`requests[security]`), inline comments, blank
 * lines and full-line comments. Lines starting with options like `-r`/`-e`/`--`
 * are skipped (they reference other files, not packages).
 */
function parseRequirementsTxt(content: string): Dependency[] {
  const deps: Dependency[] = [];
  for (const rawLine of content.split(/\r?\n/)) {
    // Strip inline comments and surrounding whitespace.
    const line = rawLine.replace(/\s+#.*$/, "").trim();
    if (line === "" || line.startsWith("#")) continue;
    if (line.startsWith("-")) continue; // pip options / file references

    // Split the package token from its version specifier. The name is the
    // leading run of valid package-name characters; everything after (and
    // including) the first version operator is the version spec.
    const match = line.match(/^([A-Za-z0-9._-]+)\s*(\[[^\]]*\])?\s*(.*)$/);
    if (!match) continue;
    const name = match[1] ?? "";
    const version = (match[3] ?? "").trim();
    deps.push({ name, version });
  }
  return deps;
}
