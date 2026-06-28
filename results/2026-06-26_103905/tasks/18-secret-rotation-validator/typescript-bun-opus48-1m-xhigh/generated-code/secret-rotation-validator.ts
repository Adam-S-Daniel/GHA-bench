/**
 * Secret Rotation Validator
 * =========================
 *
 * Given a configuration of secrets with metadata (name, last-rotated date,
 * rotation policy in days, required-by services), this module:
 *
 *   1. Computes each secret's rotation deadline and how many days remain.
 *   2. Classifies each secret by urgency:
 *        - "expired"  -> deadline is today or in the past (rotate now!)
 *        - "warning"  -> deadline falls within a configurable warning window
 *        - "ok"       -> deadline is comfortably in the future
 *   3. Generates a rotation report and renders it as a markdown table, JSON,
 *      or a key=value summary suitable for GitHub Actions step outputs.
 *
 * The classification is a *pure* function of (secret, now, warningWindowDays),
 * which makes it deterministic and trivially testable: tests inject a fixed
 * `now` rather than relying on the wall clock.
 *
 * This file is both an importable library (named exports used by the test
 * suite) and a CLI (see the `import.meta.main` block at the bottom).
 */

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/** Urgency buckets, ordered most-urgent first. */
export type Urgency = "expired" | "warning" | "ok";

/** Raw secret metadata as supplied in the configuration file (mock data). */
export interface SecretConfig {
  /** Human-readable secret identifier, e.g. "db-password". */
  name: string;
  /** Date the secret was last rotated, ISO `YYYY-MM-DD`. */
  lastRotated: string;
  /** How often the secret must be rotated, in whole days (> 0). */
  rotationPolicyDays: number;
  /** Services that depend on this secret (used for blast-radius context). */
  requiredBy: string[];
}

/** Options that drive classification. */
export interface ClassifyOptions {
  /** "Today", ISO `YYYY-MM-DD`. Injected for deterministic tests/CI. */
  now: string;
  /** Days before the deadline at which a secret starts warning (>= 0). */
  warningWindowDays: number;
}

/**
 * Parsed & validated configuration. `now`/`warningWindowDays` are optional here
 * because the CLI can also supply them via flags/env; whichever is resolved
 * last wins (see `resolveOptions`).
 */
export interface ValidatorConfig {
  secrets: SecretConfig[];
  now?: string;
  warningWindowDays?: number;
}

/** Tally of how many secrets fell into each urgency bucket. */
export interface ReportSummary {
  total: number;
  expired: number;
  warning: number;
  ok: number;
}

/** Full rotation report: context, per-urgency groups, and a summary tally. */
export interface RotationReport {
  /** The `now` used for evaluation, ISO `YYYY-MM-DD`. */
  now: string;
  /** The warning window used for evaluation, in days. */
  warningWindowDays: number;
  summary: ReportSummary;
  groups: Record<Urgency, SecretReport[]>;
}

/** A secret enriched with computed rotation status. */
export interface SecretReport extends SecretConfig {
  /** Rotation deadline = lastRotated + rotationPolicyDays, ISO `YYYY-MM-DD`. */
  expiryDate: string;
  /** Whole days from `now` to the deadline. Negative once overdue. */
  daysUntilExpiry: number;
  /** Urgency bucket. */
  status: Urgency;
}

// ---------------------------------------------------------------------------
// Date helpers (all math is done in UTC to avoid timezone drift)
// ---------------------------------------------------------------------------

const MS_PER_DAY = 24 * 60 * 60 * 1000;
const ISO_DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

/**
 * Parse a strict `YYYY-MM-DD` string into a UTC timestamp (ms).
 * Throws a descriptive error if the format or calendar date is invalid.
 */
