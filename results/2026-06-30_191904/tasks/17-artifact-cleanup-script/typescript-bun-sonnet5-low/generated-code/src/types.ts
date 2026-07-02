// Shared domain types for the artifact cleanup script.

/** A single CI artifact as reported by the (mocked) GitHub Actions API. */
export interface Artifact {
  id: string;
  name: string;
  /** Size in bytes. */
  sizeBytes: number;
  /** ISO 8601 creation timestamp. */
  createdAt: string;
  workflowRunId: string;
  /** Logical workflow name, used for the keep-latest-N-per-workflow rule. */
  workflowName: string;
}

/** Configuration for the retention policy evaluation. */
export interface RetentionPolicy {
  /** Delete artifacts older than this many days. */
  maxAgeDays?: number;
  /** Delete oldest artifacts once total size exceeds this many bytes. */
  maxTotalSizeBytes?: number;
  /** Always keep the N most recent artifacts per workflow, regardless of other rules. */
  keepLatestPerWorkflow?: number;
}

/** Why a given artifact was marked for deletion. */
export type DeletionReason = "max-age" | "max-total-size";

export interface ArtifactDecision {
  artifact: Artifact;
  keep: boolean;
  reason?: DeletionReason;
}

export interface CleanupSummary {
  totalArtifacts: number;
  retainedCount: number;
  deletedCount: number;
  spaceReclaimedBytes: number;
  dryRun: boolean;
}

export interface CleanupPlan {
  decisions: ArtifactDecision[];
  toDelete: Artifact[];
  toRetain: Artifact[];
  summary: CleanupSummary;
}
