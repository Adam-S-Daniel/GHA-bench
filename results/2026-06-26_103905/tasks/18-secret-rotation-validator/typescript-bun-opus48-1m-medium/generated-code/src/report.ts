// Report builder: turns a SecretConfig into a grouped, summarised report.
// Pure (no I/O) so it can be unit-tested deterministically.
import {
  classifySecret,
  type ClassifyOptions,
  type SecretConfig,
  type SecretEvaluation,
  type Status,
} from "./validator.ts";

/** Count of secrets in each urgency bucket plus the total. */
export interface ReportSummary {
  expired: number;
  warning: number;
  ok: number;
  total: number;
}

/** Evaluations grouped by urgency. */
export interface ReportGroups {
  expired: SecretEvaluation[];
  warning: SecretEvaluation[];
  ok: SecretEvaluation[];
}

/** The full rotation report. */
export interface RotationReport {
  /** ISO timestamp the report was generated for (the injected `now`). */
  generatedAt: string;
  /** The warning window used, echoed for transparency. */
  warningWindowDays: number;
  summary: ReportSummary;
  groups: ReportGroups;
  /** True if any secret is expired — callers map this to a non-zero exit code. */
  hasExpired: boolean;
}

/**
 * Evaluate every secret in the config, grouping by urgency.
 * Within each group, secrets are sorted soonest-due-first so the most urgent
 * items surface at the top of every rendering.
 */
export function buildReport(config: SecretConfig, options: ClassifyOptions): RotationReport {
  const groups: ReportGroups = { expired: [], warning: [], ok: [] };

  for (const secret of config.secrets) {
    const evaluation = classifySecret(secret, options);
    groups[evaluation.status].push(evaluation);
  }

  // Soonest-due (smallest daysUntilDue) first within each group.
  const bySoonestDue = (a: SecretEvaluation, b: SecretEvaluation): number =>
    a.daysUntilDue - b.daysUntilDue;
  groups.expired.sort(bySoonestDue);
  groups.warning.sort(bySoonestDue);
  groups.ok.sort(bySoonestDue);

  const summary: ReportSummary = {
    expired: groups.expired.length,
    warning: groups.warning.length,
    ok: groups.ok.length,
    total: config.secrets.length,
  };

  return {
    generatedAt: options.now.toISOString(),
    warningWindowDays: options.warningWindowDays,
    summary,
    groups,
    hasExpired: summary.expired > 0,
  };
}

/** Iterate group entries in severity order: expired, then warning, then ok. */
export function* iterateBySeverity(
  report: RotationReport,
): Generator<{ status: Status; evaluation: SecretEvaluation }> {
  const order: Status[] = ["expired", "warning", "ok"];
  for (const status of order) {
    for (const evaluation of report.groups[status]) {
      yield { status, evaluation };
    }
  }
}
