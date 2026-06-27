/**
 * CLI entry point for the artifact cleanup tool.
 *
 * Reads a JSON array of artifacts from a file, applies a retention policy
 * supplied via flags, prints a deletion plan and summary, and (unless
 * --dry-run) reports the artifacts it would delete. The tool itself never
 * performs real deletions here — it emits a plan that a downstream step could
 * act on — so --dry-run only changes the wording/output, never side effects.
 *
 * Output is designed to be both human-readable and machine-assertable: a set
 * of stable `KEY=value` lines (prefixed `SUMMARY`/`MODE`) plus an explicit
 * DELETE/RETAIN listing.
 *
 * Usage:
 *   bun run src/cli.ts --input artifacts.json \
 *     [--max-age-days N] [--max-total-size-bytes N] [--keep-latest-n N] \
 *     [--dry-run] [--now <iso-date>]
 */

import {
  parseArtifacts,
  planDeletion,
  summarize,
  type RetentionPolicy,
} from "./cleanup.ts";

interface CliOptions {
  input: string;
  policy: RetentionPolicy;
  dryRun: boolean;
  now: Date;
}

/** Parse argv (excluding `bun` and the script path) into structured options. */
export function parseArgs(argv: string[]): CliOptions {
  const policy: RetentionPolicy = {};
  let input = "";
  let dryRun = false;
  let now = new Date();

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    const next = () => {
      const v = argv[++i];
      if (v === undefined) throw new Error(`Missing value for argument "${arg}".`);
      return v;
    };
    switch (arg) {
      case "--input":
        input = next();
        break;
      case "--max-age-days":
        policy.maxAgeDays = parseNumber(next(), "--max-age-days");
        break;
      case "--max-total-size-bytes":
        policy.maxTotalSizeBytes = parseNumber(next(), "--max-total-size-bytes");
        break;
      case "--keep-latest-n":
        policy.keepLatestNPerWorkflow = parseNumber(next(), "--keep-latest-n");
        break;
      case "--dry-run":
        dryRun = true;
        break;
      case "--now": {
        const raw = next();
        now = new Date(raw);
        if (Number.isNaN(now.getTime())) throw new Error(`Invalid --now date: "${raw}".`);
        break;
      }
      default:
        throw new Error(`Unknown argument: "${arg}".`);
    }
  }

  if (!input) throw new Error("Missing required --input <path> argument.");
  return { input, policy, dryRun, now };
}

function parseNumber(raw: string, flag: string): number {
  const n = Number(raw);
  if (!Number.isFinite(n)) throw new Error(`${flag} expects a number, got "${raw}".`);
  return n;
}

/** Render the full report as a string (kept pure for easy testing). */
export function renderReport(options: CliOptions, fileContents: string): string {
  const artifacts = parseArtifacts(fileContents);
  const plan = planDeletion(artifacts, options.policy, options.now);
  const summary = summarize(plan);
  const lines: string[] = [];

  lines.push("=== Artifact Cleanup Plan ===");
  lines.push(`MODE=${options.dryRun ? "dry-run" : "execute"}`);
  lines.push(
    `POLICY maxAgeDays=${options.policy.maxAgeDays ?? "none"} ` +
      `maxTotalSizeBytes=${options.policy.maxTotalSizeBytes ?? "none"} ` +
      `keepLatestNPerWorkflow=${options.policy.keepLatestNPerWorkflow ?? "none"}`,
  );

  lines.push(`-- Artifacts to delete (${plan.toDelete.length}) --`);
  for (const a of plan.toDelete) {
    lines.push(`DELETE name=${a.name} sizeBytes=${a.sizeBytes} workflowRunId=${a.workflowRunId} createdAt=${a.createdAt}`);
  }
  lines.push(`-- Artifacts to retain (${plan.toRetain.length}) --`);
  for (const a of plan.toRetain) {
    lines.push(`RETAIN name=${a.name} sizeBytes=${a.sizeBytes} workflowRunId=${a.workflowRunId} createdAt=${a.createdAt}`);
  }

  lines.push(
    `SUMMARY deleted=${summary.deletedCount} retained=${summary.retainedCount} ` +
      `reclaimedBytes=${summary.spaceReclaimedBytes} retainedBytes=${summary.retainedSizeBytes}`,
  );

  if (options.dryRun) {
    lines.push("NOTE dry-run: no artifacts were actually deleted.");
  } else {
    lines.push(`RESULT deleted ${summary.deletedCount} artifact(s), reclaimed ${summary.spaceReclaimedBytes} bytes.`);
  }

  return lines.join("\n");
}

/** Program entry: read the input file and print the report. */
async function main(): Promise<void> {
  const options = parseArgs(Bun.argv.slice(2));
  const file = Bun.file(options.input);
  if (!(await file.exists())) {
    throw new Error(`Input file not found: ${options.input}`);
  }
  const contents = await file.text();
  console.log(renderReport(options, contents));
}

// Only run main() when executed directly (not when imported by tests).
if (import.meta.main) {
  main().catch((err: unknown) => {
    console.error(`ERROR: ${err instanceof Error ? err.message : String(err)}`);
    process.exit(1);
  });
}
