/**
 * dependency-license-checker — core library.
 *
 * Pure, side-effect-free functions so they are trivially testable. The CLI
 * (src/app.ts) is a thin shell that reads files and wires these together.
 *
 * Pipeline:
 *   manifest text ──parse──▶ Dependency[] ──lookup+classify──▶ ComplianceReport ──format──▶ text/JSON
 *
 * The license lookup is injected (a `LicenseLookup` function) so tests can mock
 * it and CI can back it with a static JSON "license database" — no network.
 */

/** A single dependency extracted from a manifest. */
export interface Dependency {
  name: string;
  /** Normalized version (range operators stripped); "*" when unspecified. */
  version: string;
}

/** Compliance outcome for one dependency's license. */
export type LicenseStatus = "approved" | "denied" | "unknown";

/** The allow / deny configuration the report is checked against. */
export interface LicensePolicy {
  /** Licenses explicitly permitted. */
  allow: string[];
  /** Licenses explicitly forbidden (takes precedence over `allow`). */
  deny: string[];
}

/** One line of the compliance report. */
export interface ReportEntry {
  name: string;
  version: string;
  /** The resolved license id, or null when the lookup found nothing. */
  license: string | null;
  status: LicenseStatus;
}

/** The full compliance report. */
export interface ComplianceReport {
  entries: ReportEntry[];
  summary: {
    total: number;
    approved: number;
    denied: number;
    unknown: number;
  };
  /** True when no dependency uses a denied license. */
  compliant: boolean;
}

/**
 * Resolves a dependency to its license id (or null if unknown).
 * Injected so it can be mocked in tests and backed by a static file in CI —
 * the production lookup would call a registry, which we never do here.
 */
export type LicenseLookup = (dep: Dependency) => string | null;

// ---------------------------------------------------------------------------
// Manifest parsing
// ---------------------------------------------------------------------------

/**
 * Normalize a version specifier into a bare version string.
 * Strips leading range operators (^ ~ >= <= > < = v) and surrounding space.
 * Returns "*" for empty / wildcard specifiers so every dependency has a value.
 */
function normalizeVersion(raw: string): string {
  const cleaned = raw.trim().replace(/^[\^~>=<v\s]+/, "").trim();
  return cleaned === "" ? "*" : cleaned;
}

/** Parse a package.json string into a sorted, de-duplicated dependency list. */
export function parsePackageJson(content: string): Dependency[] {
  let pkg: Record<string, unknown>;
  try {
    pkg = JSON.parse(content) as Record<string, unknown>;
  } catch (err) {
    const reason = err instanceof Error ? err.message : String(err);
    throw new Error(`Invalid package.json: ${reason}`);
  }

  const sections = [
    "dependencies",
    "devDependencies",
    "peerDependencies",
    "optionalDependencies",
  ];

  // Merge sections; later sections do not override an existing name.
  const byName = new Map<string, string>();
  for (const section of sections) {
    const block = pkg[section];
    if (block && typeof block === "object" && !Array.isArray(block)) {
      for (const [name, spec] of Object.entries(block as Record<string, unknown>)) {
        if (!byName.has(name)) {
          byName.set(name, normalizeVersion(String(spec)));
        }
      }
    }
  }

  return [...byName.entries()]
    .map(([name, version]): Dependency => ({ name, version }))
    .sort((a, b) => a.name.localeCompare(b.name));
}

/** Parse a pip requirements.txt string into a sorted dependency list. */
export function parseRequirementsTxt(content: string): Dependency[] {
  const byName = new Map<string, string>();

  for (const rawLine of content.split(/\r?\n/)) {
    // Drop inline comments, then trim.
    const line = rawLine.split("#")[0]!.trim();
    if (line === "") continue;
    // Skip pip option / include lines (e.g. "-r base.txt", "--index-url ...").
    if (line.startsWith("-")) continue;

    // Split on the first version operator we encounter.
    const match = line.match(/^([A-Za-z0-9._-]+)(?:\[[^\]]*\])?\s*(==|>=|<=|~=|!=|>|<)?\s*(.*)$/);
    if (!match) continue;
    const name = match[1]!;
    const operator = match[2];
    const rest = match[3] ?? "";

    let version = "*";
    if (operator && rest.trim() !== "") {
      // Take the first constraint (before any comma) and strip operators.
      version = normalizeVersion(rest.split(",")[0]!);
    }
    if (!byName.has(name)) byName.set(name, version);
  }

  return [...byName.entries()]
    .map(([name, version]): Dependency => ({ name, version }))
    .sort((a, b) => a.name.localeCompare(b.name));
}

