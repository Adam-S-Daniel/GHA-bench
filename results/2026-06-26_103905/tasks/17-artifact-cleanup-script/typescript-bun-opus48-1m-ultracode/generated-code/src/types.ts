/**
 * Core domain types for the artifact cleanup planner.
 *
 * The design keeps the *decision logic* (which artifacts to delete) entirely
 * separate from I/O (reading fixtures, printing reports). Everything in this
 * file is a plain data shape so the planner can be unit-tested in isolation.
 */

/** A CI artifact with the metadata the retention policies operate on. */
export interface Artifact {
  /** Stable unique identifier for the artifact. */
  id: string;
  /** Human-readable artifact name (need not be unique). */
  name: string;
  /** Size of the artifact in bytes. Must be >= 0. */
  sizeBytes: number;
  /** Creation timestamp as an ISO-8601 string (e.g. "2025-12-31T00:00:00Z"). */
  createdAt: string;
  /** Identifier of the workflow run that produced the artifact. */
  workflowRunId: string;
}

/**
 * Retention policy. Every field is optional; an omitted field means that
 * particular rule is not enforced. Combining rules is additive — an artifact is
 * deleted if *any* enabled rule selects it for deletion.
 */
export interface RetentionPolicy {
  /** Delete artifacts strictly older than this many days. */
  maxAgeDays?: number;
  /**
   * Cap on the total size (bytes) of *retained* artifacts. When the artifacts
   * that survive the other rules still exceed this cap, the oldest are deleted
   * until the retained total fits under the cap.
   */
  maxTotalSizeBytes?: number;
  /**
   * Keep only the N most-recently-created artifacts per workflow run id; older
   * artifacts in the same group are deleted.
   */
  keepLatestNPerWorkflow?: number;
}

/** Options controlling how the plan is produced. */
export interface PlanOptions {
  /** Reference "now" for age calculations. Injected for deterministic tests. */
  now?: Date;
  /** When true, the plan is marked as a dry run (no deletions would happen). */
  dryRun?: boolean;
}

/** The reason codes a policy can attach to a deletion decision. */
export type DeletionReason = "max-age" | "max-total-size" | "keep-latest-n";

/** The verdict for a single artifact. */
export interface ArtifactDecision {
  artifact: Artifact;
  /** True when the artifact is selected for deletion. */
  delete: boolean;
  /** The policy reason codes that selected this artifact (empty when retained). */
  reasons: DeletionReason[];
  /** Age of the artifact in whole-ish days relative to the reference "now". */
  ageDays: number;
}

/** Aggregate statistics for a deletion plan. */
export interface PlanSummary {
  totalArtifacts: number;
  retainedCount: number;
  deletedCount: number;
  /** Sum of sizes of all input artifacts. */
  totalSizeBytes: number;
  /** Sum of sizes of artifacts that will be kept. */
  retainedSizeBytes: number;
  /** Sum of sizes of artifacts that will be deleted (== space reclaimed). */
  spaceReclaimedBytes: number;
}

/** The full output of the planner. */
export interface DeletionPlan {
  decisions: ArtifactDecision[];
  summary: PlanSummary;
  dryRun: boolean;
  /** The policy that produced this plan (echoed for reporting/auditing). */
  policy: RetentionPolicy;
}
