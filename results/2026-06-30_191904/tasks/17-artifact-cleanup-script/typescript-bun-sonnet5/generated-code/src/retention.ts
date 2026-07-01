// Individual retention policy implementations. Each function takes a list of
// artifacts and returns a { retained, deleted } split; callers compose them
// in sequence (see cleanupPlanner.ts) so an artifact deleted by an earlier
// policy is never re-evaluated by a later one.
import type { Artifact } from "./types";

export interface PolicySplit {
  retained: Artifact[];
  deleted: Artifact[];
}

const MS_PER_DAY = 24 * 60 * 60 * 1000;

/**
 * Deletes artifacts whose age (relative to `now`) exceeds `maxAgeInDays`.
 * Passing `undefined` disables the rule (everything is retained).
 */
export function applyMaxAgePolicy(
  artifacts: Artifact[],
  maxAgeInDays: number | undefined,
  now: Date,
): PolicySplit {
  if (maxAgeInDays === undefined) {
    return { retained: [...artifacts], deleted: [] };
  }
  if (maxAgeInDays < 0) {
    throw new Error(`maxAgeInDays must be >= 0, got ${maxAgeInDays}`);
  }

  const retained: Artifact[] = [];
  const deleted: Artifact[] = [];
  for (const artifact of artifacts) {
    const ageInDays = (now.getTime() - artifact.createdAt.getTime()) / MS_PER_DAY;
    if (ageInDays > maxAgeInDays) {
      deleted.push(artifact);
    } else {
      retained.push(artifact);
    }
  }
  return { retained, deleted };
}

/**
 * Within each workflowId group, keeps only the `keepLatestN` most recently
 * created artifacts and deletes the rest. Passing `undefined` disables the
 * rule (everything is retained).
 */
export function applyKeepLatestNPolicy(
  artifacts: Artifact[],
  keepLatestN: number | undefined,
): PolicySplit {
  if (keepLatestN === undefined) {
    return { retained: [...artifacts], deleted: [] };
  }
  if (keepLatestN < 0) {
    throw new Error(`keepLatestN must be >= 0, got ${keepLatestN}`);
  }

  const byWorkflow = new Map<string, Artifact[]>();
  for (const artifact of artifacts) {
    const group = byWorkflow.get(artifact.workflowId) ?? [];
    group.push(artifact);
    byWorkflow.set(artifact.workflowId, group);
  }

  const retained: Artifact[] = [];
  const deleted: Artifact[] = [];
  for (const group of byWorkflow.values()) {
    const sortedNewestFirst = [...group].sort(
      (a, b) => b.createdAt.getTime() - a.createdAt.getTime(),
    );
    retained.push(...sortedNewestFirst.slice(0, keepLatestN));
    deleted.push(...sortedNewestFirst.slice(keepLatestN));
  }
  return { retained, deleted };
}

/**
 * Enforces a combined size budget across all artifacts, deleting the oldest
 * ones first until the retained total fits within `maxTotalSizeInBytes`.
 * Passing `undefined` disables the rule (everything is retained).
 */
export function applyMaxTotalSizePolicy(
  artifacts: Artifact[],
  maxTotalSizeInBytes: number | undefined,
): PolicySplit {
  if (maxTotalSizeInBytes === undefined) {
    return { retained: [...artifacts], deleted: [] };
  }
  if (maxTotalSizeInBytes < 0) {
    throw new Error(`maxTotalSizeInBytes must be >= 0, got ${maxTotalSizeInBytes}`);
  }

  const oldestFirst = [...artifacts].sort(
    (a, b) => a.createdAt.getTime() - b.createdAt.getTime(),
  );

  let runningTotal = oldestFirst.reduce((sum, a) => sum + a.sizeInBytes, 0);
  const retained: Artifact[] = [];
  const deleted: Artifact[] = [];
  for (const artifact of oldestFirst) {
    if (runningTotal > maxTotalSizeInBytes) {
      deleted.push(artifact);
      runningTotal -= artifact.sizeInBytes;
    } else {
      retained.push(artifact);
    }
  }
  return { retained, deleted };
}
