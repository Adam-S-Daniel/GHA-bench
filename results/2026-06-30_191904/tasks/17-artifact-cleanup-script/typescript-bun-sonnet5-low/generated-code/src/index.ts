// Entry point: runs the artifact cleanup policy over the (mock) artifact list and
// prints a plan report. Intended to be run with `bun run src/index.ts` and wired
// up as a step in a GitHub Actions workflow.
import { buildCleanupPlan } from "./retention";
import { formatReport } from "./report";
import { mockArtifacts } from "./fixtures";
import type { Artifact, CleanupPlan, RetentionPolicy } from "./types";

export interface RunCleanupOptions {
  artifacts: Artifact[];
  policy: RetentionPolicy;
  now?: Date;
  dryRun?: boolean;
}

export interface RunCleanupResult {
  plan: CleanupPlan;
  report: string;
}

export function runCleanup(options: RunCleanupOptions): RunCleanupResult {
  if (options.artifacts.length === 0) {
    throw new Error("Cannot run cleanup: no artifacts were provided.");
  }

  const plan = buildCleanupPlan(options.artifacts, options.policy, {
    now: options.now,
    dryRun: options.dryRun,
  });
  const report = formatReport(plan);

  return { plan, report };
}

/** Reads policy configuration from environment variables, with sensible defaults. */
function policyFromEnv(): RetentionPolicy {
  const policy: RetentionPolicy = {};

  if (process.env.MAX_AGE_DAYS) {
    policy.maxAgeDays = Number(process.env.MAX_AGE_DAYS);
  }
  if (process.env.MAX_TOTAL_SIZE_BYTES) {
    policy.maxTotalSizeBytes = Number(process.env.MAX_TOTAL_SIZE_BYTES);
  }
  if (process.env.KEEP_LATEST_PER_WORKFLOW) {
    policy.keepLatestPerWorkflow = Number(process.env.KEEP_LATEST_PER_WORKFLOW);
  }

  return policy;
}

// Only execute the CLI behavior when run directly (not when imported by tests).
if (import.meta.main) {
  const dryRun = process.env.DRY_RUN !== "false";
  const policy: RetentionPolicy = {
    maxAgeDays: 90,
    keepLatestPerWorkflow: 1,
    ...policyFromEnv(),
  };

  try {
    const { report } = runCleanup({ artifacts: mockArtifacts, policy, dryRun });
    console.log(report);
  } catch (error) {
    console.error(`Artifact cleanup failed: ${(error as Error).message}`);
    process.exit(1);
  }
}