export function parseIsoDate(value: string, field: string): number {
  if (typeof value !== "string" || !ISO_DATE_RE.test(value)) {
    throw new Error(
      `Invalid ${field}: expected an ISO date "YYYY-MM-DD", got ${JSON.stringify(value)}`,
    );
  }
  const [year, month, day] = value.split("-").map(Number) as [
    number,
    number,
    number,
  ];
  const ts = Date.UTC(year, month - 1, day);
  const d = new Date(ts);
  // Reject impossible dates like 2026-02-30 that Date.UTC silently rolls over.
  if (
    d.getUTCFullYear() !== year ||
    d.getUTCMonth() !== month - 1 ||
    d.getUTCDate() !== day
  ) {
    throw new Error(`Invalid ${field}: ${value} is not a real calendar date`);
  }
  return ts;
}

/** Render a UTC timestamp (ms) back to an ISO `YYYY-MM-DD` string. */
export function formatIsoDate(ts: number): string {
  return new Date(ts).toISOString().slice(0, 10);
}

// ---------------------------------------------------------------------------
// Core classification
// ---------------------------------------------------------------------------

/**
 * Enrich a single secret with its rotation deadline, days remaining, and
 * urgency status. Pure function of its inputs.
 */
export function classifySecret(
  secret: SecretConfig,
  options: ClassifyOptions,
): SecretReport {
  const lastRotatedTs = parseIsoDate(secret.lastRotated, `lastRotated for "${secret.name}"`);
  const nowTs = parseIsoDate(options.now, "now");

  const expiryTs = lastRotatedTs + secret.rotationPolicyDays * MS_PER_DAY;
  // Whole days remaining; Math.floor so "part of a day left" never rounds up
  // into a falsely-safe bucket.
  const daysUntilExpiry = Math.floor((expiryTs - nowTs) / MS_PER_DAY);

  let status: Urgency;
  if (daysUntilExpiry <= 0) {
    status = "expired"; // due today or overdue
  } else if (daysUntilExpiry <= options.warningWindowDays) {
    status = "warning"; // within the warning window
  } else {
    status = "ok"; // comfortably ahead of the deadline
  }

  return {
    ...secret,
    expiryDate: formatIsoDate(expiryTs),
    daysUntilExpiry,
    status,
  };
}

/** Urgency order used everywhere we iterate the buckets (most urgent first). */
export const URGENCY_ORDER: readonly Urgency[] = ["expired", "warning", "ok"];

/**
 * Build a full rotation report: classify every secret, group by urgency, sort
 * each group by soonest deadline first, and tally a summary.
 */
export function generateReport(
  secrets: SecretConfig[],
  options: ClassifyOptions,
): RotationReport {
  const groups: Record<Urgency, SecretReport[]> = {
    expired: [],
    warning: [],
    ok: [],
  };

  for (const secret of secrets) {
    const report = classifySecret(secret, options);
    groups[report.status].push(report);
  }

  // Within each bucket, the most urgent (fewest days remaining) comes first.
  // Ties break alphabetically by name for stable, predictable output.
  for (const urgency of URGENCY_ORDER) {
    groups[urgency].sort(
      (a, b) =>
        a.daysUntilExpiry - b.daysUntilExpiry || a.name.localeCompare(b.name),
    );
  }

  return {
    now: options.now,
    warningWindowDays: options.warningWindowDays,
    summary: {
      total: secrets.length,
      expired: groups.expired.length,
      warning: groups.warning.length,
      ok: groups.ok.length,
    },
    groups,
  };
}

// ---------------------------------------------------------------------------
// Config parsing & validation
// ---------------------------------------------------------------------------

/** Narrowing helper for "is a plain (non-array, non-null) object". */
function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/**
 * Validate one raw secret entry, returning a fully-formed `SecretConfig`.
 * Throws an `Error` with a precise message naming the offending field, so a
 * malformed fixture fails loudly rather than silently producing a bad report.
 */
