// Reads the CLI's configuration from environment variables, with sensible
// defaults so the script runs meaningfully with zero configuration (as it
// must inside the CI workflow, which passes no secrets).
import type { RetentionPolicy } from "./types";

export type EnvVars = Record<string, string | undefined>;

export const DEFAULT_POLICY: RetentionPolicy = {
  maxAgeInDays: 30,
  keepLatestN: 3,
  maxTotalSizeInBytes: 200 * 1024 * 1024, // 200 MiB
};

function parseNumberEnv(env: EnvVars, key: string, fallback: number): number {
  const raw = env[key];
  if (raw === undefined) {
    return fallback;
  }
  const value = Number(raw);
  if (Number.isNaN(value)) {
    throw new Error(`${key} must be a number, got "${raw}"`);
  }
  return value;
}

export function parsePolicyFromEnv(env: EnvVars): RetentionPolicy {
  return {
    maxAgeInDays: parseNumberEnv(env, "MAX_AGE_DAYS", DEFAULT_POLICY.maxAgeInDays as number),
    keepLatestN: parseNumberEnv(env, "KEEP_LATEST_N", DEFAULT_POLICY.keepLatestN as number),
    maxTotalSizeInBytes: parseNumberEnv(
      env,
      "MAX_TOTAL_SIZE_BYTES",
      DEFAULT_POLICY.maxTotalSizeInBytes as number,
    ),
  };
}

export function parseDryRunFlag(env: EnvVars): boolean {
  const raw = env.DRY_RUN;
  if (raw === undefined) {
    return true;
  }
  if (raw === "true") return true;
  if (raw === "false") return false;
  throw new Error(`DRY_RUN must be "true" or "false", got "${raw}"`);
}

/** Which named mock-data fixture to load (see src/mockData.ts). */
export function parseFixtureName(env: EnvVars): string {
  return env.MOCK_DATA_FIXTURE ?? "baseline";
}
