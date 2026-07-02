import type { Artifact, RetentionPolicy } from "./types";

/**
 * Parsing/validation for the two JSON inputs the CLI consumes: the artifact
 * list and the policy config. All errors are thrown as plain Errors with
 * messages specific enough to fix the input without reading the source.
 */

/** Policy config file shape: retention knobs plus run options. */
export interface PolicyConfig {
  policy: RetentionPolicy;
  /** Optional deterministic "now"; defaults to the real clock in the CLI. */
  referenceDate?: Date;
  dryRun?: boolean;
}

const POLICY_KEYS = new Set([
  "maxAgeDays",
  "maxTotalSizeBytes",
  "keepLatestPerWorkflow",
  "referenceDate",
  "dryRun",
]);

function parseJson(text: string, what: string): unknown {
  try {
    return JSON.parse(text);
  } catch (err) {
    throw new Error(`${what} is invalid JSON: ${(err as Error).message}`);
  }
}

function isFiniteNumber(v: unknown): v is number {
  return typeof v === "number" && Number.isFinite(v);
}

/** Parses and validates the artifact list. Throws on any structural problem. */
export function parseArtifactsJson(text: string): Artifact[] {
  const data = parseJson(text, "artifacts JSON");
  if (!Array.isArray(data)) {
    throw new Error("artifacts JSON must be an array");
  }

  return data.map((raw, i) => {
    if (typeof raw !== "object" || raw === null) {
      throw new Error(`artifact at index ${i} must be an object`);
    }
    const obj = raw as Record<string, unknown>;
    const require = (field: string, ok: boolean): void => {
      if (!ok) {
        throw new Error(`artifact at index ${i} is missing or has invalid "${field}"`);
      }
    };
    require("id", isFiniteNumber(obj.id));
    require("name", typeof obj.name === "string" && obj.name.length > 0);
    require("sizeBytes", isFiniteNumber(obj.sizeBytes));
    require("createdAt", typeof obj.createdAt === "string");
    require("workflowRunId", isFiniteNumber(obj.workflowRunId));

    return {
      id: obj.id as number,
      name: obj.name as string,
      sizeBytes: obj.sizeBytes as number,
      createdAt: obj.createdAt as string,
      workflowRunId: obj.workflowRunId as number,
    };
  });
}

/** Parses and validates the policy config file. */
export function parsePolicyJson(text: string): PolicyConfig {
  const data = parseJson(text, "policy JSON");
  if (typeof data !== "object" || data === null || Array.isArray(data)) {
    throw new Error("policy JSON must be an object");
  }
  const obj = data as Record<string, unknown>;

  for (const key of Object.keys(obj)) {
    if (!POLICY_KEYS.has(key)) {
      throw new Error(
        `unknown policy key "${key}" (expected one of: ${[...POLICY_KEYS].join(", ")})`,
      );
    }
  }

  const policy: RetentionPolicy = {};
  for (const key of ["maxAgeDays", "maxTotalSizeBytes", "keepLatestPerWorkflow"] as const) {
    const v = obj[key];
    if (v === undefined) continue;
    if (!isFiniteNumber(v)) {
      throw new Error(`policy key "${key}" must be a number, got ${JSON.stringify(v)}`);
    }
    policy[key] = v;
  }

  let referenceDate: Date | undefined;
  if (obj.referenceDate !== undefined) {
    if (typeof obj.referenceDate !== "string" || Number.isNaN(Date.parse(obj.referenceDate))) {
      throw new Error(`invalid referenceDate: ${JSON.stringify(obj.referenceDate)}`);
    }
    referenceDate = new Date(obj.referenceDate);
  }

  let dryRun: boolean | undefined;
  if (obj.dryRun !== undefined) {
    if (typeof obj.dryRun !== "boolean") {
      throw new Error(`policy key "dryRun" must be a boolean, got ${JSON.stringify(obj.dryRun)}`);
    }
    dryRun = obj.dryRun;
  }

  return { policy, referenceDate, dryRun };
}
