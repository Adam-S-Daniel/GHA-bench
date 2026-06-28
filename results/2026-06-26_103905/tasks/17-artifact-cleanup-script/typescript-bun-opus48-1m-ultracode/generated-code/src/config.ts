/**
 * Parsing/validation of the on-disk cleanup config (the "fixture" format).
 *
 * A config file is JSON shaped like:
 *   {
 *     "now": "2026-01-01T00:00:00Z",          // optional reference time
 *     "policy": { "maxAgeDays": 30, ... },      // optional, defaults to {}
 *     "artifacts": [ { id, name, sizeBytes, createdAt, workflowRunId }, ... ]
 *   }
 *
 * `parseConfig` accepts already-parsed JSON (so it can be unit-tested without
 * touching the filesystem) and returns strongly-typed, validated data.
 */

import type { Artifact, RetentionPolicy } from "./types.ts";
import { validateArtifacts, validatePolicy } from "./cleanup.ts";

/** The validated, ready-to-use shape produced from a config file. */
export interface CleanupConfig {
  artifacts: Artifact[];
  policy: RetentionPolicy;
  /** Reference "now" if the config pinned one, else undefined. */
  now?: Date;
}

/** Validate and normalise a raw (JSON-parsed) config value. */
export function parseConfig(raw: unknown): CleanupConfig {
  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) {
    throw new Error(`config must be an object, got ${Array.isArray(raw) ? "array" : typeof raw}`);
  }
  const obj = raw as Record<string, unknown>;

  if (!("artifacts" in obj)) {
    throw new Error('config is missing the required "artifacts" array');
  }
  const artifacts = obj.artifacts as Artifact[];
  // Reuse the planner's validator so config + planner agree on what is valid.
  validateArtifacts(artifacts);

  const policy: RetentionPolicy = (obj.policy as RetentionPolicy | undefined) ?? {};
  validatePolicy(policy);

  let now: Date | undefined;
  if (obj.now !== undefined) {
    if (typeof obj.now !== "string" || Number.isNaN(Date.parse(obj.now))) {
      throw new Error(`config "now" must be a valid ISO date string, got ${JSON.stringify(obj.now)}`);
    }
    now = new Date(obj.now);
  }

  return { artifacts, policy, now };
}
