// Core domain logic for the Secret Rotation Validator.
//
// Everything here is pure and side-effect free: given a configuration and a
// reference "now" date, it classifies each secret by rotation urgency and
// produces a structured report. Keeping it pure makes the logic trivially
// testable and lets the CLI / formatting layers stay thin.

/** Rotation urgency buckets, ordered from most to least urgent. */
export type RotationStatus = "expired" | "warning" | "ok";

/** A single secret's metadata as supplied in the configuration. */
export interface Secret {
  /** Logical name of the secret (e.g. DATABASE_PASSWORD). */
  name: string;
  /** ISO calendar date (YYYY-MM-DD) the secret was last rotated. */
  lastRotated: string;
  /** Maximum age, in days, before the secret must be rotated. */
  rotationPolicyDays: number;
  /** Services that depend on this secret (for blast-radius context). */
  requiredBy: string[];
}

/** A validated configuration ready for evaluation. */
export interface SecretConfig {
  secrets: Secret[];
  /** Number of days before expiry that should raise a "warning". */
  warningWindowDays: number;
}

/** A secret after evaluation against the reference date. */
export interface EvaluatedSecret extends Secret {
  status: RotationStatus;
  /** ISO date the secret expires (lastRotated + rotationPolicyDays). */
  expiresOn: string;
  /** Whole days until expiry; negative when already expired. */
  daysUntilExpiry: number;
}

/** The full rotation report, grouped by urgency. */
export interface RotationReport {
  /** ISO date the report was generated against. */
  generatedAt: string;
  warningWindowDays: number;
  summary: {
    expired: number;
    warning: number;
    ok: number;
    total: number;
  };
  groups: {
    expired: EvaluatedSecret[];
    warning: EvaluatedSecret[];
    ok: EvaluatedSecret[];
  };
}

/** Default warning window applied when the config does not specify one. */
export const DEFAULT_WARNING_WINDOW_DAYS = 14;

const MS_PER_DAY = 24 * 60 * 60 * 1000;
const ISO_DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

/**
 * Parse an ISO calendar date (YYYY-MM-DD) into a UTC-midnight epoch in ms.
 * We pin everything to UTC midnight so day arithmetic is exact and never
 * affected by timezones or daylight-saving transitions.
 */
function parseIsoDateToUtcMs(value: string, field: string): number {
  if (typeof value !== "string" || !ISO_DATE_RE.test(value)) {
    throw new Error(
      `Invalid date for '${field}': expected an ISO date like 2026-01-31, got ${JSON.stringify(value)}`,
    );
  }
  const ms = Date.parse(`${value}T00:00:00.000Z`);
  if (Number.isNaN(ms)) {
    throw new Error(
      `Invalid date for '${field}': '${value}' is not a real calendar date`,
    );
  }
  return ms;
}

/** Format a UTC-midnight epoch (ms) back to an ISO calendar date. */
function formatUtcMsToIsoDate(ms: number): string {
  // toISOString() yields e.g. "2026-04-01T00:00:00.000Z"; keep the date part.
  return new Date(ms).toISOString().slice(0, 10);
}

/**
 * Validate raw (untrusted) input into a typed SecretConfig.
 * Throws Error with a precise, human-readable message on the first problem so
 * the CLI can surface exactly what is wrong with the user's config file.
 */
export function parseConfig(raw: unknown): SecretConfig {
  if (raw === null || typeof raw !== "object") {
    throw new Error("Config must be a JSON object with a 'secrets' array");
  }
  const obj = raw as Record<string, unknown>;

  if (!Array.isArray(obj.secrets)) {
    throw new Error("Config is missing required 'secrets' array");
  }

  const secrets: Secret[] = obj.secrets.map((entry, index) =>
    validateSecret(entry, index),
  );

  let warningWindowDays = DEFAULT_WARNING_WINDOW_DAYS;
  if (obj.warningWindowDays !== undefined) {
    if (
      typeof obj.warningWindowDays !== "number" ||
      !Number.isFinite(obj.warningWindowDays) ||
      obj.warningWindowDays < 0
    ) {
      throw new Error(
        `Config 'warningWindowDays' must be a non-negative number, got ${JSON.stringify(obj.warningWindowDays)}`,
      );
    }
    warningWindowDays = obj.warningWindowDays;
  }

  return { secrets, warningWindowDays };
}

