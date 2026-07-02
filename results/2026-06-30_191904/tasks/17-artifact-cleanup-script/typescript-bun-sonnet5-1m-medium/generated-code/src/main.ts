// CLI entrypoint: load mock artifacts, apply retention policies, print a
// deletion plan. Run with `bun run src/main.ts [--dry-run|--apply]`.
//
// Policy knobs are configured via environment variables so the same script
// can be invoked identically from a shell or a GitHub Actions workflow:
//   ARTIFACTS_FILE            path to the JSON artifacts fixture (required)
//   MAX_AGE_DAYS              retention max-age policy (optional)
//   MAX_TOTAL_SIZE_BYTES      retention max-total-size policy (optional)
//   KEEP_LATEST_PER_WORKFLOW  keep-latest-N-per-workflow policy (optional)
//   NOW                       ISO timestamp to use as "now" (optional, for
//                             reproducible test runs; defaults to real time)
import { loadArtifacts } from "./loadArtifacts";
import { buildDeletionPlan } from "./retention";
import { formatPlanReport } from "./format";
import type { RetentionPolicy } from "./types";

function parseOptionalInt(value: string | undefined, name: string): number | undefined {
  if (value === undefined || value === "") return undefined;
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) {
    throw new Error(`Invalid environment value for ${name}: "${value}" is not a number`);
  }
  return parsed;
}

export function parsePolicyFromEnv(env: NodeJS.ProcessEnv): RetentionPolicy {
  return {
    maxAgeDays: parseOptionalInt(env.MAX_AGE_DAYS, "MAX_AGE_DAYS"),
    maxTotalSizeBytes: parseOptionalInt(
      env.MAX_TOTAL_SIZE_BYTES,
      "MAX_TOTAL_SIZE_BYTES",
    ),
    keepLatestPerWorkflow: parseOptionalInt(
      env.KEEP_LATEST_PER_WORKFLOW,
      "KEEP_LATEST_PER_WORKFLOW",
    ),
  };
}

export function isDryRun(argv: string[]): boolean {
  // Dry-run is the safe default; --apply is required to opt out of it.
  return !argv.includes("--apply");
}

async function main(): Promise<void> {
  const artifactsFile = process.env.ARTIFACTS_FILE ?? `${import.meta.dir}/../fixtures/mock-artifacts.json`;
  const policy = parsePolicyFromEnv(process.env);
  const dryRun = isDryRun(process.argv.slice(2));
  const now = process.env.NOW ? new Date(process.env.NOW) : new Date();

  const artifacts = await loadArtifacts(artifactsFile);
  const plan = buildDeletionPlan(artifacts, policy, { now, dryRun });

  console.log(formatPlanReport(plan));

  if (!dryRun) {
    // Real deletion is out of scope for this exercise (artifacts are mock
    // data), but we log clearly what would be deleted for real in --apply mode.
    console.log("");
    console.log(`Applied: ${plan.toDelete.length} artifact(s) would be deleted via the GitHub API.`);
  }
}

if (import.meta.main) {
  main().catch((err) => {
    console.error(`artifact-cleanup failed: ${(err as Error).message}`);
    process.exit(1);
  });
}
