// Executes a CleanupPlan against a real (or mock) deletion callback.
//
// In dry-run mode the callback is never invoked — the plan's deletions are
// simply reported as "would delete". In wet mode each planned deletion is
// attempted independently: one failing deletion is recorded and does not
// prevent the remaining artifacts from being deleted.
import type { CleanupPlan, ExecutionResult } from "./types";

export interface ExecuteOptions {
  dryRun: boolean;
}

export async function executeCleanupPlan(
  plan: CleanupPlan,
  deleteArtifact: (artifact: CleanupPlan["deletions"][number]["artifact"]) => void | Promise<void>,
  options: ExecuteOptions,
): Promise<ExecutionResult> {
  const deletedIds: string[] = [];
  const failures: ExecutionResult["failures"] = [];

  if (options.dryRun) {
    return {
      dryRun: true,
      deletedIds: plan.deletions.map((d) => d.artifact.id),
      failures: [],
    };
  }

  for (const { artifact } of plan.deletions) {
    try {
      await deleteArtifact(artifact);
      deletedIds.push(artifact.id);
    } catch (error) {
      failures.push({
        artifactId: artifact.id,
        message: error instanceof Error ? error.message : String(error),
      });
    }
  }

  return { dryRun: false, deletedIds, failures };
}
