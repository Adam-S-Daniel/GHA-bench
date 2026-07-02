// Artifact cleanup script entrypoint. Run with: bun run src/cli.ts
//
// Ties together env-based configuration, the (mock) artifact source, the
// retention policy engine, and the executor into one end-to-end run.
// `runCleanup` is the pure, fully-injectable orchestration used by tests;
// the `import.meta.main` block below is the thin real-world wrapper that
// wires it to `process.env`, mock data, and stdout.
import { buildCleanupPlan } from "./cleanupPlanner";
import type { EnvVars } from "./envConfig";
import { parseDryRunFlag, parseFixtureName, parsePolicyFromEnv } from "./envConfig";
import { executeCleanupPlan } from "./executor";
import { generateMockArtifacts } from "./mockData";
import { formatPlanReport } from "./report";
import type { Artifact, CleanupPlan, ExecutionResult } from "./types";

export interface RunCleanupOptions {
  env: EnvVars;
  now: Date;
  artifacts: Artifact[];
  deleteArtifact: (artifact: Artifact) => void | Promise<void>;
}

export interface RunCleanupResult {
  plan: CleanupPlan;
  execution: ExecutionResult;
  report: string;
}

export async function runCleanup(options: RunCleanupOptions): Promise<RunCleanupResult> {
  const policy = parsePolicyFromEnv(options.env);
  const dryRun = parseDryRunFlag(options.env);

  const plan = buildCleanupPlan(options.artifacts, policy, options.now);
  const execution = await executeCleanupPlan(plan, options.deleteArtifact, { dryRun });
  const report = formatPlanReport(plan, { dryRun });

  return { plan, execution, report };
}

if (import.meta.main) {
  const now = new Date();
  const artifacts = generateMockArtifacts(now, parseFixtureName(process.env));

  // Deletion is simulated: this is mock artifact data, not a live API, so
  // "deleting" just means acknowledging the artifact would be removed.
  const deleteArtifact = (artifact: Artifact): void => {
    console.error(`Deleting artifact ${artifact.id} (${artifact.name})...`);
  };

  try {
    const { execution, report } = await runCleanup({
      env: process.env,
      now,
      artifacts,
      deleteArtifact,
    });

    console.log(report);

    if (execution.failures.length > 0) {
      console.error(`\n${execution.failures.length} artifact(s) failed to delete:`);
      for (const failure of execution.failures) {
        console.error(`  ${failure.artifactId}: ${failure.message}`);
      }
      process.exit(1);
    }
  } catch (error) {
    console.error(`Artifact cleanup failed: ${error instanceof Error ? error.message : error}`);
    process.exit(1);
  }
}
