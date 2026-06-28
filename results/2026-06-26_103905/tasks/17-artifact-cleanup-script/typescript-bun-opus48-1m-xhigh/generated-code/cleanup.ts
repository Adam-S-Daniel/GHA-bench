/**
 * Artifact Cleanup Script (TypeScript / Bun)
 * ==========================================
 *
 * Given a list of CI artifacts with metadata, applies a set of retention
 * policies, decides which artifacts to delete, and produces a deletion plan
 * plus a summary (space reclaimed, retained-vs-deleted counts).
 *
 * Supported retention policies (any combination may be active at once):
 *   - maxAgeDays              delete artifacts older than N days
 *   - keepLatestNPerWorkflow  per workflow, keep only the N most-recent artifacts
 *   - maxTotalSizeBytes       cap total retained size; evict oldest-first to fit
 *
 * Design notes / how the policies combine
 * ----------------------------------------
 * Each artifact accumulates a set of *reasons* explaining why it is deleted.
 * The three policies are applied in a fixed, documented order so the result is
 * fully deterministic (important: the GitHub Actions pipeline asserts on exact
 * numbers):
 *
 *   1. max-age           — flag every artifact older than the cutoff.
 *   2. keep-latest-n     — within each workflow group, flag everything past the
 *                          N newest artifacts.
 *   3. max-total-size    — of the artifacts that *survived* rules 1 & 2, if their
 *                          combined size still exceeds the cap, evict oldest-first
 *                          until the retained set fits under the cap.
 *
 * `now` is injectable via PlanOptions so age calculations are testable and
 * reproducible. This module is both a library (exported functions) and a CLI
 * (`bun run cleanup.ts ...`).
 */

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/** Metadata describing a single stored artifact. */
export interface Artifact {
  /** Unique artifact identifier. */
  id: string;
  /** Human-readable artifact name. */
  name: string;
  /** Size of the artifact in bytes. */
  sizeBytes: number;
  /** ISO-8601 creation timestamp. */
  createdAt: string;
  /** Identifier of the workflow run that produced the artifact. */
  workflowRunId: string;
  /**
   * Optional logical workflow name. Used as the grouping key for the
   * keep-latest-N-per-workflow policy. When absent, the workflowRunId is used
   * as the grouping key instead.
   */
  workflowName?: string;
}

/** Retention rules. Every field is optional; omitted rules are not applied. */
export interface RetentionPolicy {
  /** Delete artifacts strictly older than this many days. */
  maxAgeDays?: number;
  /** Maximum total size (bytes) of the *retained* set. */
  maxTotalSizeBytes?: number;
  /** Keep only the N most-recent artifacts per workflow. */
  keepLatestNPerWorkflow?: number;
}

/** Per-run options that influence planning but are not retention rules. */
export interface PlanOptions {
  /** When true, the plan is informational only (no deletion performed). */
  dryRun?: boolean;
  /** Reference "current time"; defaults to the real wall clock. */
  now?: Date;
}

/** Why a given artifact was selected for deletion. */
export type DeletionReason = "max-age" | "keep-latest-n" | "max-total-size";

/** A single artifact slated for deletion, with its reason(s). */
export interface DeletionEntry {
  artifact: Artifact;
  reasons: DeletionReason[];
}

/** Aggregate numbers describing the plan. */
export interface CleanupSummary {
  totalArtifacts: number;
  retainedCount: number;
  deletedCount: number;
  /** Total size of *all* artifacts before cleanup. */
  totalSizeBytes: number;
  /** Total size of artifacts to be deleted (space reclaimed). */
  spaceReclaimedBytes: number;
  /** Total size of artifacts to be retained. */
  retainedSizeBytes: number;
}

/** The full deletion plan returned by {@link planCleanup}. */
export interface DeletionPlan {
  dryRun: boolean;
  toDelete: DeletionEntry[];
  toRetain: Artifact[];
  summary: CleanupSummary;
}

const MS_PER_DAY = 24 * 60 * 60 * 1000;

// ---------------------------------------------------------------------------
// Validation helpers
// ---------------------------------------------------------------------------

/**
 * Validate the artifact list, throwing a descriptive Error on the first
 * problem. Validating up-front means the planner can assume clean data.
 */
