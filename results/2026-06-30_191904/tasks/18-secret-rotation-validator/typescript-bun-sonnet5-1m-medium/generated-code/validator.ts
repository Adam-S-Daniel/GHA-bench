// Core rotation-validation logic: turns raw secret metadata into a classified
// status (expired / warning / ok) relative to a reference date.

import type { RotationConfig, RotationReport, SecretMeta, SecretStatus } from "./types.ts";

const MS_PER_DAY = 24 * 60 * 60 * 1000;

/** Parses an ISO date string, throwing a clear error on malformed input. */
function parseDate(dateString: string, context: string): Date {
  const parsed = new Date(dateString);
  if (Number.isNaN(parsed.getTime())) {
    throw new Error(`Invalid date "${dateString}" for ${context}`);
  }
  return parsed;
}

/**
 * Classifies a single secret's rotation urgency as of `referenceDate`.
 *
 * - expired: the rotation policy window has already elapsed (daysUntilExpiry <= 0)
 * - warning: expiry falls within `warningWindowDays` from now
 * - ok: otherwise
 */
export function classifySecret(
  secret: SecretMeta,
  referenceDate: Date,
  warningWindowDays: number,
): SecretStatus {
  const lastRotated = parseDate(secret.lastRotated, `secret "${secret.name}"`);

  const daysSinceRotation = Math.floor(
    (referenceDate.getTime() - lastRotated.getTime()) / MS_PER_DAY,
  );
  const daysUntilExpiry = secret.rotationPolicyDays - daysSinceRotation;

  let urgency: SecretStatus["urgency"];
  if (daysUntilExpiry <= 0) {
    urgency = "expired";
  } else if (daysUntilExpiry <= warningWindowDays) {
    urgency = "warning";
  } else {
    urgency = "ok";
  }

  return {
    name: secret.name,
    requiredBy: secret.requiredBy,
    lastRotated: secret.lastRotated,
    rotationPolicyDays: secret.rotationPolicyDays,
    daysSinceRotation,
    daysUntilExpiry,
    urgency,
  };
}

/**
 * Validates a full rotation config and produces a report grouping every
 * secret into expired/warning/ok buckets, sorted by urgency then most-urgent
 * first within each bucket.
 */
export function validateSecrets(config: RotationConfig, referenceDate: Date): RotationReport {
  if (!config.secrets || config.secrets.length === 0) {
    throw new Error("Invalid config: must contain at least one secret");
  }
  if (!Number.isFinite(config.warningWindowDays) || config.warningWindowDays < 0) {
    throw new Error(
      `Invalid config: warningWindowDays must be a non-negative number, got ${config.warningWindowDays}`,
    );
  }

  const report: RotationReport = {
    generatedAt: referenceDate.toISOString(),
    warningWindowDays: config.warningWindowDays,
    expired: [],
    warning: [],
    ok: [],
  };

  for (const secret of config.secrets) {
    const status = classifySecret(secret, referenceDate, config.warningWindowDays);
    report[status.urgency].push(status);
  }

  // Within each bucket, show the most urgent (soonest/most overdue) secrets first.
  const byExpiry = (a: SecretStatus, b: SecretStatus): number => a.daysUntilExpiry - b.daysUntilExpiry;
  report.expired.sort(byExpiry);
  report.warning.sort(byExpiry);
  report.ok.sort(byExpiry);

  return report;
}
