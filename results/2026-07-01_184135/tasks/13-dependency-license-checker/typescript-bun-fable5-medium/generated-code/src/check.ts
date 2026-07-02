import type { LicenseConfig, LicenseStatus } from "./types";

/**
 * Classify a license against the allow/deny configuration.
 * The deny-list always wins over the allow-list; an unresolved or
 * unlisted license is "unknown" (it is neither approved nor denied).
 */
export function checkLicense(
  license: string | undefined,
  config: LicenseConfig,
): LicenseStatus {
  if (license === undefined) return "unknown";
  if (config.deny.includes(license)) return "denied";
  if (config.allow.includes(license)) return "approved";
  return "unknown";
}
