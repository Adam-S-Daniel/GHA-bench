/**
 * Artifact cleanup CLI.
 *
 * Usage:
 *   bun run src/cli.ts --artifacts <artifacts.json> --config <policy.json> [--dry-run]
 *
 * Reads a mock artifact inventory and a retention-policy config, builds a
 * deletion plan, prints a human-readable report, and emits the full plan as a
 * single machine-readable line (::PLAN::{json}::ENDPLAN::) so CI harnesses can
 * assert exact values. In execute mode (dryRun=false) it "deletes" each doomed
 * artifact through a mock deleter that logs a DELETED line — the data is mock,
 * so no real API is called.
 */
import { executePlan, type ArtifactDeleter } from "./executor";
import { parseArtifactsJson, parsePolicyJson } from "./parse";
import { buildDeletionPlan } from "./planner";
import type { DeletionPlan } from "./types";

const USAGE =
  "Usage: bun run src/cli.ts --artifacts <artifacts.json> --config <policy.json> [--dry-run]";

interface CliArgs {
  artifactsPath: string;
  configPath: string;
  forceDryRun: boolean;
}

function parseArgs(argv: string[]): CliArgs {
  let artifactsPath: string | undefined;
  let configPath: string | undefined;
  let forceDryRun = false;

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    switch (arg) {
      case "--artifacts":
        artifactsPath = argv[++i];
        break;
      case "--config":
        configPath = argv[++i];
        break;
      case "--dry-run":
        forceDryRun = true;
        break;
      default:
        throw new Error(`unknown argument: ${arg}\n${USAGE}`);
    }
  }

  if (!artifactsPath) throw new Error(`--artifacts <file> is required\n${USAGE}`);
  if (!configPath) throw new Error(`--config <file> is required\n${USAGE}`);
  return { artifactsPath, configPath, forceDryRun };
}

async function readFileOrThrow(path: string, what: string): Promise<string> {
  try {
    return await Bun.file(path).text();
  } catch {
    throw new Error(`cannot read ${what} file: ${path}`);
  }
}

function printReport(plan: DeletionPlan): void {
  const mode = plan.dryRun ? " (DRY RUN)" : "";
  console.log(`Artifact Cleanup Plan${mode}`);
  console.log(`Reference date: ${plan.referenceDate}`);

  for (const a of plan.toDelete) {
    console.log(`  DELETE ${a.name} (id=${a.id}, ${a.sizeBytes} bytes) — ${a.reasons.join(", ")}`);
  }
  for (const a of plan.toRetain) {
    console.log(`  RETAIN ${a.name} (id=${a.id}, ${a.sizeBytes} bytes)`);
  }

  const s = plan.summary;
  console.log(
    `Summary: ${s.totalArtifacts} total | ${s.retainedCount} retained (${s.retainedSizeBytes} bytes) | ` +
      `${s.deletedCount} to delete | ${s.spaceReclaimedBytes} bytes reclaimed`,
  );
  // Single-line machine-readable plan for CI log parsing.
  console.log(`::PLAN::${JSON.stringify(plan)}::ENDPLAN::`);
}

/** Mock deleter: the inventory is mock data, so "deleting" just logs. */
const loggingDeleter: ArtifactDeleter = async (artifact) => {
  console.log(`DELETED ${artifact.name} (id=${artifact.id}, ${artifact.sizeBytes} bytes)`);
};

async function main(): Promise<void> {
  const args = parseArgs(Bun.argv.slice(2));

  const artifacts = parseArtifactsJson(
    await readFileOrThrow(args.artifactsPath, "artifacts"),
  );
  const config = parsePolicyJson(await readFileOrThrow(args.configPath, "policy config"));

  const plan = buildDeletionPlan(artifacts, config.policy, {
    // Default to the real clock; tests and CI fixtures pin referenceDate.
    referenceDate: config.referenceDate ?? new Date(),
    // Safety first: --dry-run always wins; otherwise the config decides.
    dryRun: args.forceDryRun || (config.dryRun ?? true),
  });

  printReport(plan);

  const result = await executePlan(plan, loggingDeleter);
  if (plan.dryRun) {
    console.log(
      `Dry run: ${result.skippedDryRun.length} artifacts would be deleted, nothing was touched`,
    );
  } else {
    console.log(
      `Deleted ${result.deleted.length} artifacts, reclaimed ${plan.summary.spaceReclaimedBytes} bytes`,
    );
  }
}

main().catch((err: unknown) => {
  console.error(`error: ${err instanceof Error ? err.message : String(err)}`);
  process.exit(1);
});
