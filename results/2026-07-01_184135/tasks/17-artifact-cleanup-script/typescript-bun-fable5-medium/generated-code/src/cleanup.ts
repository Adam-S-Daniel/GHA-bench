/**
 * Artifact cleanup core logic.
 *
 * Approach: retention policies are applied as a pipeline of pure functions
 * over an immutable artifact list. Each policy stage marks artifacts for
 * deletion with a reason; the final plan aggregates marks into a summary.
 * All functions take an explicit `now` timestamp so behavior is fully
 * deterministic and testable (no hidden clock access).
 */

/** A single build artifact with the metadata the cleanup rules operate on. */
export interface Artifact {
  /** Artifact name, unique within the fixture set. */
  name: string;
  /** Size in bytes. Must be a non-negative integer. */
  sizeBytes: number;
  /** ISO-8601 creation timestamp. */
  createdAt: string;
  /** ID of the workflow run that produced this artifact. */
  workflowRunId: number;
}

/** Retention policy configuration. Every rule is optional. */
export interface RetentionPolicy {
  /** Delete artifacts older than this many days (relative to `now`). */
  maxAgeDays?: number;
  /** Keep only the newest N artifacts per workflow run ID. */
  keepLatestPerWorkflow?: number;
  /** After other rules, delete oldest survivors until total size fits. */
  maxTotalSizeBytes?: number;
  /** When true, the plan is reported but nothing is deleted. */
  dryRun?: boolean;
}

/** Why an artifact was selected for deletion. */
export type DeletionReason = "max-age" | "keep-latest" | "max-total-size";

/** One entry in the deletion plan. */
export interface PlannedDeletion {
  artifact: Artifact;
  reason: DeletionReason;
}

/** Full deletion plan plus summary numbers. */
export interface DeletionPlan {
  toDelete: PlannedDeletion[];
  retained: Artifact[];
  summary: {
    deletedCount: number;
    retainedCount: number;
    spaceReclaimedBytes: number;
    dryRun: boolean;
  };
}

/**
 * Split artifacts into { expired, fresh } by age.
 * An artifact is expired when it is strictly older than `maxAgeDays`.
 */
/**
 * Split artifacts into { evicted, kept }, keeping only the newest `n`
 * artifacts within each workflow run ID group.
 */
export function partitionByKeepLatest(
  artifacts: Artifact[],
  n: number,
): { evicted: Artifact[]; kept: Artifact[] } {
  if (!Number.isInteger(n) || n <= 0) {
    throw new Error(`keepLatestPerWorkflow must be a positive integer, got ${n}`);
  }
  const byRun = new Map<number, Artifact[]>();
  for (const artifact of artifacts) {
    const group = byRun.get(artifact.workflowRunId);
    if (group) {
      group.push(artifact);
    } else {
      byRun.set(artifact.workflowRunId, [artifact]);
    }
  }
  const evicted: Artifact[] = [];
  const kept: Artifact[] = [];
  for (const group of byRun.values()) {
    const newestFirst = [...group].sort(
      (a, b) => createdAtMs(b) - createdAtMs(a),
    );
    kept.push(...newestFirst.slice(0, n));
    evicted.push(...newestFirst.slice(n));
  }
  return { evicted, kept };
}

/**
 * Split artifacts into { overflow, kept } so that the kept set's total size
 * is at most `maxTotalSizeBytes`. Oldest artifacts are sacrificed first.
 */
export function partitionByMaxTotalSize(
  artifacts: Artifact[],
  maxTotalSizeBytes: number,
): { overflow: Artifact[]; kept: Artifact[] } {
  if (!Number.isFinite(maxTotalSizeBytes) || maxTotalSizeBytes < 0) {
    throw new Error(
      `maxTotalSizeBytes must be a non-negative number, got ${maxTotalSizeBytes}`,
    );
  }
  // Walk oldest-first, evicting until the remaining total fits the cap.
  const oldestFirst = [...artifacts].sort(
    (a, b) => createdAtMs(a) - createdAtMs(b),
  );
  let total: number = artifacts.reduce((sum, a) => sum + a.sizeBytes, 0);
  const overflow: Artifact[] = [];
  for (const artifact of oldestFirst) {
    if (total <= maxTotalSizeBytes) break;
    overflow.push(artifact);
    total -= artifact.sizeBytes;
  }
  const overflowNames = new Set(overflow.map((a) => a.name));
  const kept = artifacts.filter((a) => !overflowNames.has(a.name));
  return { overflow, kept };
}

/**
 * Apply all configured retention policies, in order:
 *   1. max-age  2. keep-latest-N per workflow  3. max-total-size
 * Rules not present in the policy are skipped. Returns the full plan.
 */