function parseSecret(raw: unknown, index: number): SecretConfig {
  const where = `secrets[${index}]`;
  if (!isPlainObject(raw)) {
    throw new Error(`${where} must be an object`);
  }

  const { name, lastRotated, rotationPolicyDays, requiredBy } = raw;

  if (typeof name !== "string" || name.trim() === "") {
    throw new Error(`${where}.name must be a non-empty string`);
  }
  if (typeof lastRotated !== "string") {
    throw new Error(`${where}.lastRotated must be an ISO "YYYY-MM-DD" string`);
  }
  // parseIsoDate throws a precise message for bad formats / impossible dates.
  parseIsoDate(lastRotated, `${where}.lastRotated`);

  if (
    typeof rotationPolicyDays !== "number" ||
    !Number.isInteger(rotationPolicyDays) ||
    rotationPolicyDays <= 0
  ) {
    throw new Error(
      `${where}.rotationPolicyDays must be a positive integer (got ${JSON.stringify(rotationPolicyDays)})`,
    );
  }

  let services: string[] = [];
  if (requiredBy !== undefined) {
    if (
      !Array.isArray(requiredBy) ||
      !requiredBy.every((s) => typeof s === "string")
    ) {
      throw new Error(`${where}.requiredBy must be an array of strings`);
    }
    services = requiredBy as string[];
  }

  return { name, lastRotated, rotationPolicyDays, requiredBy: services };
}

/**
 * Parse a raw, untrusted value (typically `JSON.parse` output) into a validated
 * `ValidatorConfig`. Accepts either `{ secrets: [...], now?, warningWindowDays? }`
 * or a bare `[...]` array of secrets as shorthand.
 */
export function parseConfig(raw: unknown): ValidatorConfig {
  let secretsRaw: unknown;
  let now: string | undefined;
  let warningWindowDays: number | undefined;

  if (Array.isArray(raw)) {
    secretsRaw = raw;
  } else if (isPlainObject(raw)) {
    secretsRaw = raw.secrets;
    if (raw.now !== undefined) {
      if (typeof raw.now !== "string") {
        throw new Error(`config.now must be an ISO "YYYY-MM-DD" string`);
      }
      parseIsoDate(raw.now, "config.now");
      now = raw.now;
    }
    if (raw.warningWindowDays !== undefined) {
      if (
        typeof raw.warningWindowDays !== "number" ||
        !Number.isInteger(raw.warningWindowDays) ||
        raw.warningWindowDays < 0
      ) {
        throw new Error(
          `config.warningWindowDays must be a non-negative integer`,
        );
      }
      warningWindowDays = raw.warningWindowDays;
    }
  } else {
    throw new Error(
      "Configuration must be a JSON object or array of secrets",
    );
  }

  if (!Array.isArray(secretsRaw)) {
    throw new Error(
      'Configuration must contain a "secrets" array (or be an array of secrets)',
    );
  }

  const secrets = secretsRaw.map((s, i) => parseSecret(s, i));

  // Guard against duplicate names, which would make notifications ambiguous.
  const seen = new Set<string>();
  for (const s of secrets) {
    if (seen.has(s.name)) {
      throw new Error(`Duplicate secret name "${s.name}" in configuration`);
    }
    seen.add(s.name);
  }

  return { secrets, now, warningWindowDays };
}

// ---------------------------------------------------------------------------
// Output formatters
// ---------------------------------------------------------------------------

/** Supported output formats for the rotation report. */
export type OutputFormat = "markdown" | "json" | "github";

/** Human-friendly labels for each urgency bucket. */
const URGENCY_LABEL: Record<Urgency, string> = {
  expired: "EXPIRED",
  warning: "WARNING",
  ok: "OK",
};

/** Iterate every classified secret in urgency order (expired -> warning -> ok). */
function allSecretsInOrder(report: RotationReport): SecretReport[] {
  return URGENCY_ORDER.flatMap((u) => report.groups[u]);
}

/** Render the report as pretty-printed JSON. */
export function renderJson(report: RotationReport): string {
  return JSON.stringify(report, null, 2);
}

/** Escape a value so it cannot break out of a markdown table cell. */
function mdCell(value: string): string {
  return value.replace(/\|/g, "\\|").replace(/\n/g, " ");
}

