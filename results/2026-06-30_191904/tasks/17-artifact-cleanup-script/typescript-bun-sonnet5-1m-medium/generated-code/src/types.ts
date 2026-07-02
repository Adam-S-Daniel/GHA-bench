// Shared type definitions for the artifact cleanup script.

/** A single CI artifact as reported by the GitHub Actions API (mocked in tests/fixtures). */
export interface Artifact {
  id: string;
  name: string;
  /** Size in bytes. */
  sizeInBytes: number;
  /** ISO-8601 creation timestamp. */
  createdAt: string;
  workflowRunId: string;
  /** Workflow name/id the run belongs to, used for per-workflow keep-latest-N. */
  workflowName: string;
}

/** Retention policy knobs. All fields are optional; omitted fields are not enforced. */
export interface RetentionPolicy {
  /** Maximum age in days. Artifacts older than this are eligible for deletion. */
  maxAgeDays?: number;
  /** Maximum total size (bytes) allowed across all retained artifacts. */
  maxTotalSizeBytes?: number;
  /** Number of most-recent artifacts to always keep per workflowName, regardless of age/size. */
  keepLatestPerWorkflow?: number;
}

export interface ArtifactDecision {
  artifact: Artifact;
  /** Why the artifact was marked for deletion or retention. */
  reason: string;
}

export interface DeletionPlan {
  /** Artifacts to delete. */
  toDelete: ArtifactDecision[];
  /** Artifacts to keep. */
  toRetain: ArtifactDecision[];
  /** Total bytes that would be reclaimed by deleting toDelete. */
  totalBytesReclaimed: number;
  /** Whether this plan was generated in dry-run mode (no actual deletion performed). */
  dryRun: boolean;
}