function validateArtifacts(artifacts: Artifact[]): void {
  if (!Array.isArray(artifacts)) {
    throw new Error("artifacts must be an array");
  }
  const seen = new Set<string>();
  artifacts.forEach((a, i) => {
    const where = `artifacts[${i}]`;
    if (typeof a !== "object" || a === null) {
      throw new Error(`${where} must be an object`);
    }
    if (typeof a.id !== "string" || a.id.length === 0) {
      throw new Error(`${where}.id must be a non-empty string`);
    }
    if (seen.has(a.id)) {
      throw new Error(`duplicate artifact id "${a.id}" at ${where}`);
    }
    seen.add(a.id);
    if (typeof a.name !== "string") {
      throw new Error(`${where} (id="${a.id}").name must be a string`);
    }
    if (typeof a.sizeBytes !== "number" || !Number.isFinite(a.sizeBytes) || a.sizeBytes < 0) {
      throw new Error(`${where} (id="${a.id}").sizeBytes must be a non-negative number`);
    }
    if (typeof a.workflowRunId !== "string" || a.workflowRunId.length === 0) {
      throw new Error(`${where} (id="${a.id}").workflowRunId must be a non-empty string`);
    }
    if (Number.isNaN(Date.parse(a.createdAt))) {
      throw new Error(`${where} (id="${a.id}").createdAt is not a valid date: "${a.createdAt}"`);
    }
  });
}

/** Validate a single optional non-negative integer policy field. */
function validateNonNegativeInt(value: number | undefined, label: string): void {
  if (value === undefined) return;
  if (typeof value !== "number" || !Number.isFinite(value) || value < 0 || !Number.isInteger(value)) {
    throw new Error(`${label} must be a non-negative integer`);
  }
}

function validatePolicy(policy: RetentionPolicy): void {
  if (typeof policy !== "object" || policy === null) {
    throw new Error("policy must be an object");
  }
  validateNonNegativeInt(policy.maxAgeDays, "policy.maxAgeDays");
  validateNonNegativeInt(policy.maxTotalSizeBytes, "policy.maxTotalSizeBytes");
  validateNonNegativeInt(policy.keepLatestNPerWorkflow, "policy.keepLatestNPerWorkflow");
}

// ---------------------------------------------------------------------------
// Sorting helpers (kept explicit so ordering is deterministic & documented)
// ---------------------------------------------------------------------------

/** Epoch millis for an artifact's creation time. */
function createdMs(a: Artifact): number {
  return Date.parse(a.createdAt);
}

/** The grouping key for keep-latest-N: workflow name if present, else run id. */
function workflowKey(a: Artifact): string {
  return a.workflowName ?? a.workflowRunId;
}

/**
 * Newest-first ordering. Ties on timestamp are broken by id (descending) so the
 * notion of "the latest N" is stable across runs.
 */
function byNewestFirst(x: Artifact, y: Artifact): number {
  const d = createdMs(y) - createdMs(x);
  if (d !== 0) return d;
  return x.id < y.id ? 1 : x.id > y.id ? -1 : 0;
}

/**
 * Oldest-first ordering. Ties on timestamp are broken by id (ascending) so the
 * eviction order for the size cap is stable across runs.
 */
function byOldestFirst(x: Artifact, y: Artifact): number {
  const d = createdMs(x) - createdMs(y);
  if (d !== 0) return d;
  return x.id < y.id ? -1 : x.id > y.id ? 1 : 0;
}

// ---------------------------------------------------------------------------
// Core planner
// ---------------------------------------------------------------------------

/**
 * Build a deletion plan for `artifacts` under `policy`.
 *
 * Pure function: it never mutates its inputs and performs no I/O, which makes
 * it trivial to unit-test. The caller decides what to do with the plan
 * (print it, call an API, etc.).
 */
