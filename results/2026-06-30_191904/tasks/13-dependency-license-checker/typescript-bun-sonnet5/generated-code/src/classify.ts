import type { ComplianceStatus, LicenseConfig } from "./types";

/**
 * Classifies a resolved license against the allow/deny policy.
 * A license present on both lists is treated as denied: compliance
 * gates should fail closed rather than silently approve a conflict.
 */
export function classifyLicense(
  license: string | null,
  config: LicenseConfig,
): ComplianceStatus {
  if (!license) return "unknown";

  const normalized = license.toLowerCase();
  const denylist = config.denylist.map((entry) => entry.toLowerCase());
  const allowlist = config.allowlist.map((entry) => entry.toLowerCase());

  if (denylist.includes(normalized)) return "denied";
  if (allowlist.includes(normalized)) return "approved";
  return "unknown";
}
