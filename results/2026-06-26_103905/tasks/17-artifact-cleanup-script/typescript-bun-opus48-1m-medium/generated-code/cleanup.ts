/**
 * Artifact retention / cleanup planner.
 *
 * Given a list of artifacts with metadata, applies retention policies and
 * produces a deletion plan describing which artifacts to delete vs. retain,
 * plus a summary (space reclaimed, counts). Supports dry-run mode.
 */

/** A single CI artifact and its metadata. */
export interface Artifact {
  /** Human-readable artifact name. */
  name: string;
  /** Size of the artifact in bytes. */
  sizeBytes: number;
  /** ISO-8601 creation timestamp. */
  createdAt: string;
  /** Name of the workflow that produced the artifact (used for keep-latest-N). */
  workflowName: string;
  /** Identifier of the specific workflow run. */
  workflowRunId: number;
}

/** Retention policies. All fields are optional; omit to disable that policy. */
export interface RetentionPolicy {
  /** Delete artifacts older than this many days. */
  maxAgeDays?: number;
  /** Cap total retained size in bytes; oldest artifacts are deleted first. */
  maxTotalSizeBytes?: number;
  /** Always retain the N most recent artifacts per workflow. */
  keepLatestNPerWorkflow?: number;
}

/** Options influencing planning (injectable clock for deterministic tests). */
export interface PlanOptions {
  /** ISO-8601 "current time"; defaults to the real wall clock. */
  now?: string;
  /** When true, the plan is informational only (no side effects). */
  dryRun?: boolean;
}

/** Why a particular artifact was marked for deletion. */
export type DeletionReason = "max-age" | "keep-latest-n" | "max-total-size";

/** An artifact slated for deletion, annotated with the reason. */
export interface DeletionEntry {
  artifact: Artifact;
  reason: DeletionReason;
}

/** Summary statistics for a cleanup plan. */
export interface CleanupSummary {
  totalArtifacts: number;
  retainedCount: number;
  deletedCount: number;
  bytesReclaimed: number;
  bytesRetained: number;
}

/** The full deletion plan. */
export interface CleanupPlan {
  toDelete: DeletionEntry[];
  toRetain: Artifact[];
  summary: CleanupSummary;
  dryRun: boolean;
}

/**
 * Produce a cleanup plan. The planner is pure: it never mutates inputs and has
 * no side effects, which makes it trivially testable.
 */
export function planCleanup(
  artifacts: Artifact[],
  policy: RetentionPolicy,
  options: PlanOptions = {},
): CleanupPlan {
  validate(artifacts, policy);

  const now = parseDate(options.now ?? new Date().toISOString(), "options.now");

  // Artifacts that keep-latest-N protects: never eligible for deletion.
  const protectedIds = computeProtectedSet(
    artifacts,
    policy.keepLatestNPerWorkflow,
  );

  const deletions = new Map<Artifact, DeletionReason>();
  // Record a reason only if the artifact is not already slated for deletion,
  // so the first (highest-priority) policy that matches "wins" the reason.
  const markForDeletion = (artifact: Artifact, reason: DeletionReason): void => {
    if (!deletions.has(artifact)) deletions.set(artifact, reason);
  };

  // --- Policy 1: max age ---------------------------------------------------
  // Delete anything older than the cutoff, unless protected by keep-latest-N.
  if (policy.maxAgeDays !== undefined) {
    const maxAgeMs = policy.maxAgeDays * MS_PER_DAY;
    for (const artifact of artifacts) {
      if (protectedIds.has(artifact)) continue;
      const ageMs = now - parseDate(artifact.createdAt, artifact.name);
      if (ageMs > maxAgeMs) markForDeletion(artifact, "max-age");
    }
  }

  // --- Policy 2: keep-latest-N per workflow -------------------------------
  // keep-latest-N is an active retention policy: keep the N most recent
  // artifacts per workflow (the protected set) and delete every other one.
  if (policy.keepLatestNPerWorkflow !== undefined) {
    for (const artifact of artifacts) {
      if (!protectedIds.has(artifact)) markForDeletion(artifact, "keep-latest-n");
    }
  }

  // --- Policy 3: max total size -------------------------------------------
  // Delete oldest non-protected, not-yet-deleted artifacts until the retained
  // total is within budget.
  if (policy.maxTotalSizeBytes !== undefined) {
    let retainedBytes = artifacts
      .filter((a) => !deletions.has(a))
      .reduce((sum, a) => sum + a.sizeBytes, 0);

    if (retainedBytes > policy.maxTotalSizeBytes) {
      // Oldest first among candidates we are still allowed to delete.
      const candidates = artifacts
        .filter((a) => !deletions.has(a) && !protectedIds.has(a))
        .sort((a, b) => parseDate(a.createdAt, a.name) - parseDate(b.createdAt, b.name));

      for (const artifact of candidates) {
        if (retainedBytes <= policy.maxTotalSizeBytes) break;
        deletions.set(artifact, "max-total-size");
        retainedBytes -= artifact.sizeBytes;
      }
    }
  }

  const toDelete: DeletionEntry[] = artifacts
    .filter((a) => deletions.has(a))
    .map((a) => ({ artifact: a, reason: deletions.get(a)! }));
  const toRetain: Artifact[] = artifacts.filter((a) => !deletions.has(a));

  const bytesReclaimed = toDelete.reduce((s, d) => s + d.artifact.sizeBytes, 0);
  const bytesRetained = toRetain.reduce((s, a) => s + a.sizeBytes, 0);

  return {
    toDelete,
    toRetain,
    summary: {
      totalArtifacts: artifacts.length,
      retainedCount: toRetain.length,
      deletedCount: toDelete.length,
      bytesReclaimed,
      bytesRetained,
    },
    dryRun: options.dryRun ?? false,
  };
}

