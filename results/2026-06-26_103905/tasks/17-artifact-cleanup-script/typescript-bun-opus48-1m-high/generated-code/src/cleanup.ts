/**
 * Core artifact retention / cleanup logic.
 *
 * Pure, side-effect-free functions: given a list of artifacts and a retention
 * policy, decide which artifacts to delete and which to keep, then summarise.
 * Keeping this module pure makes it trivial to unit test and lets the CLI layer
 * own all the I/O (reading fixtures, printing, exit codes).
 */

/** A single CI artifact with the metadata we make retention decisions on. */
export interface Artifact {
  /** Human-readable artifact name (e.g. "build-output"). */
  name: string;
  /** Size of the artifact in bytes. */
  sizeBytes: number;
  /** ISO-8601 creation timestamp. */
  createdAt: string;
  /** ID of the workflow run that produced the artifact. */
  workflowRunId: number;
}

/**
 * Retention policy. Every field is optional; an omitted field means "this rule
 * does not apply". When multiple rules are present they are combined (see
 * planCleanup for the precise, documented semantics).
 */
export interface RetentionPolicy {
  /** Delete artifacts strictly older than this many days. */
  maxAgeDays?: number;
  /** Cap the total size of *retained* artifacts; delete oldest first to fit. */
  maxTotalSizeBytes?: number;
  /** Keep only the N most recent artifacts per workflow run id. */
  keepLatestNPerWorkflow?: number;
}

/** Options for the planner, mainly to make time deterministic in tests. */
export interface PlanOptions {
  /** Reference "now" used for age calculations. Defaults to the wall clock. */
  now?: Date;
}

/** Aggregate statistics describing the outcome of a cleanup plan. */
export interface PlanSummary {
  totalArtifacts: number;
  retainedCount: number;
  deletedCount: number;
  totalSizeBytes: number;
  spaceReclaimedBytes: number;
  retainedSizeBytes: number;
}

/** The full result of planning: who stays, who goes, and the headline numbers. */
export interface DeletionPlan {
  toDelete: Artifact[];
  toRetain: Artifact[];
  summary: PlanSummary;
}

const MILLIS_PER_DAY = 24 * 60 * 60 * 1000;

/**
 * Produce a deletion plan for the given artifacts under the given policy.
 *
 * Rules are applied in order: (1) max-age and (2) keep-latest-N each add to the
 * deletion set independently (union), then (3) the max-total-size cap evicts the
 * oldest survivors until the retained total fits the budget. The result is the
 * same regardless of which subset of rules the policy enables.
 */
export function planCleanup(
  artifacts: Artifact[],
  policy: RetentionPolicy,
  options: PlanOptions = {},
): DeletionPlan {
  const now = options.now ?? new Date();

  // A Set of artifacts marked for deletion. Each policy rule adds to it.
  const deleteSet = new Set<Artifact>();

  // Rule: max age. An artifact older than maxAgeDays is deleted.
  if (policy.maxAgeDays !== undefined) {
    for (const a of artifacts) {
      const ageDays = (now.getTime() - new Date(a.createdAt).getTime()) / MILLIS_PER_DAY;
      if (ageDays > policy.maxAgeDays) {
        deleteSet.add(a);
      }
    }
  }

  // Rule: keep latest N per workflow run. Group artifacts by workflowRunId,
  // sort each group newest-first, and delete everything past the first N.
  if (policy.keepLatestNPerWorkflow !== undefined) {
    const n = policy.keepLatestNPerWorkflow;
    const groups = new Map<number, Artifact[]>();
    for (const a of artifacts) {
      const group = groups.get(a.workflowRunId) ?? [];
      group.push(a);
      groups.set(a.workflowRunId, group);
    }
    for (const group of groups.values()) {
      group.sort((x, y) => new Date(y.createdAt).getTime() - new Date(x.createdAt).getTime());
      for (const a of group.slice(n)) {
        deleteSet.add(a);
      }
    }
  }

  // Rule: max total size. Applied LAST, on the survivors of the rules above,
  // so size eviction never has to reconsider artifacts already condemned.
  // We evict oldest-first until the retained total fits within the budget.
  if (policy.maxTotalSizeBytes !== undefined) {
    const survivors = artifacts
      .filter((a) => !deleteSet.has(a))
      .sort((x, y) => new Date(x.createdAt).getTime() - new Date(y.createdAt).getTime());
    let retainedSize = survivors.reduce((sum, a) => sum + a.sizeBytes, 0);
    for (const a of survivors) {
      if (retainedSize <= policy.maxTotalSizeBytes) break;
      deleteSet.add(a);
      retainedSize -= a.sizeBytes;
    }
  }

  const toDelete = artifacts.filter((a) => deleteSet.has(a));
  const toRetain = artifacts.filter((a) => !deleteSet.has(a));

  const totalSizeBytes = artifacts.reduce((sum, a) => sum + a.sizeBytes, 0);
  const spaceReclaimedBytes = toDelete.reduce((sum, a) => sum + a.sizeBytes, 0);
  const summary: PlanSummary = {
    totalArtifacts: artifacts.length,
    retainedCount: toRetain.length,
    deletedCount: toDelete.length,
    totalSizeBytes,
    spaceReclaimedBytes,
    retainedSizeBytes: totalSizeBytes - spaceReclaimedBytes,
  };

  return { toDelete, toRetain, summary };
}