/** Validate a single raw secret entry; `index` is used for error context. */
function validateSecret(entry: unknown, index: number): Secret {
  const where = `secrets[${index}]`;
  if (entry === null || typeof entry !== "object") {
    throw new Error(`${where} must be an object`);
  }
  const s = entry as Record<string, unknown>;

  if (typeof s.name !== "string" || s.name.trim() === "") {
    throw new Error(`${where}.name must be a non-empty string`);
  }
  if (typeof s.lastRotated !== "string") {
    throw new Error(`${where} (${s.name}) is missing 'lastRotated' date`);
  }
  // Validate date format/value eagerly so bad data fails at parse time.
  parseIsoDateToUtcMs(s.lastRotated, `${where}.lastRotated`);

  if (
    typeof s.rotationPolicyDays !== "number" ||
    !Number.isInteger(s.rotationPolicyDays) ||
    s.rotationPolicyDays <= 0
  ) {
    throw new Error(
      `${where} (${s.name}) 'rotationPolicyDays' must be a positive integer, got ${JSON.stringify(s.rotationPolicyDays)}`,
    );
  }

  let requiredBy: string[] = [];
  if (s.requiredBy !== undefined) {
    if (
      !Array.isArray(s.requiredBy) ||
      !s.requiredBy.every((x): x is string => typeof x === "string")
    ) {
      throw new Error(
        `${where} (${s.name}) 'requiredBy' must be an array of strings`,
      );
    }
    requiredBy = s.requiredBy;
  }

  return {
    name: s.name,
    lastRotated: s.lastRotated,
    rotationPolicyDays: s.rotationPolicyDays,
    requiredBy,
  };
}

/**
 * Evaluate a single secret against the reference date `now`.
 *
 * Classification rules (warningWindowDays = W):
 *   daysUntilExpiry < 0            -> "expired"  (policy already breached)
 *   0 <= daysUntilExpiry <= W      -> "warning"  (rotate soon, incl. today)
 *   daysUntilExpiry > W            -> "ok"
 */
export function evaluateSecret(
  secret: Secret,
  now: string,
  warningWindowDays: number,
): EvaluatedSecret {
  const lastRotatedMs = parseIsoDateToUtcMs(
    secret.lastRotated,
    "lastRotated",
  );
  const nowMs = parseIsoDateToUtcMs(now, "now");

  const expiresOnMs = lastRotatedMs + secret.rotationPolicyDays * MS_PER_DAY;
  // Both operands are UTC midnight, so this division is an exact integer.
  const daysUntilExpiry = Math.round((expiresOnMs - nowMs) / MS_PER_DAY);

  let status: RotationStatus;
  if (daysUntilExpiry < 0) {
    status = "expired";
  } else if (daysUntilExpiry <= warningWindowDays) {
    status = "warning";
  } else {
    status = "ok";
  }

  return {
    ...secret,
    status,
    expiresOn: formatUtcMsToIsoDate(expiresOnMs),
    daysUntilExpiry,
  };
}

/**
 * Evaluate every secret in the config and assemble the grouped report.
 * An explicit `warningWindowDays` overrides the config value (used by the CLI
 * --warning-window flag); otherwise the config's window is used.
 */
export function generateReport(
  config: SecretConfig,
  now: string,
  warningWindowDays: number = config.warningWindowDays,
): RotationReport {
  const evaluated = config.secrets.map((s) =>
    evaluateSecret(s, now, warningWindowDays),
  );

  // Soonest expiry first within each group keeps the most urgent rows on top.
  const bySoonestExpiry = (a: EvaluatedSecret, b: EvaluatedSecret): number =>
    a.daysUntilExpiry - b.daysUntilExpiry;

  const groups = {
    expired: evaluated
      .filter((s) => s.status === "expired")
      .sort(bySoonestExpiry),
    warning: evaluated
      .filter((s) => s.status === "warning")
      .sort(bySoonestExpiry),
    ok: evaluated.filter((s) => s.status === "ok").sort(bySoonestExpiry),
  };

  return {
    generatedAt: now,
    warningWindowDays,
    summary: {
      expired: groups.expired.length,
      warning: groups.warning.length,
      ok: groups.ok.length,
      total: evaluated.length,
    },
    groups,
  };
}