/** Render the report as a GitHub-flavoured markdown document with a table. */
export function renderMarkdown(report: RotationReport): string {
  const { summary } = report;
  const lines: string[] = [];

  lines.push("# Secret Rotation Report");
  lines.push("");
  lines.push(`_Evaluated as of **${report.now}** with a **${report.warningWindowDays}-day** warning window._`);
  lines.push("");
  lines.push(
    `**Total:** ${summary.total} &nbsp;|&nbsp; ` +
      `**Expired:** ${summary.expired} &nbsp;|&nbsp; ` +
      `**Warning:** ${summary.warning} &nbsp;|&nbsp; ` +
      `**OK:** ${summary.ok}`,
  );
  lines.push("");
  lines.push("| Secret | Status | Last Rotated | Policy (days) | Expiry | Days Left | Required By |");
  lines.push("| --- | --- | --- | --- | ---: | ---: | --- |");

  if (summary.total === 0) {
    lines.push("| _(no secrets configured)_ |  |  |  |  |  |  |");
  } else {
    for (const s of allSecretsInOrder(report)) {
      lines.push(
        `| ${mdCell(s.name)} | ${s.status} | ${s.lastRotated} | ` +
          `${s.rotationPolicyDays} | ${s.expiryDate} | ${s.daysUntilExpiry} | ` +
          `${mdCell(s.requiredBy.join(", "))} |`,
      );
    }
  }

  lines.push("");
  return lines.join("\n");
}

/**
 * Render key=value lines for GitHub Actions step outputs (`>> $GITHUB_OUTPUT`).
 * Names are comma-joined onto a single line so no multiline delimiter is needed.
 */
export function renderGithubOutput(report: RotationReport): string {
  const { summary, groups } = report;
  const names = (u: Urgency): string => groups[u].map((s) => s.name).join(",");
  const lines = [
    `total=${summary.total}`,
    `expired_count=${summary.expired}`,
    `warning_count=${summary.warning}`,
    `ok_count=${summary.ok}`,
    `expired_names=${names("expired")}`,
    `warning_names=${names("warning")}`,
    `ok_names=${names("ok")}`,
  ];
  return lines.join("\n") + "\n";
}

/**
 * Render plain-text notifications grouped by urgency. This is the
 * "output notifications grouped by urgency" deliverable, suitable for piping to
 * chat/email or printing in a CI log.
 */
export function renderNotifications(report: RotationReport): string {
  const lines: string[] = [];
  lines.push("=== Secret Rotation Notifications ===");
  lines.push(`As of ${report.now} (warning window: ${report.warningWindowDays} days)`);

  for (const urgency of URGENCY_ORDER) {
    const bucket = report.groups[urgency];
    lines.push("");
    lines.push(`${URGENCY_LABEL[urgency]} (${bucket.length}):`);
    if (bucket.length === 0) {
      lines.push("  (none)");
      continue;
    }
    for (const s of bucket) {
      const dependents = s.requiredBy.length ? s.requiredBy.join(", ") : "no listed services";
      const when =
        s.daysUntilExpiry < 0
          ? `overdue by ${Math.abs(s.daysUntilExpiry)} day(s)`
          : s.daysUntilExpiry === 0
            ? "due today"
            : `due in ${s.daysUntilExpiry} day(s)`;
      lines.push(`  - ${s.name}: ${when} (expiry ${s.expiryDate}); required by ${dependents}`);
    }
  }
  return lines.join("\n");
}

/** Dispatch to the requested formatter. Throws on an unsupported format. */
export function formatReport(report: RotationReport, format: OutputFormat): string {
  switch (format) {
    case "json":
      return renderJson(report);
    case "markdown":
      return renderMarkdown(report);
    case "github":
      return renderGithubOutput(report);
    default:
      // Exhaustiveness guard: also catches bad runtime values from the CLI.
      throw new Error(
        `Unknown output format: ${JSON.stringify(format)} (expected "markdown", "json" or "github")`,
      );
  }
}

