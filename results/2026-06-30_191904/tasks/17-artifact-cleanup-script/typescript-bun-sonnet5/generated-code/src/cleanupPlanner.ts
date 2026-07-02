// Combines the individual retention policies into a single cleanup plan.
//
// Policies are applied in a fixed pipeline — max-age, then keep-latest-N,
// then max-total-size — each operating only on artifacts the previous
// policy retained. This ordering means an artifact is deleted for exactly
// one reason (whichever policy first flags it), so reason attribution in
// the summary is unambiguous.
import { applyKeepLatestNPolicy, applyMaxAgePolicy, applyMaxTotalSizePolicy } from "./retention";
import type {
  Artifact,
  CleanupPlan,
  CleanupSummary,
  DeletionReason,
  PlannedDeletion,
  RetentionPolicy,
} from "./types";
import { validateArtifacts, validatePolicy } from "./validation";

export function buildCleanupPlan(
  artifacts: Artifact[],
  policy: RetentionPolicy,
  now: Date = new Date(),
): CleanupPlan {
  validatePolicy(policy);
  validateArtifacts(artifacts);

  const deletions: PlannedDeletion[] = [];

  const afterMaxAge = applyMaxAgePolicy(artifacts, policy.maxAgeInDays, now);
  addDeletions(deletions, afterMaxAge.deleted, "max-age");

  const afterKeepLatestN = applyKeepLatestNPolicy(afterMaxAge.retained, policy.keepLatestN);
  addDeletions(deletions, afterKeepLatestN.deleted, "keep-latest-n");

  const afterMaxTotalSize = applyMaxTotalSizePolicy(
    afterKeepLatestN.retained,
    policy.maxTotalSizeInBytes,
  );
  addDeletions(deletions, afterMaxTotalSize.deleted, "max-total-size");

  const retained = afterMaxTotalSize.retained;
  return { retained, deletions, summary: buildSummary(artifacts, retained, deletions) };
}

function addDeletions(
  deletions: PlannedDeletion[],
  artifacts: Artifact[],
  reason: DeletionReason,
): void {
  for (const artifact of artifacts) {
    deletions.push({ artifact, reason });
  }
}

function buildSummary(
  allArtifacts: Artifact[],
  retained: Artifact[],
  deletions: PlannedDeletion[],
): CleanupSummary {
  const totalSizeInBytes = sumSizes(allArtifacts);
  const retainedSizeInBytes = sumSizes(retained);
  const deletedByReason: Record<DeletionReason, number> = {
    "max-age": 0,
    "keep-latest-n": 0,
    "max-total-size": 0,
  };
  for (const deletion of deletions) {
    deletedByReason[deletion.reason]++;
  }

  return {
    totalArtifacts: allArtifacts.length,
    retainedCount: retained.length,
    deletedCount: deletions.length,
    totalSizeInBytes,
    retainedSizeInBytes,
    reclaimedSizeInBytes: totalSizeInBytes - retainedSizeInBytes,
    deletedByReason,
  };
}

function sumSizes(artifacts: Artifact[]): number {
  return artifacts.reduce((sum, a) => sum + a.sizeInBytes, 0);
}