const MS_PER_DAY = 24 * 60 * 60 * 1000;

/**
 * Compute the set of artifacts protected by keep-latest-N: for each workflow,
 * the N artifacts with the most recent creation dates are retained.
 */
function computeProtectedSet(
  artifacts: Artifact[],
  keepLatestN: number | undefined,
): Set<Artifact> {
  const protectedSet = new Set<Artifact>();
  if (keepLatestN === undefined || keepLatestN <= 0) return protectedSet;

  const byWorkflow = new Map<string, Artifact[]>();
  for (const artifact of artifacts) {
    const group = byWorkflow.get(artifact.workflowName) ?? [];
    group.push(artifact);
    byWorkflow.set(artifact.workflowName, group);
  }

  for (const group of byWorkflow.values()) {
    group
      .slice()
      // Newest first.
      .sort((a, b) => parseDate(b.createdAt, b.name) - parseDate(a.createdAt, a.name))
      .slice(0, keepLatestN)
      .forEach((a) => protectedSet.add(a));
  }

  return protectedSet;
}

/** Parse an ISO date, throwing a meaningful error on bad input. */
function parseDate(value: string, context: string): number {
  const ms = Date.parse(value);
  if (Number.isNaN(ms)) {
    throw new Error(
      `Invalid date "${value}" for ${context}; expected an ISO-8601 timestamp.`,
    );
  }
  return ms;
}

/** Validate inputs up front so failures are clear rather than silently wrong. */
function validate(artifacts: Artifact[], policy: RetentionPolicy): void {
  if (!Array.isArray(artifacts)) {
    throw new Error("artifacts must be an array.");
  }
  for (const a of artifacts) {
    if (typeof a.name !== "string" || a.name.length === 0) {
      throw new Error("Each artifact must have a non-empty name.");
    }
    if (typeof a.sizeBytes !== "number" || a.sizeBytes < 0) {
      throw new Error(`Artifact "${a.name}" has an invalid sizeBytes.`);
    }
  }
  if (policy.maxAgeDays !== undefined && policy.maxAgeDays < 0) {
    throw new Error("maxAgeDays must be >= 0.");
  }
  if (policy.maxTotalSizeBytes !== undefined && policy.maxTotalSizeBytes < 0) {
    throw new Error("maxTotalSizeBytes must be >= 0.");
  }
  if (
    policy.keepLatestNPerWorkflow !== undefined &&
    policy.keepLatestNPerWorkflow < 0
  ) {
    throw new Error("keepLatestNPerWorkflow must be >= 0.");
  }
}

/** Shape of a JSON config file consumed by the CLI. */
export interface CleanupConfig {
  artifacts: Artifact[];
  policy?: RetentionPolicy;
  now?: string;
  dryRun?: boolean;
}

/**
 * Render a human-readable + machine-parseable report for a plan. The `KEY=value`
 * lines are stable so CI (and the act-based test harness) can assert on exact
 * values rather than fuzzy text matching.
 */
export function renderReport(plan: CleanupPlan): string {
  const lines: string[] = [];
  lines.push("=== Artifact Cleanup Plan ===");
  lines.push(`MODE=${plan.dryRun ? "DRY-RUN" : "EXECUTE"}`);
  lines.push(`TOTAL_ARTIFACTS=${plan.summary.totalArtifacts}`);
  lines.push(`RETAINED_COUNT=${plan.summary.retainedCount}`);
  lines.push(`DELETED_COUNT=${plan.summary.deletedCount}`);
  lines.push(`BYTES_RECLAIMED=${plan.summary.bytesReclaimed}`);
  lines.push(`BYTES_RETAINED=${plan.summary.bytesRetained}`);
  for (const d of plan.toDelete) {
    lines.push(`DELETE ${d.artifact.name} reason=${d.reason} size=${d.artifact.sizeBytes}`);
  }
  for (const a of plan.toRetain) {
    lines.push(`RETAIN ${a.name} size=${a.sizeBytes}`);
  }
  if (plan.dryRun) {
    lines.push("NOTE: dry-run mode — no artifacts were actually deleted.");
  }
  return lines.join("\n");
}

/** Load and minimally validate a JSON config file. */
export async function loadConfig(path: string): Promise<CleanupConfig> {
  const file = Bun.file(path);
  if (!(await file.exists())) {
    throw new Error(`Config file not found: ${path}`);
  }
  let parsed: unknown;
  try {
    parsed = await file.json();
  } catch (err) {
    throw new Error(
      `Failed to parse JSON config "${path}": ${(err as Error).message}`,
    );
  }
  const config = parsed as CleanupConfig;
  if (!config || !Array.isArray(config.artifacts)) {
    throw new Error(
      `Config "${path}" must be an object with an "artifacts" array.`,
    );
  }
  return config;
}

/** CLI entry: `bun run cleanup.ts <config.json>`. */
async function main(argv: string[]): Promise<number> {
  const configPath = argv[0];
  if (!configPath) {
    console.error("Usage: bun run cleanup.ts <config.json>");
    return 2;
  }
  try {
    const config = await loadConfig(configPath);
    const plan = planCleanup(config.artifacts, config.policy ?? {}, {
      now: config.now,
      dryRun: config.dryRun,
    });
    console.log(renderReport(plan));
    return 0;
  } catch (err) {
    console.error(`Error: ${(err as Error).message}`);
    return 1;
  }
}

// Only run the CLI when executed directly, not when imported by tests.
if (import.meta.main) {
  main(Bun.argv.slice(2)).then((code) => process.exit(code));
}