// ---------------------------------------------------------------------------
// CI gating
// ---------------------------------------------------------------------------

/** Threshold at which the validator should signal failure via its exit code. */
export type FailOn = "none" | "warning" | "expired";

/**
 * Map a report + fail-on threshold to a process exit code.
 *   - "none":    always 0 (report-only mode)
 *   - "expired": 1 if any secret is expired
 *   - "warning": 1 if any secret is expired OR within the warning window
 */
export function resolveExitCode(report: RotationReport, failOn: FailOn): number {
  switch (failOn) {
    case "none":
      return 0;
    case "expired":
      return report.summary.expired > 0 ? 1 : 0;
    case "warning":
      return report.summary.expired + report.summary.warning > 0 ? 1 : 0;
    default:
      throw new Error(
        `Unknown fail-on value: ${JSON.stringify(failOn)} (expected "none", "warning" or "expired")`,
      );
  }
}

// ---------------------------------------------------------------------------
// CLI argument parsing
// ---------------------------------------------------------------------------

/** Flags recognised on the command line (all optional). */
export interface CliArgs {
  config?: string;
  format?: OutputFormat;
  warningWindowDays?: number;
  now?: string;
  failOn?: FailOn;
  notify?: boolean;
  help?: boolean;
}

const VALID_FORMATS: readonly OutputFormat[] = ["markdown", "json", "github"];
const VALID_FAIL_ON: readonly FailOn[] = ["none", "warning", "expired"];

function asFormat(value: string): OutputFormat {
  if ((VALID_FORMATS as readonly string[]).includes(value)) {
    return value as OutputFormat;
  }
  throw new Error(`Invalid --format "${value}" (expected one of: ${VALID_FORMATS.join(", ")})`);
}

function asFailOn(value: string): FailOn {
  if ((VALID_FAIL_ON as readonly string[]).includes(value)) {
    return value as FailOn;
  }
  throw new Error(`Invalid --fail-on "${value}" (expected one of: ${VALID_FAIL_ON.join(", ")})`);
}

function asWarningDays(value: string): number {
  const n = Number(value);
  if (!Number.isInteger(n) || n < 0) {
    throw new Error(`Invalid --warning-days "${value}" (expected a non-negative integer)`);
  }
  return n;
}

/**
 * Parse `argv` (excluding `node`/script path) into a `CliArgs`. Supports
 * `--flag value`, `--flag=value`, and short aliases `-c/-f/-w/-h`. Throws an
 * `Error` with a precise message for unknown flags or missing values.
 */
export function parseArgs(argv: string[]): CliArgs {
  const args: CliArgs = {};

  // Read the value for a flag, handling both "--flag value" and "--flag=value".
  for (let i = 0; i < argv.length; i++) {
    const token = argv[i]!;
    let key = token;
    let inlineValue: string | undefined;

    const eq = token.indexOf("=");
    if (token.startsWith("--") && eq !== -1) {
      key = token.slice(0, eq);
      inlineValue = token.slice(eq + 1);
    }

    // Pull the next token as this flag's value (errors if absent).
    const takeValue = (flag: string): string => {
      if (inlineValue !== undefined) return inlineValue;
      const next = argv[i + 1];
      if (next === undefined) {
        throw new Error(`Flag ${flag} requires a value`);
      }
      i++;
      return next;
    };

    switch (key) {
      case "--config":
      case "-c":
        args.config = takeValue(key);
        break;
      case "--format":
      case "-f":
        args.format = asFormat(takeValue(key));
        break;
      case "--warning-days":
      case "-w":
        args.warningWindowDays = asWarningDays(takeValue(key));
        break;
      case "--now":
        args.now = takeValue(key);
        break;
      case "--fail-on":
        args.failOn = asFailOn(takeValue(key));
        break;
      case "--notify":
        args.notify = true;
        break;
      case "--help":
      case "-h":
        args.help = true;
        break;
      default:
        throw new Error(`Unknown flag: ${token}`);
    }
  }

  return args;
}

