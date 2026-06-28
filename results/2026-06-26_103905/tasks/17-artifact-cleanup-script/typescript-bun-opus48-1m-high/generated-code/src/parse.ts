/**
 * Input parsing and validation for the cleanup CLI.
 *
 * The CLI receives untrusted JSON (a fixture file or piped data). This module
 * turns that `unknown` blob into a strongly-typed, validated document or throws
 * an Error with a message precise enough to fix the input. All validation lives
 * here so the pure planner in cleanup.ts can trust its inputs.
 */
import type { Artifact, RetentionPolicy } from "./cleanup.ts";

/** A fully validated cleanup request ready to hand to planCleanup. */
export interface CleanupInput {
  /** Reference time for age calculations, or undefined to use the wall clock. */
  now: Date | undefined;
  policy: RetentionPolicy;
  artifacts: Artifact[];
}

/** Narrow `unknown` to a plain (non-array, non-null) object. */
function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/**
 * Validate one optional, non-negative numeric policy field.
 * Returns the number when present, or undefined when absent.
 */
function optionalNonNegative(
  source: Record<string, unknown>,
  field: string,
): number | undefined {
  const value = source[field];
  if (value === undefined || value === null) return undefined;
  if (typeof value !== "number" || !Number.isFinite(value) || value < 0) {
    throw new Error(`policy.${field} must be a non-negative number`);
  }
  return value;
}

/** Validate a single artifact at a known index, returning a typed Artifact. */
function parseArtifact(value: unknown, index: number): Artifact {
  const where = `artifacts[${index}]`;
  if (!isPlainObject(value)) {
    throw new Error(`${where} must be an object`);
  }

  const { name, sizeBytes, createdAt, workflowRunId } = value;

  if (typeof name !== "string" || name.length === 0) {
    throw new Error(`${where}.name must be a non-empty string`);
  }
  if (typeof sizeBytes !== "number" || !Number.isFinite(sizeBytes) || sizeBytes < 0) {
    throw new Error(`${where}.sizeBytes must be a non-negative number`);
  }
  if (typeof createdAt !== "string" || Number.isNaN(new Date(createdAt).getTime())) {
    throw new Error(`${where}.createdAt must be a valid ISO-8601 timestamp`);
  }
  if (typeof workflowRunId !== "number" || !Number.isInteger(workflowRunId)) {
    throw new Error(`${where}.workflowRunId must be an integer`);
  }

  return { name, sizeBytes, createdAt, workflowRunId };
}

/**
 * Parse and validate a raw cleanup-input document.
 * @throws Error with a human-actionable message on any invalid field.
 */
export function parseCleanupInput(raw: unknown): CleanupInput {
  if (!isPlainObject(raw)) {
    throw new Error("input must be a JSON object with an 'artifacts' array");
  }

  if (!Array.isArray(raw.artifacts)) {
    throw new Error('input "artifacts" must be an array');
  }
  const artifacts = raw.artifacts.map((a, i) => parseArtifact(a, i));

  // Policy is optional; absent means "no rules".
  let policy: RetentionPolicy = {};
  if (raw.policy !== undefined && raw.policy !== null) {
    if (!isPlainObject(raw.policy)) {
      throw new Error("input 'policy' must be an object when present");
    }
    policy = {
      maxAgeDays: optionalNonNegative(raw.policy, "maxAgeDays"),
      maxTotalSizeBytes: optionalNonNegative(raw.policy, "maxTotalSizeBytes"),
      keepLatestNPerWorkflow: optionalNonNegative(raw.policy, "keepLatestNPerWorkflow"),
    };
  }

  // 'now' is optional; when present it must be a valid timestamp.
  let now: Date | undefined;
  if (raw.now !== undefined && raw.now !== null) {
    if (typeof raw.now !== "string" || Number.isNaN(new Date(raw.now).getTime())) {
      throw new Error("input 'now' must be a valid ISO-8601 timestamp");
    }
    now = new Date(raw.now);
  }

  return { now, policy, artifacts };
}
