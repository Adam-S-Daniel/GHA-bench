/**
 * Pure decision logic for the artifact cleanup planner.
 *
 * `planCleanup` takes a list of artifacts + a retention policy and returns a
 * fully-resolved deletion plan. It performs no I/O so it is trivially testable.
 *
 * Policy semantics (rules are additive — an artifact is deleted if ANY enabled
 * rule selects it):
 *   1. max-age           — delete artifacts strictly older than `maxAgeDays`.
 *   2. keep-latest-n     — per workflow run id, keep the N newest; delete the rest.
 *   3. max-total-size    — if the artifacts surviving rules 1+2 still exceed the
 *                          size cap, delete the OLDEST survivors until they fit.
 *
 * Rules are evaluated in the order above so that the size cap only ever needs to
 * remove artifacts that the cheaper age/keep rules did not already remove.
 */

import type {
  Artifact,
  ArtifactDecision,
  DeletionPlan,
  DeletionReason,
  PlanOptions,
  RetentionPolicy,
} from "./types.ts";

const MS_PER_DAY = 24 * 60 * 60 * 1000;

/** Stable, human-meaningful ordering of reason codes for any decision. */
const REASON_ORDER: DeletionReason[] = ["max-age", "keep-latest-n", "max-total-size"];

/**
 * Validate a single artifact, throwing an `Error` with a descriptive message
 * (including the offending index) when something is wrong. Returns the parsed
 * creation timestamp (ms since epoch) so callers don't re-parse.
 */
function validateArtifact(artifact: Artifact, index: number): number {
  const where = `artifact at index ${index}`;
  if (typeof artifact !== "object" || artifact === null) {
    throw new Error(`${where} is not an object`);
  }
  if (typeof artifact.id !== "string" || artifact.id.trim() === "") {
    throw new Error(`${where} has a missing or empty "id"`);
  }
  if (typeof artifact.name !== "string") {
    throw new Error(`${where} (id="${artifact.id}") has a non-string "name"`);
  }
  if (
    typeof artifact.sizeBytes !== "number" ||
    !Number.isFinite(artifact.sizeBytes) ||
    artifact.sizeBytes < 0
  ) {
    throw new Error(
      `${where} (id="${artifact.id}") has an invalid "sizeBytes": ` +
        `${String(artifact.sizeBytes)} (must be a finite number >= 0)`,
    );
  }
  if (typeof artifact.workflowRunId !== "string" || artifact.workflowRunId.trim() === "") {
    throw new Error(`${where} (id="${artifact.id}") has a missing or empty "workflowRunId"`);
  }
  const ts = Date.parse(artifact.createdAt);
  if (typeof artifact.createdAt !== "string" || Number.isNaN(ts)) {
    throw new Error(
      `${where} (id="${artifact.id}") has an unparseable "createdAt": ` +
        `${JSON.stringify(artifact.createdAt)}`,
    );
  }
  return ts;
}

/** Validate the policy object, throwing on out-of-range or wrong-typed fields. */
export function validatePolicy(policy: RetentionPolicy): void {
  if (typeof policy !== "object" || policy === null) {
    throw new Error(`policy must be an object, got ${String(policy)}`);
  }
  const nonNeg = (value: number | undefined, field: string): void => {
    if (value === undefined) return;
    if (typeof value !== "number" || !Number.isFinite(value) || value < 0) {
      throw new Error(`policy.${field} must be a finite number >= 0, got ${String(value)}`);
    }
  };
  nonNeg(policy.maxAgeDays, "maxAgeDays");
  nonNeg(policy.maxTotalSizeBytes, "maxTotalSizeBytes");
  if (policy.keepLatestNPerWorkflow !== undefined) {
    const n = policy.keepLatestNPerWorkflow;
    if (typeof n !== "number" || !Number.isInteger(n) || n < 0) {
      throw new Error(
        `policy.keepLatestNPerWorkflow must be an integer >= 0, got ${String(n)}`,
      );
    }
  }
}

/**
 * Validate a list of artifacts: each artifact is well-formed and all ids are
 * unique. Returns a parallel array of parsed timestamps for convenience.
 */
export function validateArtifacts(artifacts: Artifact[]): number[] {
  if (!Array.isArray(artifacts)) {
    throw new Error(`expected an array of artifacts, got ${typeof artifacts}`);
  }
  const seen = new Set<string>();
  const timestamps: number[] = [];
  artifacts.forEach((artifact, index) => {
    const ts = validateArtifact(artifact, index);
    if (seen.has(artifact.id)) {
      throw new Error(`duplicate artifact id "${artifact.id}" at index ${index}`);
    }
    seen.add(artifact.id);
    timestamps.push(ts);
  });
  return timestamps;
}

