// Builds the full rotation report by evaluating every secret and grouping
// the results into expired/warning/ok notification buckets.
import { evaluateSecret } from "./evaluate.ts";
import type { RotationReport, SecretsConfig, SecretStatus } from "./types.ts";

/**
 * Generates a rotation report for `config` as of `now`.
 * `warningWindowOverrideDays`, when provided, takes precedence over the
 * config file's own `warningWindowDays` (e.g. a CLI flag override).
 */
export function generateReport(
  config: SecretsConfig,
  now: Date,
  warningWindowOverrideDays?: number,
): RotationReport {
  const warningWindowDays: number =
    warningWindowOverrideDays ?? config.warningWindowDays ?? 14;

  const expired: SecretStatus[] = [];
  const warning: SecretStatus[] = [];
  const ok: SecretStatus[] = [];

  for (const secret of config.secrets) {
    const status: SecretStatus = evaluateSecret(secret, now, warningWindowDays);
    if (status.urgency === "expired") {
      expired.push(status);
    } else if (status.urgency === "warning") {
      warning.push(status);
    } else {
      ok.push(status);
    }
  }

  return {
    generatedAt: now.toISOString(),
    warningWindowDays,
    totalSecrets: config.secrets.length,
    expired,
    warning,
    ok,
  };
}
