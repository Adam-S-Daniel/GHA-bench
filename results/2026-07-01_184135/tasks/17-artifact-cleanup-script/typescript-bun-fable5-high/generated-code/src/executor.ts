import type { Artifact, DeletionPlan, DoomedArtifact } from "./types";

/**
 * Deletes one artifact. In production this would call the artifact-store API;
 * in this project (mock data) the CLI injects a logger-backed mock, and the
 * tests inject recording/failing mocks.
 */
export type ArtifactDeleter = (artifact: Artifact) => Promise<void>;

export interface ExecutionResult {
  /** Artifacts actually deleted (empty in dry-run mode). */
  deleted: DoomedArtifact[];
  /** Artifacts that would have been deleted but were spared by dry-run. */
  skippedDryRun: DoomedArtifact[];
}

/**
 * Carries out (or, in dry-run mode, merely reports) a deletion plan.
 * Deletions run sequentially in plan order so failures are deterministic;
 * any deleter error is re-thrown with the artifact's identity attached.
 */
export async function executePlan(
  plan: DeletionPlan,
  deleter: ArtifactDeleter,
): Promise<ExecutionResult> {
  if (plan.dryRun) {
    return { deleted: [], skippedDryRun: [...plan.toDelete] };
  }

  const deleted: DoomedArtifact[] = [];
  for (const artifact of plan.toDelete) {
    try {
      await deleter(artifact);
    } catch (err) {
      throw new Error(
        `failed to delete artifact "${artifact.name}" (id=${artifact.id}): ${(err as Error).message}`,
      );
    }
    deleted.push(artifact);
  }
  return { deleted, skippedDryRun: [] };
}
