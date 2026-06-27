/**
 * Artifact cleanup core logic.
 *
 * Given a set of CI artifacts and a retention policy, decide which artifacts
 * to delete and which to keep, then summarize the outcome. All functions here
 * are pure: they take an explicit `now` so behaviour is deterministic and
 * testable, and they never perform I/O.
 */

/** A single CI artifact with the metadata we make retention decisions on. */
export interface Artifact {
  /** Human-readable artifact name. */
  name: string;
  /** Size of the artifact in bytes. */
  sizeBytes: number;
  /** Creation timestamp as an ISO-8601 string. */
  createdAt: string;
  /** ID of the workflow run that produced the artifact. */
  workflowRunId: string;
}

/**
 * Retention policy. Every field is optional; an omitted field means "this
 * dimension does not constrain retention". Policies are additive — an artifact
 * is deleted if ANY policy marks it for deletion.
 */
export interface RetentionPolicy {
  /** Delete artifacts strictly older than this many days. */
  maxAgeDays?: number;
  /** Cap the total retained size (bytes); oldest artifacts are dropped first. */
  maxTotalSizeBytes?: number;
  /** Per workflow run, keep only the N most recently created artifacts. */
  keepLatestNPerWorkflow?: number;
}

/** The result of evaluating a retention policy against a set of artifacts. */
export interface DeletionPlan {
  toDelete: Artifact[];
  toRetain: Artifact[];
}

/** Aggregate statistics describing the outcome of a deletion plan. */
export interface PlanSummary {
  deletedCount: number;
  retainedCount: number;
  /** Total bytes freed by deleting the `toDelete` artifacts. */
  spaceReclaimedBytes: number;
  /** Total bytes still occupied by the `toRetain` artifacts. */
  retainedSizeBytes: number;
}

/** Sum the byte sizes of a list of artifacts. */
function totalSize(artifacts: Artifact[]): number {
  return artifacts.reduce((sum, a) => sum + a.sizeBytes, 0);
}

/** Compute summary statistics for a deletion plan. */
export function summarize(plan: DeletionPlan): PlanSummary {
  return {
    deletedCount: plan.toDelete.length,
    retainedCount: plan.toRetain.length,
    spaceReclaimedBytes: totalSize(plan.toDelete),
    retainedSizeBytes: totalSize(plan.toRetain),
  };
}

const MS_PER_DAY = 1000 * 60 * 60 * 24;

/**
 * Parse and validate a JSON string into an Artifact[]. Throws Error with a
 * clear, actionable message when the data is malformed so the CLI can report
 * exactly what went wrong rather than crashing with a stack trace.
 */
export function parseArtifacts(json: string): Artifact[] {
  let data: unknown;
  try {
    data = JSON.parse(json);
  } catch (err) {
    throw new Error(
      `Invalid JSON: ${(err as Error).message}. Provide a JSON array of artifacts.`,
    );
  }

  if (!Array.isArray(data)) {
    throw new Error("Artifact input must be a JSON array of artifact objects.");
  }

  return data.map((raw, i) => validateArtifact(raw, i));
}

/** Validate a single raw value into an Artifact, with index-tagged errors. */
function validateArtifact(raw: unknown, index: number): Artifact {
  const where = `artifact at index ${index}`;
  if (typeof raw !== "object" || raw === null) {
    throw new Error(`${where} must be an object.`);
  }
  const obj = raw as Record<string, unknown>;

  if (typeof obj.name !== "string" || obj.name.length === 0) {
    throw new Error(`${where} is missing a valid "name" (non-empty string).`);
  }
  if (typeof obj.workflowRunId !== "string" || obj.workflowRunId.length === 0) {
    throw new Error(`${where} is missing a valid "workflowRunId" (non-empty string).`);
  }
  if (typeof obj.sizeBytes !== "number" || !Number.isFinite(obj.sizeBytes) || obj.sizeBytes < 0) {
    throw new Error(`${where} has an invalid "sizeBytes" (must be a number >= 0).`);
  }
  if (typeof obj.createdAt !== "string" || Number.isNaN(new Date(obj.createdAt).getTime())) {
    throw new Error(`${where} has an invalid "createdAt" (must be an ISO-8601 date string).`);
  }

  return {
    name: obj.name,
    sizeBytes: obj.sizeBytes,
    createdAt: obj.createdAt,
    workflowRunId: obj.workflowRunId,
  };
}

/** Age of an artifact in whole-and-fractional days relative to `now`. */
function ageInDays(artifact: Artifact, now: Date): number {
  const created = new Date(artifact.createdAt).getTime();
  return (now.getTime() - created) / MS_PER_DAY;
}

/** Newest-first comparator (descending by creation time). */
function byNewestFirst(a: Artifact, b: Artifact): number {
  return new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime();
}

/**
 * Build a deletion plan from artifacts + policy. The `now` parameter is
 * injected for deterministic, testable age calculations.
 *
 * Policies are applied as successive stages, each operating on the artifacts
 * that have survived earlier stages. An artifact is deleted if any stage marks
 * it. We track deletions by array index so that artifacts with identical names
 * are handled correctly.
 */
export function planDeletion(
  artifacts: Artifact[],
  policy: RetentionPolicy,
  now: Date,
): DeletionPlan {
  const deleted = new Set<number>();
  const survives = (i: number) => !deleted.has(i);

  // Stage 1: max age — drop anything strictly older than the limit.
  if (policy.maxAgeDays !== undefined) {
    const maxAge = policy.maxAgeDays;
    artifacts.forEach((artifact, i) => {
      if (ageInDays(artifact, now) > maxAge) deleted.add(i);
    });
  }

  // Stage 2: keep-latest-N per workflow — within each workflow run, keep the N
  // most recent survivors and delete the rest.
  if (policy.keepLatestNPerWorkflow !== undefined) {
    const keepN = policy.keepLatestNPerWorkflow;
    const byWorkflow = new Map<string, number[]>();
    artifacts.forEach((artifact, i) => {
      if (!survives(i)) return;
      const group = byWorkflow.get(artifact.workflowRunId) ?? [];
      group.push(i);
      byWorkflow.set(artifact.workflowRunId, group);
    });
    for (const indices of byWorkflow.values()) {
      indices
        .sort((x, y) => byNewestFirst(artifacts[x]!, artifacts[y]!))
        .slice(keepN) // everything past the N newest
        .forEach((i) => deleted.add(i));
    }
  }

  // Stage 3: max total size — if surviving artifacts exceed the cap, delete the
  // oldest first until the retained total fits within the budget.
  if (policy.maxTotalSizeBytes !== undefined) {
    const survivors = artifacts
      .map((_, i) => i)
      .filter(survives)
      .sort((x, y) => byNewestFirst(artifacts[x]!, artifacts[y]!)); // newest first
    let runningTotal = 0;
    for (const i of survivors) {
      runningTotal += artifacts[i]!.sizeBytes;
      if (runningTotal > policy.maxTotalSizeBytes) deleted.add(i);
    }
  }

  const toDelete: Artifact[] = [];
  const toRetain: Artifact[] = [];
  artifacts.forEach((artifact, i) => {
    (deleted.has(i) ? toDelete : toRetain).push(artifact);
  });

  return { toDelete, toRetain };
}