// ---------------------------------------------------------------------------
// Option resolution (precedence: CLI flag > env var > config file > default)
// ---------------------------------------------------------------------------

/** Fully-resolved runtime options after merging all sources. */
export interface ResolvedOptions {
  now: string;
  warningWindowDays: number;
  format: OutputFormat;
  failOn: FailOn;
  notify: boolean;
}

const DEFAULT_WARNING_WINDOW_DAYS = 14;

/** Environment variable names understood by the CLI. */
export const ENV = {
  config: "SECRET_ROTATION_CONFIG",
  now: "SECRET_ROTATION_NOW",
  warningDays: "SECRET_ROTATION_WARNING_DAYS",
  format: "SECRET_ROTATION_FORMAT",
  failOn: "SECRET_ROTATION_FAIL_ON",
  notify: "SECRET_ROTATION_NOTIFY",
} as const;

type Env = Record<string, string | undefined>;

/**
 * Merge CLI args, environment variables, config-file defaults and built-in
 * defaults into a single resolved options object. `today` is the system date
 * (ISO `YYYY-MM-DD`), passed in so this function stays pure and testable.
 */
export function resolveOptions(
  args: CliArgs,
  config: ValidatorConfig,
  env: Env,
  today: string,
): ResolvedOptions {
  // Read env vars into locals so TypeScript can narrow them after the
  // `!== undefined` guards (index-access expressions don't narrow on re-read).
  const envNow = env[ENV.now];
  const envWarningDays = env[ENV.warningDays];
  const envFormat = env[ENV.format];
  const envFailOn = env[ENV.failOn];

  const now = args.now ?? envNow ?? config.now ?? today;
  // Validate the resolved `now` eagerly for a clear early error.
  parseIsoDate(now, "now");

  const warningWindowDays =
    args.warningWindowDays ??
    (envWarningDays !== undefined ? asWarningDays(envWarningDays) : undefined) ??
    config.warningWindowDays ??
    DEFAULT_WARNING_WINDOW_DAYS;

  const format =
    args.format ??
    (envFormat !== undefined ? asFormat(envFormat) : undefined) ??
    "markdown";

  const failOn =
    args.failOn ??
    (envFailOn !== undefined ? asFailOn(envFailOn) : undefined) ??
    "none";

  const notify = args.notify ?? isTruthy(env[ENV.notify]) ?? false;

  return { now, warningWindowDays, format, failOn, notify };
}

/** Interpret a string env var as a boolean (undefined stays undefined). */
function isTruthy(value: string | undefined): boolean | undefined {
  if (value === undefined) return undefined;
  return ["1", "true", "yes", "on"].includes(value.toLowerCase());
}

// ---------------------------------------------------------------------------
// CLI runner (pure-ish: returns a result instead of touching process.*)
// ---------------------------------------------------------------------------

/** Result of running the CLI: captured output streams + intended exit code. */
export interface CliResult {
  stdout: string;
  stderr: string;
  exitCode: number;
}

const USAGE = `Secret Rotation Validator

Identify expired / expiring secrets from a config file and report them grouped
by urgency (expired, warning, ok).

Usage:
  bun run secret-rotation-validator.ts --config <path> [options]

Options:
  -c, --config <path>     Path to the secrets JSON config (required).
  -f, --format <fmt>      Output format: markdown | json | github (default: markdown).
  -w, --warning-days <n>  Warning window in days (default: config value or 14).
      --now <YYYY-MM-DD>  Evaluation date (default: config value or today).
      --fail-on <level>   Exit non-zero if findings reach: none | warning | expired
                          (default: none).
      --notify            Also print urgency-grouped notifications to stderr.
  -h, --help              Show this help.

Environment variables (override config, overridden by flags):
  SECRET_ROTATION_CONFIG, SECRET_ROTATION_NOW, SECRET_ROTATION_WARNING_DAYS,
  SECRET_ROTATION_FORMAT, SECRET_ROTATION_FAIL_ON, SECRET_ROTATION_NOTIFY

Exit codes:
  0  success (or findings below --fail-on threshold)
  1  findings reached the --fail-on threshold
  2  usage / configuration / I/O error
`;

