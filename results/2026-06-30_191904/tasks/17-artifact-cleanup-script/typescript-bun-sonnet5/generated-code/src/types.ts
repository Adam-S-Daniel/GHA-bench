// Shared type definitions for the artifact cleanup script.

/** A single CI artifact as reported by the artifact store (e.g. GitHub Actions). */
export interface Artifact {
  /** Stable unique identifier for the artifact. */
  id: string;
  /** Human readable artifact name, e.g. "build-output". */
  name: string;
  /** Size of the artifact in bytes. */
  sizeInBytes: number;
  /** When the artifact was created/uploaded. */
  createdAt: Date;
  /** Identifier of the workflow (e.g. "ci.yml") that produced this artifact. */
  workflowId: string;
  /** Identifier of the specific workflow run that produced this artifact. */
  workflowRunId: string;
}

/** Reasons an artifact was selected for deletion, in the order policies are evaluated. */
export type DeletionReason = "max-age" | "keep-latest-n" | "max-total-size";

/** Configurable retention policy applied to a set of artifacts. */
export interface RetentionPolicy {
  /** Delete artifacts older than this many days. Omit/undefined disables the rule. */
  maxAgeInDays?: number;
  /** Cap on the combined size (bytes) of retained artifacts. Omit/undefined disables the rule. */
  maxTotalSizeInBytes?: number;
  /** Keep only the N most recently created artifacts per workflowId. Omit/undefined disables the rule. */
  keepLatestN?: number;
}

/** An artifact paired with why it was chosen for deletion. */
export interface PlannedDeletion {
  artifact: Artifact;
  reason: DeletionReason;
}

/** Aggregate statistics describing the outcome of a cleanup plan. */
export interface CleanupSummary {
  totalArtifacts: number;
  retainedCount: number;
  deletedCount: number;
  totalSizeInBytes: number;
  retainedSizeInBytes: number;
  /** Bytes that would be/were reclaimed by deleting the planned artifacts. */
  reclaimedSizeInBytes: number;
  deletedByReason: Record<DeletionReason, number>;
}

/** The full result of running the retention policies over a set of artifacts. */
export interface CleanupPlan {
  retained: Artifact[];
  deletions: PlannedDeletion[];
  summary: CleanupSummary;
}

/** A single artifact whose deletion callback threw. */
export interface DeletionFailure {
  artifactId: string;
  message: string;
}

/** Outcome of running a CleanupPlan through the executor. */
export interface ExecutionResult {
  dryRun: boolean;
  /** IDs successfully deleted (or that would be deleted, in dry-run mode). */
  deletedIds: string[];
  failures: DeletionFailure[];
}