/**
 * Detect manifest type by filename and dispatch to the right parser.
 * `.json` files are treated as npm package.json manifests; `.txt` files as pip
 * requirements files.
 */
export function parseManifest(content: string, filename: string): Dependency[] {
  const lower = filename.toLowerCase();
  if (lower.endsWith(".json")) return parsePackageJson(content);
  if (lower.endsWith(".txt")) return parseRequirementsTxt(content);
  throw new Error(
    `Unsupported manifest type: ${filename} (expected package.json or a requirements .txt file)`,
  );
}

// ---------------------------------------------------------------------------
// License classification & report building
// ---------------------------------------------------------------------------

/**
 * Classify a single license against the policy.
 * Matching is case-insensitive. The deny-list wins over the allow-list, and
 * anything missing or unlisted is "unknown" (a flag, not a hard violation).
 */
export function classifyLicense(license: string | null, policy: LicensePolicy): LicenseStatus {
  if (license === null || license.trim() === "") return "unknown";
  const normalized = license.trim().toLowerCase();
  const denied = policy.deny.some((l) => l.toLowerCase() === normalized);
  if (denied) return "denied";
  const allowed = policy.allow.some((l) => l.toLowerCase() === normalized);
  if (allowed) return "approved";
  return "unknown";
}

/**
 * Look up + classify every dependency, then summarize.
 * The lookup is injected (mocked in tests / file-backed in CI).
 */
export function buildReport(
  deps: Dependency[],
  lookup: LicenseLookup,
  policy: LicensePolicy,
): ComplianceReport {
  const entries: ReportEntry[] = deps.map((dep) => {
    const license = lookup(dep);
    return {
      name: dep.name,
      version: dep.version,
      license,
      status: classifyLicense(license, policy),
    };
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
 * Build a `LicenseLookup` from a static map. Used by CI as the mocked license
 * database. Keys may be "name@version" (exact) or just "name" (fallback).
 */
export function createLookupFromMap(map: Record<string, string>): LicenseLookup {
  return (dep: Dependency): string | null => {
    const exact = map[`${dep.name}@${dep.version}`];
    if (exact !== undefined) return exact;
    const byName = map[dep.name];
    if (byName !== undefined) return byName;
    return null;
  };
}

/** Parse and validate a license-policy config (JSON with allow/deny arrays). */
export function loadPolicy(content: string): LicensePolicy {
  let raw: unknown;
  try {
    raw = JSON.parse(content);
  } catch (err) {
    const reason = err instanceof Error ? err.message : String(err);
    throw new Error(`Invalid policy config: ${reason}`);
  }
  if (raw === null || typeof raw !== "object") {
    throw new Error("Invalid policy config: expected a JSON object with allow/deny arrays");
  }
  const obj = raw as Record<string, unknown>;

  const coerceList = (value: unknown, field: string): string[] => {
    if (value === undefined) return [];
    if (!Array.isArray(value)) {
      throw new Error(`Invalid policy config: "${field}" must be an array of license ids`);
    }
    return value.map((v) => String(v));
  };

  return {
    allow: coerceList(obj["allow"], "allow"),
    deny: coerceList(obj["deny"], "deny"),
  };
}

// ---------------------------------------------------------------------------
// Formatting
// ---------------------------------------------------------------------------

/** Render the report as human-readable, greppable plain text. */
export function formatReportText(report: ComplianceReport): string {
  const lines: string[] = [
    "Dependency License Compliance Report",
    "====================================",
  ];
  for (const e of report.entries) {
    const license = e.license ?? "UNKNOWN";
    lines.push(`- ${e.name}@${e.version} [${e.status}] license=${license}`);
  }
  const { total, approved, denied, unknown } = report.summary;
  lines.push("");
  lines.push(`SUMMARY total=${total} approved=${approved} denied=${denied} unknown=${unknown}`);
  lines.push(`COMPLIANT=${report.compliant}`);
  return lines.join("\n");
}

/** Render the report as pretty-printed JSON. */
export function formatReportJson(report: ComplianceReport): string {
  return JSON.stringify(report, null, 2);
}

/**
 * Render the summary as `key=value` lines — directly appendable to a GitHub
 * Actions `$GITHUB_OUTPUT` file so downstream jobs can consume the result.
 */
export function formatReportKv(report: ComplianceReport): string {
  const { total, approved, denied, unknown } = report.summary;
  return [
    `total=${total}`,
    `approved=${approved}`,
    `denied=${denied}`,
    `unknown=${unknown}`,
    `compliant=${report.compliant}`,
  ].join("\n");
}
