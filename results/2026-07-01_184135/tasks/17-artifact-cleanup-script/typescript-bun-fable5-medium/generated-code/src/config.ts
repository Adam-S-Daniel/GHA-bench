/**
 * Config loading: parse and validate the artifacts/policy JSON files.
 * Validation is done by hand (no runtime dependency) with precise error
 * messages naming the file and offending field.
 */
import type { Artifact, RetentionPolicy } from "./cleanup.ts";

/** Read a file and parse it as JSON, wrapping failures in clear messages. */
async function readJson(path: string, what: string): Promise<unknown> {
  let text: string;
  try {
    text = await Bun.file(path).text();
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    throw new Error(`cannot read ${what} file "${path}": ${message}`);
  }
  try {
    return JSON.parse(text);
  } catch {
    throw new Error(`${what} file "${path}" contains invalid JSON`);
  }
}

/** Assert a field is a number of the given object, with an indexed context label. */
function requireNumber(obj: Record<string, unknown>, field: string, ctx: string): number {
  const value = obj[field];
  if (typeof value !== "number") {
    throw new Error(`${ctx}: "${field}" must be a number, got ${JSON.stringify(value)}`);
  }
  return value;
}

function requireString(obj: Record<string, unknown>, field: string, ctx: string): string {
  const value = obj[field];
  if (typeof value !== "string") {
    throw new Error(`${ctx}: "${field}" must be a string, got ${JSON.stringify(value)}`);
  }
  return value;
}

/** Load and validate an artifacts JSON file (an array of Artifact objects). */
export async function loadArtifactsFile(path: string): Promise<Artifact[]> {
  const data = await readJson(path, "artifacts");
  if (!Array.isArray(data)) {
    throw new Error(`artifacts file "${path}" must contain a JSON array`);
  }
  return data.map((entry: unknown, i: number): Artifact => {
    if (typeof entry !== "object" || entry === null) {
      throw new Error(`artifact at index ${i}: must be an object`);
    }
    const obj = entry as Record<string, unknown>;
    const ctx = `artifact at index ${i}`;
    return {
      name: requireString(obj, "name", ctx),
      sizeBytes: requireNumber(obj, "sizeBytes", ctx),
      createdAt: requireString(obj, "createdAt", ctx),
      workflowRunId: requireNumber(obj, "workflowRunId", ctx),
    };
  });
}

/** Load and validate a retention policy JSON file. Absent fields skip that rule. */
export async function loadPolicyFile(path: string): Promise<RetentionPolicy> {
  const data = await readJson(path, "policy");
  if (typeof data !== "object" || data === null || Array.isArray(data)) {
    throw new Error(`policy file "${path}" must contain a JSON object`);
  }
  const obj = data as Record<string, unknown>;
  const ctx = `policy file "${path}"`;
  const policy: RetentionPolicy = {};
  if (obj.maxAgeDays !== undefined) {
    policy.maxAgeDays = requireNumber(obj, "maxAgeDays", ctx);
  }
  if (obj.keepLatestPerWorkflow !== undefined) {
    policy.keepLatestPerWorkflow = requireNumber(obj, "keepLatestPerWorkflow", ctx);
  }
  if (obj.maxTotalSizeBytes !== undefined) {
    policy.maxTotalSizeBytes = requireNumber(obj, "maxTotalSizeBytes", ctx);
  }
  if (obj.dryRun !== undefined) {
    if (typeof obj.dryRun !== "boolean") {
      throw new Error(`${ctx}: "dryRun" must be a boolean, got ${JSON.stringify(obj.dryRun)}`);
    }
    policy.dryRun = obj.dryRun;
  }
  return policy;
}
