import type {
  Artifact,
  DeletionPlan,
  DoomedArtifact,
  PlanOptions,
  RetentionPolicy,
} from "./types";

const MS_PER_DAY = 86_400_000;

/** Rejects nonsensical policy values before any planning happens. */
function validatePolicy(policy: RetentionPolicy): void {
  if (policy.maxAgeDays !== undefined && !(policy.maxAgeDays >= 0)) {
    throw new Error(`maxAgeDays must be a non-negative number, got ${policy.maxAgeDays}`);
  }
  if (policy.maxTotalSizeBytes !== undefined && !(policy.maxTotalSizeBytes >= 0)) {
    throw new Error(
      `maxTotalSizeBytes must be a non-negative number, got ${policy.maxTotalSizeBytes}`,
    );
  }
  if (
    policy.keepLatestPerWorkflow !== undefined &&
    (!Number.isInteger(policy.keepLatestPerWorkflow) || policy.keepLatestPerWorkflow < 0)
  ) {
    throw new Error(
      `keepLatestPerWorkflow must be a non-negative integer, got ${policy.keepLatestPerWorkflow}`,
    );
  }
}

/** Rejects malformed artifacts so downstream math never sees NaN. */
function validateArtifacts(artifacts: Artifact[]): void {
  const seen = new Set<number>();
  for (const a of artifacts) {
    if (seen.has(a.id)) {
      throw new Error(`duplicate artifact id: ${a.id}`);
    }
    seen.add(a.id);
    if (Number.isNaN(Date.parse(a.createdAt))) {
      throw new Error(
        `artifact "${a.name}" (id=${a.id}) has invalid createdAt: ${JSON.stringify(a.createdAt)}`,
      );
    }
    if (!(a.sizeBytes >= 0)) {
      throw new Error(`artifact "${a.name}" (id=${a.id}) has invalid sizeBytes: ${a.sizeBytes}`);
    }
  }
}

/**
 * Builds a deletion plan by applying the configured retention policies.
 *
 * Policy semantics (applied in this order):
 *  1. max-age: artifacts strictly older than `maxAgeDays` are doomed.
 *  2. keep-latest-per-workflow: within each workflowRunId, artifacts ranked
 *     beyond the N most recent are doomed.
 *  3. max-total-size: if the surviving set still exceeds the size cap, the
 *     oldest survivors are doomed until the total fits.
 */
export function buildDeletionPlan(
  artifacts: Artifact[],
  policy: RetentionPolicy,
  options: PlanOptions,
): DeletionPlan {
  validatePolicy(policy);
  validateArtifacts(artifacts);

  // Reasons for deletion, keyed by artifact id. An artifact can be doomed by
  // several policies at once; we record all of them for the report.
  const doomed = new Map<number, string[]>();
  const condemn = (id: number, reason: string): void => {
    const reasons = doomed.get(id) ?? [];
    reasons.push(reason);
    doomed.set(id, reasons);
  };

  // --- Policy 1: max-age -----------------------------------------------
  if (policy.maxAgeDays !== undefined) {
    const cutoff = options.referenceDate.getTime() - policy.maxAgeDays * MS_PER_DAY;
    for (const a of artifacts) {
      if (new Date(a.createdAt).getTime() < cutoff) {
        condemn(a.id, "max-age");
      }
    }
  }

  // --- Policy 2: keep-latest-N per workflow ------------------------------
  if (policy.keepLatestPerWorkflow !== undefined) {
    const byRun = new Map<number, Artifact[]>();
    for (const a of artifacts) {
      const group = byRun.get(a.workflowRunId) ?? [];
      group.push(a);
      byRun.set(a.workflowRunId, group);
    }
    for (const group of byRun.values()) {
      // Newest first; ties broken by id (a higher id was created later).
      const ranked = [...group].sort(
        (x, y) =>
          new Date(y.createdAt).getTime() - new Date(x.createdAt).getTime() || y.id - x.id,
      );
      for (const a of ranked.slice(policy.keepLatestPerWorkflow)) {
        condemn(a.id, "keep-latest-per-workflow");
      }
    }
  }

  // --- Policy 3: max-total-size ------------------------------------------
  // Applied last so that space freed by the other policies counts first: we
  // only evict extra (oldest-first) survivors if the cap is still exceeded.
  if (policy.maxTotalSizeBytes !== undefined) {
    const survivors = artifacts
      .filter((a) => !doomed.has(a.id))
      .sort(
        (x, y) =>
          new Date(x.createdAt).getTime() - new Date(y.createdAt).getTime() || x.id - y.id,
      );
    let total = survivors.reduce((sum, a) => sum + a.sizeBytes, 0);
    for (const a of survivors) {
      if (total <= policy.maxTotalSizeBytes) break;
      condemn(a.id, "max-total-size");
      total -= a.sizeBytes;
    }
  }

  const toDelete: DoomedArtifact[] = artifacts
    .filter((a) => doomed.has(a.id))
    .map((a) => ({ ...a, reasons: doomed.get(a.id)! }));
  const toRetain = artifacts.filter((a) => !doomed.has(a.id));

  const spaceReclaimedBytes = toDelete.reduce((sum, a) => sum + a.sizeBytes, 0);
  const retainedSizeBytes = toRetain.reduce((sum, a) => sum + a.sizeBytes, 0);

  return {
    toDelete,
    toRetain,
    summary: {
      totalArtifacts: artifacts.length,
      retainedCount: toRetain.length,
      deletedCount: toDelete.length,
      spaceReclaimedBytes,
      retainedSizeBytes,
    },
    referenceDate: options.referenceDate.toISOString(),
    dryRun: options.dryRun ?? false,
  };
}