export function planCleanup(
  artifacts: Artifact[],
  policy: RetentionPolicy,
  options: PlanOptions = {},
): DeletionPlan {
  validateArtifacts(artifacts);
  validatePolicy(policy);

  const now = options.now ?? new Date();
  if (Number.isNaN(now.getTime())) {
    throw new Error("options.now is not a valid Date");
  }
  const dryRun = options.dryRun ?? false;

  // Accumulate deletion reasons per artifact id. A LinkedHashSet-like ordering
  // is achieved by inserting reasons in policy-application order.
  const reasons = new Map<string, Set<DeletionReason>>();
  const addReason = (id: string, reason: DeletionReason): void => {
    let set = reasons.get(id);
    if (!set) {
      set = new Set<DeletionReason>();
      reasons.set(id, set);
    }
    set.add(reason);
  };

  // --- Rule 1: max age -----------------------------------------------------
  if (policy.maxAgeDays !== undefined) {
    const cutoffMs = now.getTime() - policy.maxAgeDays * MS_PER_DAY;
    for (const a of artifacts) {
      if (createdMs(a) < cutoffMs) addReason(a.id, "max-age");
    }
  }

  // --- Rule 2: keep latest N per workflow ----------------------------------
  if (policy.keepLatestNPerWorkflow !== undefined) {
    const groups = new Map<string, Artifact[]>();
    for (const a of artifacts) {
      const key = workflowKey(a);
      const list = groups.get(key);
      if (list) list.push(a);
      else groups.set(key, [a]);
    }
    for (const group of groups.values()) {
      const ordered = [...group].sort(byNewestFirst);
      // Everything past the N newest is flagged.
      for (const a of ordered.slice(policy.keepLatestNPerWorkflow)) {
        addReason(a.id, "keep-latest-n");
      }
    }
  }

  // --- Rule 3: max total size (evict oldest survivors first) ---------------
  if (policy.maxTotalSizeBytes !== undefined) {
    // Survivors = artifacts not yet flagged by rules 1 & 2.
    const survivors = artifacts.filter((a) => !reasons.has(a.id));
    let retainedSize = survivors.reduce((sum, a) => sum + a.sizeBytes, 0);
    if (retainedSize > policy.maxTotalSizeBytes) {
      for (const a of [...survivors].sort(byOldestFirst)) {
        if (retainedSize <= policy.maxTotalSizeBytes) break;
        addReason(a.id, "max-total-size");
        retainedSize -= a.sizeBytes;
      }
    }
  }

  // --- Assemble plan (preserve input order in the outputs) -----------------
  const toDelete: DeletionEntry[] = [];
  const toRetain: Artifact[] = [];
  for (const a of artifacts) {
    const set = reasons.get(a.id);
    if (set && set.size > 0) {
      toDelete.push({ artifact: a, reasons: [...set] });
    } else {
      toRetain.push(a);
    }
  }

  const totalSizeBytes = artifacts.reduce((s, a) => s + a.sizeBytes, 0);
  const spaceReclaimedBytes = toDelete.reduce((s, d) => s + d.artifact.sizeBytes, 0);
  const retainedSizeBytes = totalSizeBytes - spaceReclaimedBytes;

  const summary: CleanupSummary = {
    totalArtifacts: artifacts.length,
    retainedCount: toRetain.length,
    deletedCount: toDelete.length,
    totalSizeBytes,
    spaceReclaimedBytes,
    retainedSizeBytes,
  };

  return { dryRun, toDelete, toRetain, summary };
}

// ===========================================================================
// CLI layer
// ===========================================================================
//
// The script doubles as a command-line tool. The simplest way to drive it is a
// self-contained "scenario" file passed with --config:
//
//   {
//     "now": "2026-06-28T00:00:00Z",
//     "dryRun": true,
//     "policy": { "maxAgeDays": 60, "maxTotalSizeBytes": 5000, "keepLatestNPerWorkflow": 3 },
//     "artifacts": [ { "id": "...", "name": "...", "sizeBytes": 0, "createdAt": "...", "workflowRunId": "..." } ]
//   }
//
// Individual --flags override fields loaded from the scenario file, so the same
// fixture can be reused with different policies.

/** A scenario bundles the artifacts together with the policy/options. */
export interface Scenario {
  now?: string;
  dryRun?: boolean;
  policy?: RetentionPolicy;
  artifacts: Artifact[];
}

interface CliConfig {
  artifacts: Artifact[];
  policy: RetentionPolicy;
  options: PlanOptions;
  output?: string;
  format: "text" | "json";
}

/** Format a byte count as a short human-readable string (for the summary). */
export function humanSize(bytes: number): string {
  const units = ["B", "KiB", "MiB", "GiB", "TiB"];
  let value = bytes;
  let unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  const rounded = unit === 0 ? value : Math.round(value * 100) / 100;
  return `${rounded} ${units[unit]}`;
}