/**
 * Compute the deletion plan for `artifacts` under `policy`.
 *
 * @throws Error when the artifacts or policy are invalid.
 */
export function planCleanup(
  artifacts: Artifact[],
  policy: RetentionPolicy,
  options: PlanOptions = {},
): DeletionPlan {
  validatePolicy(policy);
  const timestamps = validateArtifacts(artifacts);

  const now = options.now ?? new Date();
  const nowMs = now.getTime();
  if (Number.isNaN(nowMs)) {
    throw new Error("options.now is an invalid Date");
  }
  const dryRun = options.dryRun ?? false;

  // Reasons accumulate per artifact id; presence of any reason ⇒ delete.
  const reasonsById = new Map<string, Set<DeletionReason>>();
  artifacts.forEach((a) => reasonsById.set(a.id, new Set()));

  // Precompute ages so each rule and the final summary share one source.
  const ageDaysById = new Map<string, number>();
  artifacts.forEach((a, i) => {
    ageDaysById.set(a.id, (nowMs - timestamps[i]!) / MS_PER_DAY);
  });

  const mark = (id: string, reason: DeletionReason): void => {
    reasonsById.get(id)!.add(reason);
  };
  const isDeleted = (id: string): boolean => reasonsById.get(id)!.size > 0;

  // ---- Rule 1: max age -----------------------------------------------------
  if (policy.maxAgeDays !== undefined) {
    artifacts.forEach((a) => {
      if (ageDaysById.get(a.id)! > policy.maxAgeDays!) {
        mark(a.id, "max-age");
      }
    });
  }

  // ---- Rule 2: keep latest N per workflow ----------------------------------
  if (policy.keepLatestNPerWorkflow !== undefined) {
    const groups = new Map<string, Artifact[]>();
    artifacts.forEach((a) => {
      const group = groups.get(a.workflowRunId) ?? [];
      group.push(a);
      groups.set(a.workflowRunId, group);
    });
    for (const group of groups.values()) {
      // Newest first; tie-break by id so ordering is deterministic.
      const sorted = [...group].sort((x, y) => {
        const dt = Date.parse(y.createdAt) - Date.parse(x.createdAt);
        return dt !== 0 ? dt : x.id.localeCompare(y.id);
      });
      sorted.slice(policy.keepLatestNPerWorkflow).forEach((a) => mark(a.id, "keep-latest-n"));
    }
  }

  // ---- Rule 3: max total size (over the survivors of rules 1+2) ------------
  if (policy.maxTotalSizeBytes !== undefined) {
    const survivors = artifacts.filter((a) => !isDeleted(a.id));
    let retainedSize = survivors.reduce((sum, a) => sum + a.sizeBytes, 0);
    if (retainedSize > policy.maxTotalSizeBytes) {
      // Delete oldest survivors first (FIFO retention) until under the cap.
      const oldestFirst = [...survivors].sort((x, y) => {
        const dt = Date.parse(x.createdAt) - Date.parse(y.createdAt);
        return dt !== 0 ? dt : x.id.localeCompare(y.id);
      });
      for (const a of oldestFirst) {
        if (retainedSize <= policy.maxTotalSizeBytes) break;
        mark(a.id, "max-total-size");
        retainedSize -= a.sizeBytes;
      }
    }
  }

  // ---- Build decisions (preserving input order) and the summary ------------
  const decisions: ArtifactDecision[] = artifacts.map((a) => {
    const reasonSet = reasonsById.get(a.id)!;
    const reasons = REASON_ORDER.filter((r) => reasonSet.has(r));
    return {
      artifact: a,
      delete: reasons.length > 0,
      reasons,
      ageDays: ageDaysById.get(a.id)!,
    };
  });

  const totalSizeBytes = artifacts.reduce((sum, a) => sum + a.sizeBytes, 0);
  const deleted = decisions.filter((d) => d.delete);
  const spaceReclaimedBytes = deleted.reduce((sum, d) => sum + d.artifact.sizeBytes, 0);

  return {
    decisions,
    summary: {
      totalArtifacts: artifacts.length,
      retainedCount: artifacts.length - deleted.length,
      deletedCount: deleted.length,
      totalSizeBytes,
      retainedSizeBytes: totalSizeBytes - spaceReclaimedBytes,
      spaceReclaimedBytes,
    },
    dryRun,
    policy,
  };
}