/**
 * Run the validator CLI. Returns captured stdout/stderr and an exit code rather
 * than writing to the console or calling `process.exit`, so it is fully
 * testable. The thin `main()` wrapper below performs the real side effects.
 *
 * @param argv  CLI arguments (excluding runtime + script path).
 * @param env   Environment map (inject for tests; pass `process.env` in main).
 * @param today System date as ISO `YYYY-MM-DD` (inject for determinism).
 */
export async function runCli(
  argv: string[],
  env: Env,
  today: string,
): Promise<CliResult> {
  let args: CliArgs;
  try {
    args = parseArgs(argv);
  } catch (err) {
    return { stdout: "", stderr: `Error: ${errMessage(err)}\n\n${USAGE}`, exitCode: 2 };
  }

  if (args.help) {
    return { stdout: USAGE, stderr: "", exitCode: 0 };
  }

  // Resolve the config path (flag > env). Required.
  const configPath = args.config ?? env[ENV.config];
  if (!configPath) {
    return {
      stdout: "",
      stderr: `Error: no config provided. Pass --config <path> or set ${ENV.config}.\n\n${USAGE}`,
      exitCode: 2,
    };
  }

  // Read + parse the config file with friendly errors for each failure mode.
  let parsed: ValidatorConfig;
  try {
    const file = Bun.file(configPath);
    if (!(await file.exists())) {
      throw new Error(`config file not found: ${configPath}`);
    }
    let raw: unknown;
    try {
      raw = JSON.parse(await file.text());
    } catch (jsonErr) {
      throw new Error(`config file is not valid JSON (${configPath}): ${errMessage(jsonErr)}`);
    }
    parsed = parseConfig(raw);
  } catch (err) {
    return { stdout: "", stderr: `Error: ${errMessage(err)}`, exitCode: 2 };
  }

  // Resolve all runtime options and build the report.
  let options: ResolvedOptions;
  let report: RotationReport;
  try {
    options = resolveOptions(args, parsed, env, today);
    report = generateReport(parsed.secrets, {
      now: options.now,
      warningWindowDays: options.warningWindowDays,
    });
  } catch (err) {
    return { stdout: "", stderr: `Error: ${errMessage(err)}`, exitCode: 2 };
  }

  // Primary output goes to stdout in the requested format.
  const stdout = formatReport(report, options.format);

  // A one-line machine-readable summary (+ optional notifications) on stderr,
  // so it never pollutes the parseable stdout payload.
  const stderrParts: string[] = [
    `secret-rotation-validator: total=${report.summary.total} ` +
      `expired=${report.summary.expired} warning=${report.summary.warning} ok=${report.summary.ok} ` +
      `(now=${report.now}, warningWindow=${report.warningWindowDays}d)`,
  ];
  if (options.notify) {
    stderrParts.push(renderNotifications(report));
  }

  const exitCode = resolveExitCode(report, options.failOn);
  return { stdout, stderr: stderrParts.join("\n"), exitCode };
}

/** Extract a human-readable message from an unknown thrown value. */
function errMessage(err: unknown): string {
  return err instanceof Error ? err.message : String(err);
}

// ---------------------------------------------------------------------------
// Entrypoint
// ---------------------------------------------------------------------------

/** Thin wrapper that wires `runCli` to the real process. */
async function main(): Promise<void> {
  const today = new Date().toISOString().slice(0, 10);
  const result = await runCli(Bun.argv.slice(2), process.env, today);
  if (result.stdout) process.stdout.write(result.stdout.endsWith("\n") ? result.stdout : result.stdout + "\n");
  if (result.stderr) process.stderr.write(result.stderr + "\n");
  process.exit(result.exitCode);
}

// Only run the CLI when executed directly (not when imported by tests).
if (import.meta.main) {
  await main();
}
