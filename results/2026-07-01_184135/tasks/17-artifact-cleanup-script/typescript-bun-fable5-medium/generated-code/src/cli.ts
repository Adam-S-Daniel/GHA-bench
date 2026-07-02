/**
 * CLI entry point for the artifact cleanup script.
 *
 * Usage:
 *   bun run src/cli.ts --artifacts <file> --policy <file> [--now <ISO date>]
 *
 * Reads mock artifact metadata and a retention policy from JSON files,
 * builds a deletion plan, prints a machine-parseable report, and (unless
 * the policy sets dryRun) "deletes" each artifact via a mock deleter that
 * logs the action. `--now` pins the clock for deterministic CI output.
 */
import {
  buildDeletionPlan,
  executePlan,
  formatPlanReport,
  type Artifact,
  type DeletionPlan,
} from "./cleanup.ts";
import { loadArtifactsFile, loadPolicyFile } from "./config.ts";

/** Parse `--flag value` pairs from argv, rejecting unknown flags. */
export function parseArgs(argv: string[]): {
  artifacts: string;
  policy: string;
  now: Date;
} {
  const opts = new Map<string, string>();
  for (let i = 0; i < argv.length; i += 2) {
    const flag = argv[i];
    const value = argv[i + 1];
    if (flag === undefined || !flag.startsWith("--") || value === undefined) {
      throw new Error(`invalid arguments near "${flag ?? ""}"`);
    }
    opts.set(flag.slice(2), value);
  }
  const artifacts = opts.get("artifacts");
  const policy = opts.get("policy");
  if (!artifacts || !policy) {
    throw new Error(
      "usage: bun run src/cli.ts --artifacts <file> --policy <file> [--now <ISO date>]",
    );
  }
  const nowRaw = opts.get("now");
  const now = nowRaw === undefined ? new Date() : new Date(nowRaw);
  if (Number.isNaN(now.getTime())) {
    throw new Error(`--now is not a valid date: "${nowRaw}"`);
  }
  const known = new Set(["artifacts", "policy", "now"]);
  for (const key of opts.keys()) {
    if (!known.has(key)) throw new Error(`unknown flag: --${key}`);
  }
  return { artifacts, policy, now };
}

async function main(): Promise<void> {
  const { artifacts: artifactsPath, policy: policyPath, now } = parseArgs(
    Bun.argv.slice(2),
  );
  const artifacts: Artifact[] = await loadArtifactsFile(artifactsPath);
  const policy = await loadPolicyFile(policyPath);
  const plan: DeletionPlan = buildDeletionPlan(artifacts, policy, now);

  console.log(formatPlanReport(plan));

  // Mock deleter: the artifact list is mock data, so "deleting" just logs.
  const deleted = await executePlan(plan, async (artifact) => {
    console.log(`Deleting artifact: ${artifact.name}`);
  });
  if (!plan.summary.dryRun) {
    console.log(`EXECUTED deletions=${deleted.length}`);
  }
}

if (import.meta.main) {
  main().catch((err: unknown) => {
    console.error(`error: ${err instanceof Error ? err.message : String(err)}`);
    process.exit(1);
  });
}