/** Render the deletion plan as deterministic, assertion-friendly plain text. */
export function formatPlanText(plan: DeletionPlan): string {
  const s = plan.summary;
  const lines: string[] = [
    "=== Artifact Cleanup Plan ===",
    `Mode: ${plan.dryRun ? "dry-run" : "live"}`,
    `Total artifacts: ${s.totalArtifacts}`,
    `Retained count: ${s.retainedCount}`,
    `Deleted count: ${s.deletedCount}`,
    `Total size bytes: ${s.totalSizeBytes}`,
    `Space reclaimed bytes: ${s.spaceReclaimedBytes}`,
    `Retained size bytes: ${s.retainedSizeBytes}`,
    `Space reclaimed human: ${humanSize(s.spaceReclaimedBytes)}`,
    "",
    `Artifacts to delete (${plan.toDelete.length}):`,
  ];
  for (const d of plan.toDelete) {
    lines.push(
      `  - ${d.artifact.id} | ${d.artifact.name} | ${d.artifact.sizeBytes} bytes | ${d.artifact.createdAt} | reasons: ${d.reasons.join(",")}`,
    );
  }
  lines.push("", `Artifacts to retain (${plan.toRetain.length}):`);
  for (const a of plan.toRetain) {
    lines.push(`  - ${a.id} | ${a.name} | ${a.sizeBytes} bytes | ${a.createdAt}`);
  }
  lines.push("=== End Artifact Cleanup Plan ===");
  return lines.join("\n");
}

/** Render the plan as a Markdown summary suitable for $GITHUB_STEP_SUMMARY. */
export function formatPlanMarkdown(plan: DeletionPlan): string {
  const s = plan.summary;
  const md: string[] = [
    `## 🧹 Artifact Cleanup Plan (${plan.dryRun ? "dry-run" : "live"})`,
    "",
    "| Metric | Value |",
    "| --- | --- |",
    `| Total artifacts | ${s.totalArtifacts} |`,
    `| Retained | ${s.retainedCount} |`,
    `| Deleted | ${s.deletedCount} |`,
    `| Space reclaimed | ${humanSize(s.spaceReclaimedBytes)} (${s.spaceReclaimedBytes} bytes) |`,
    `| Retained size | ${humanSize(s.retainedSizeBytes)} (${s.retainedSizeBytes} bytes) |`,
    "",
  ];
  if (plan.toDelete.length > 0) {
    md.push("### Artifacts to delete", "", "| Artifact | Size | Created | Reasons |", "| --- | --- | --- | --- |");
    for (const d of plan.toDelete) {
      md.push(
        `| ${d.artifact.name} | ${humanSize(d.artifact.sizeBytes)} | ${d.artifact.createdAt} | ${d.reasons.join(", ")} |`,
      );
    }
  } else {
    md.push("_No artifacts selected for deletion._");
  }
  return md.join("\n");
}

const USAGE = `Artifact Cleanup Script

Usage:
  bun run cleanup.ts --config <scenario.json> [overrides...]
  bun run cleanup.ts --artifacts <artifacts.json> [policy flags...]

Inputs:
  --config <path>        Scenario file: { now, dryRun, policy, artifacts }
  --artifacts <path>     JSON file containing just an array of artifacts

Policy (override scenario values):
  --max-age-days <n>         Delete artifacts older than n days
  --max-total-size <bytes>   Cap total retained size (bytes)
  --keep-latest <n>          Keep only the n newest artifacts per workflow

Options:
  --now <iso8601>        Reference "now" for age calculations
  --dry-run              Mark the plan as dry-run (default)
  --no-dry-run           Mark the plan as a live deletion
  --format <text|json>   Output format on stdout (default: text)
  --output <path>        Also write the full plan as JSON to <path>
  -h, --help             Show this help

If GITHUB_STEP_SUMMARY is set, a Markdown summary is appended to it.`;

/** Parse a numeric CLI argument, throwing a clear error on bad input. */
function parseIntArg(raw: string | undefined, flag: string): number {
  if (raw === undefined) throw new Error(`${flag} requires a value`);
  const n = Number(raw);
  if (!Number.isFinite(n) || !Number.isInteger(n) || n < 0) {
    throw new Error(`${flag} must be a non-negative integer, got "${raw}"`);
  }
  return n;
}

/** Read and JSON-parse a file, with a friendly error if it's missing/invalid. */
async function readJson(path: string): Promise<unknown> {
  const file = Bun.file(path);
  if (!(await file.exists())) {
    throw new Error(`input file not found: ${path}`);
  }
  const text = await file.text();
  try {
    return JSON.parse(text);
  } catch (err) {
    throw new Error(`failed to parse JSON in ${path}: ${(err as Error).message}`);
  }
}