/** Validate the artifact list itself (fields + name uniqueness). */
function validateArtifacts(artifacts: Artifact[]): void {
  const seen = new Set<string>();
  for (const artifact of artifacts) {
    if (seen.has(artifact.name)) {
      throw new Error(`duplicate artifact name: "${artifact.name}"`);
    }
    seen.add(artifact.name);
    if (!Number.isFinite(artifact.sizeBytes) || artifact.sizeBytes < 0) {
      throw new Error(
        `artifact "${artifact.name}" has invalid sizeBytes: ${artifact.sizeBytes}`,
      );
    }
    createdAtMs(artifact); // throws on malformed createdAt
  }
}

export function buildDeletionPlan(
  artifacts: Artifact[],
  policy: RetentionPolicy,
  now: Date,
): DeletionPlan {
  validateArtifacts(artifacts);

  const toDelete: PlannedDeletion[] = [];
  let survivors: Artifact[] = artifacts;

  if (policy.maxAgeDays !== undefined) {
    const { expired, fresh } = partitionByMaxAge(
      survivors,
      policy.maxAgeDays,
      now,
    );
    toDelete.push(...expired.map((a) => ({ artifact: a, reason: "max-age" as const })));
    survivors = fresh;
  }
  if (policy.keepLatestPerWorkflow !== undefined) {
    const { evicted, kept } = partitionByKeepLatest(
      survivors,
      policy.keepLatestPerWorkflow,
    );
    toDelete.push(...evicted.map((a) => ({ artifact: a, reason: "keep-latest" as const })));
    survivors = kept;
  }
  if (policy.maxTotalSizeBytes !== undefined) {
    const { overflow, kept } = partitionByMaxTotalSize(
      survivors,
      policy.maxTotalSizeBytes,
    );
    toDelete.push(...overflow.map((a) => ({ artifact: a, reason: "max-total-size" as const })));
    survivors = kept;
  }

  return {
    toDelete,
    retained: survivors,
    summary: {
      deletedCount: toDelete.length,
      retainedCount: survivors.length,
      spaceReclaimedBytes: toDelete.reduce(
        (sum, d) => sum + d.artifact.sizeBytes,
        0,
      ),
      dryRun: policy.dryRun ?? false,
    },
  };
}

/** Function that performs the actual deletion of one artifact (injectable for tests). */
export type ArtifactDeleter = (artifact: Artifact) => Promise<void>;

/**
 * Execute a deletion plan. In dry-run mode the deleter is never invoked.
 * Returns the names of artifacts actually deleted.
 */
export async function executePlan(
  plan: DeletionPlan,
  deleter: ArtifactDeleter,
): Promise<string[]> {
  if (plan.summary.dryRun) return [];
  const deleted: string[] = [];
  for (const { artifact } of plan.toDelete) {
    try {
      await deleter(artifact);
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      throw new Error(`failed to delete artifact "${artifact.name}": ${message}`);
    }
    deleted.push(artifact.name);
  }
  return deleted;
}

/**
 * Render a plan as stable, machine-parseable text lines. The CI pipeline
 * prints this and the act test harness asserts on the exact values.
 */
export function formatPlanReport(plan: DeletionPlan): string {
  const lines: string[] = [
    `MODE ${plan.summary.dryRun ? "dry-run" : "execute"}`,
  ];
  for (const { artifact, reason } of plan.toDelete) {
    lines.push(`DELETE ${artifact.name} reason=${reason} size=${artifact.sizeBytes}`);
  }
  for (const artifact of plan.retained) {
    lines.push(`RETAIN ${artifact.name} size=${artifact.sizeBytes}`);
  }
  lines.push(
    `SUMMARY deleted=${plan.summary.deletedCount}` +
      ` retained=${plan.summary.retainedCount}` +
      ` reclaimed_bytes=${plan.summary.spaceReclaimedBytes}`,
  );
  return lines.join("\n");
}

const MS_PER_DAY: number = 24 * 60 * 60 * 1000;

/** Parse an artifact's createdAt, failing loudly on malformed input. */
export function createdAtMs(artifact: Artifact): number {
  const ms: number = Date.parse(artifact.createdAt);
  if (Number.isNaN(ms)) {
    throw new Error(
      `artifact "${artifact.name}" has invalid createdAt: "${artifact.createdAt}"`,
    );
  }
  return ms;
}

export function partitionByMaxAge(
  artifacts: Artifact[],
  maxAgeDays: number,
  now: Date,
): { expired: Artifact[]; fresh: Artifact[] } {
  if (!Number.isFinite(maxAgeDays) || maxAgeDays < 0) {
    throw new Error(
      `maxAgeDays must be a non-negative number, got ${maxAgeDays}`,
    );
  }
  const cutoffMs: number = now.getTime() - maxAgeDays * MS_PER_DAY;
  const expired: Artifact[] = [];
  const fresh: Artifact[] = [];
  for (const artifact of artifacts) {
    (createdAtMs(artifact) < cutoffMs ? expired : fresh).push(artifact);
  }
  return { expired, fresh };
}
