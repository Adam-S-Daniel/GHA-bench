/**
 * License policy: loading config and classifying a license.
 */
import type { ComplianceStatus, LicensePolicy } from "./types.ts";

/** Case-insensitive membership test against a list of license ids. */
function listIncludes(list: string[], license: string): boolean {
  const needle = license.toLowerCase();
  return list.some((entry) => entry.toLowerCase() === needle);
}

/**
 * Classify a resolved license against the policy.
 *
 * Precedence: deny-list beats allow-list (an explicitly forbidden license is
 * never approved). A null license, or one on neither list, is "unknown".
 */
export function classify(
  license: string | null,
  policy: LicensePolicy,
): ComplianceStatus {
  if (license === null) return "unknown";
  if (listIncludes(policy.deny, license)) return "denied";
  if (listIncludes(policy.allow, license)) return "approved";
  return "unknown";
}

/**
 * Parse and validate a policy config from a JSON string. `allow` and `deny`
 * are required arrays; `failOnUnknown` defaults to false.
 */
export function loadPolicy(json: string): LicensePolicy {
  let raw: unknown;
  try {
    raw = JSON.parse(json);
  } catch (err) {
    const reason = err instanceof Error ? err.message : String(err);
    throw new Error(`Failed to parse policy config: ${reason}`);
  }

  if (typeof raw !== "object" || raw === null) {
    throw new Error("Failed to parse policy config: expected a JSON object");
  }

  const record = raw as Record<string, unknown>;
  if (!Array.isArray(record.allow)) {
    throw new Error('Invalid policy config: "allow" must be an array of license ids');
  }
  if (!Array.isArray(record.deny)) {
    throw new Error('Invalid policy config: "deny" must be an array of license ids');
  }

  return {
    allow: record.allow.map(String),
    deny: record.deny.map(String),
    failOnUnknown: record.failOnUnknown === true,
  };
}