/**
 * Resolve CLI argv (plus already-read file contents) into a CliConfig.
 * Exported so the argument handling can be reasoned about/tested in isolation.
 */
export function buildConfig(
  argv: string[],
  loaded: { scenario?: Scenario; artifacts?: Artifact[] },
): CliConfig {
  const policy: RetentionPolicy = { ...(loaded.scenario?.policy ?? {}) };
  const options: PlanOptions = {
    dryRun: loaded.scenario?.dryRun ?? true,
    now: loaded.scenario?.now ? new Date(loaded.scenario.now) : undefined,
  };
  let artifacts: Artifact[] | undefined = loaded.scenario?.artifacts ?? loaded.artifacts;
  let output: string | undefined;
  let format: "text" | "json" = "text";

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    switch (arg) {
      case "--config":
      case "--artifacts":
        i++; // value already consumed during the pre-read pass
        break;
      case "--max-age-days":
        policy.maxAgeDays = parseIntArg(argv[++i], "--max-age-days");
        break;
      case "--max-total-size":
        policy.maxTotalSizeBytes = parseIntArg(argv[++i], "--max-total-size");
        break;
      case "--keep-latest":
        policy.keepLatestNPerWorkflow = parseIntArg(argv[++i], "--keep-latest");
        break;
      case "--now": {
        const raw = argv[++i];
        if (raw === undefined) throw new Error("--now requires a value");
        const d = new Date(raw);
        if (Number.isNaN(d.getTime())) throw new Error(`--now is not a valid date: "${raw}"`);
        options.now = d;
        break;
      }
      case "--dry-run":
        options.dryRun = true;
        break;
      case "--no-dry-run":
        options.dryRun = false;
        break;
      case "--format": {
        const raw = argv[++i];
        if (raw !== "text" && raw !== "json") {
          throw new Error(`--format must be "text" or "json", got "${raw}"`);
        }
        format = raw;
        break;
      }
      case "--output":
        output = argv[++i];
        if (output === undefined) throw new Error("--output requires a value");
        break;
      default:
        throw new Error(`unknown argument: ${arg}`);
    }
  }

  if (!artifacts) {
    throw new Error("no artifacts provided; pass --config <file> or --artifacts <file>");
  }
  return { artifacts, policy, options, output, format };
}

/** Entry point for the CLI. Returns a process exit code. */
export async function runCli(argv: string[]): Promise<number> {
  if (argv.includes("-h") || argv.includes("--help")) {
    console.log(USAGE);
    return 0;
  }

  try {
    // Pre-read any file inputs referenced by --config / --artifacts.
    const loaded: { scenario?: Scenario; artifacts?: Artifact[] } = {};
    const configIdx = argv.indexOf("--config");
    if (configIdx !== -1) {
      const path = argv[configIdx + 1];
      if (!path) throw new Error("--config requires a value");
      loaded.scenario = (await readJson(path)) as Scenario;
    }
    const artifactsIdx = argv.indexOf("--artifacts");
    if (artifactsIdx !== -1) {
      const path = argv[artifactsIdx + 1];
      if (!path) throw new Error("--artifacts requires a value");
      const parsed = await readJson(path);
      if (!Array.isArray(parsed)) {
        throw new Error(`--artifacts file must contain a JSON array: ${path}`);
      }
      loaded.artifacts = parsed as Artifact[];
    }

    const config = buildConfig(argv, loaded);
    const plan = planCleanup(config.artifacts, config.policy, config.options);

    // stdout output
    if (config.format === "json") {
      console.log(JSON.stringify(plan, null, 2));
    } else {
      console.log(formatPlanText(plan));
    }

    // Optionally persist the full plan as JSON.
    if (config.output) {
      await Bun.write(config.output, `${JSON.stringify(plan, null, 2)}\n`);
      console.log(`Wrote plan JSON to ${config.output}`);
    }

    // Append a Markdown summary to the GitHub Actions job summary, if present.
    const summaryPath = process.env.GITHUB_STEP_SUMMARY;
    if (summaryPath) {
      const fs = await import("node:fs/promises");
      await fs.appendFile(summaryPath, `${formatPlanMarkdown(plan)}\n`);
    }

    return 0;
  } catch (err) {
    console.error(`Error: ${(err as Error).message}`);
    return 1;
  }
}

// Only run the CLI when executed directly (not when imported by tests).
if (import.meta.main) {
  runCli(process.argv.slice(2)).then((code) => process.exit(code));
}
