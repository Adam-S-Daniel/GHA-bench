/**
 * Report generation: evaluate all secrets and group them by urgency.
 */
import type { RotationReport, SecretConfig, SecretStatus, Urgency } from "./types";
import { evaluateSecret } from "./validator";

export interface ReportOptions {
  /** ISO date (YYYY-MM-DD) to evaluate against. */
  referenceDate: string;
  /** Secrets expiring within this many days are flagged as warnings. */
  warningWindowDays: number;
}

/** Evaluate every secret and build the grouped rotation report. */
export function generateReport(
  secrets: SecretConfig[],
  options: ReportOptions,
): RotationReport {
  const { referenceDate, warningWindowDays } = options;
  if (!Number.isInteger(warningWindowDays) || warningWindowDays <= 0) {
    throw new Error(
      `warning window must be a positive integer (got ${warningWindowDays})`,
    );
  }

  const groups: Record<Urgency, SecretStatus[]> = { expired: [], warning: [], ok: [] };
  for (const secret of secrets) {
    const status = evaluateSecret(secret, referenceDate, warningWindowDays);
    groups[status.urgency].push(status);
  }

  // Deterministic order: most urgent first, ties broken alphabetically.
  for (const bucket of Object.values(groups)) {
    bucket.sort(
      (a, b) =>
        a.daysUntilExpiry - b.daysUntilExpiry ||
        a.secret.name.localeCompare(b.secret.name),
    );
  }

  return {
    referenceDate,
    warningWindowDays,
    summary: {
      expired: groups.expired.length,
      warning: groups.warning.length,
      ok: groups.ok.length,
    },
    groups,
  };
}
