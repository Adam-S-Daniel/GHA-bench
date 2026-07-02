// Input validation for artifacts and retention policies. Fails fast with
// specific, actionable error messages rather than letting bad data produce
// silently wrong deletion plans.
import type { Artifact, RetentionPolicy } from "./types";

export function validatePolicy(policy: RetentionPolicy): void {
  if (policy.maxAgeInDays !== undefined && policy.maxAgeInDays < 0) {
    throw new Error(`maxAgeInDays must be >= 0, got ${policy.maxAgeInDays}`);
  }
  if (policy.keepLatestN !== undefined && policy.keepLatestN < 0) {
    throw new Error(`keepLatestN must be >= 0, got ${policy.keepLatestN}`);
  }
  if (policy.maxTotalSizeInBytes !== undefined && policy.maxTotalSizeInBytes < 0) {
    throw new Error(`maxTotalSizeInBytes must be >= 0, got ${policy.maxTotalSizeInBytes}`);
  }
}

export function validateArtifacts(artifacts: Artifact[]): void {
  const seenIds = new Set<string>();
  for (const artifact of artifacts) {
    if (!artifact.id) {
      throw new Error("artifact is missing a non-empty id");
    }
    if (seenIds.has(artifact.id)) {
      throw new Error(`duplicate artifact id: "${artifact.id}"`);
    }
    seenIds.add(artifact.id);

    if (artifact.sizeInBytes < 0) {
      throw new Error(
        `artifact "${artifact.id}" has invalid sizeInBytes: ${artifact.sizeInBytes} (must be >= 0)`,
      );
    }
    if (Number.isNaN(artifact.createdAt.getTime())) {
      throw new Error(`artifact "${artifact.id}" has an invalid createdAt date`);
    }
  }
}
