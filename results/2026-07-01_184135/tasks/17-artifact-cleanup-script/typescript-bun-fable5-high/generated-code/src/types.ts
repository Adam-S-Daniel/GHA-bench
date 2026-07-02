/**
 * Core domain types for the artifact cleanup planner.
 *
 * These are defined up-front (before the implementation) so that the tests
 * written in the red phase of TDD have a stable contract to compile against.
 */

/** A single CI artifact, as returned by a (mocked) artifact-listing API. */
export interface Artifact {
  /** Unique numeric identifier of the artifact. */
  id: number;
  /** Human-readable artifact name (e.g. "build-logs"). */
  name: string;
  /** Size of the artifact in bytes. Must be a non-negative integer. */
  sizeBytes: number;
  /** ISO-8601 creation timestamp (e.g. "2026-06-01T00:00:00Z"). */
  createdAt: string;
  /** The workflow run this artifact belongs to (grouping key for keep-latest-N). */
  workflowRunId: number;
}

/** Retention policy knobs. Every field is optional; omitted policies are skipped. */
export interface RetentionPolicy {
  /** Delete artifacts strictly older than this many days (relative to the reference date). */
  maxAgeDays?: number;
  /** After all other policies, evict oldest retained artifacts until total size <= this cap. */
  maxTotalSizeBytes?: number;
  /** Within each workflow run, keep only the N most recent artifacts. */
  keepLatestPerWorkflow?: number;
}

/** An artifact marked for deletion, annotated with the policies that doomed it. */
export interface DoomedArtifact extends Artifact {
  /** Which policy rules matched (e.g. ["max-age", "keep-latest-per-workflow"]). */
  reasons: string[];
}

/** Aggregate numbers for reporting. */
export interface PlanSummary {
  totalArtifacts: number;
  retainedCount: number;
  deletedCount: number;
  /** Sum of sizeBytes over deleted artifacts. */
  spaceReclaimedBytes: number;
  /** Sum of sizeBytes over retained artifacts. */
  retainedSizeBytes: number;
}

/** The full deletion plan produced by the planner. */
export interface DeletionPlan {
  toDelete: DoomedArtifact[];
  toRetain: Artifact[];
  summary: PlanSummary;
  /** Reference "now" used for age computations (ISO-8601). */
  referenceDate: string;
  dryRun: boolean;
}

/** Options accepted by the planner. */
export interface PlanOptions {
  /** The instant to treat as "now" — injected for deterministic tests. */
  referenceDate: Date;
  dryRun?: boolean;
}
