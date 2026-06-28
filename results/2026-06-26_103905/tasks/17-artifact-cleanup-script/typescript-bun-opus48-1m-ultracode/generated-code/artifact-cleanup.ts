#!/usr/bin/env bun
/**
 * artifact-cleanup.ts — CLI entry point for the artifact retention planner.
 *
 * Reads a JSON config (artifacts + retention policy + optional reference time),
 * computes a deletion plan, and prints either a human-readable report or JSON.
 *
 * Usage:
 *   bun run artifact-cleanup.ts <config.json> [options]
 *
 * Options:
 *   --dry-run                 Mark the plan as a dry run (no deletions performed).
 *   --format <text|json>      Output format (default: text).
 *   --now <ISO-8601>          Override the reference "now" used for age checks.
 *   --max-age-days <n>        Override policy.maxAgeDays.
 *   --max-total-size <bytes>  Override policy.maxTotalSizeBytes.
 *   --keep-latest <n>         Override policy.keepLatestNPerWorkflow.
 *   -h, --help                Show this help.
 *
 * The reference time is resolved with the precedence:
 *   --now flag  >  CLEANUP_NOW env var  >  config "now"  >  the real wall clock.
 *
 * Exit codes: 0 on success, 1 on any error (bad args, unreadable/invalid config,
 * invalid policy). Errors are written to stderr with a meaningful message.
 */

import { parseConfig } from "./src/config.ts";
import { planCleanup } from "./src/cleanup.ts";
import { formatPlanJson, formatPlanText } from "./src/format.ts";
import type { RetentionPolicy } from "./src/types.ts";

interface CliOptions {
  configPath?: string;
  dryRun: boolean;
  format: "text" | "json";
  now?: string;
  overrides: Partial<RetentionPolicy>;
  help: boolean;
}

const USAGE = `Usage: bun run artifact-cleanup.ts <config.json> [options]

Apply retention policies to a list of CI artifacts and print a deletion plan.

Options:
  --dry-run                 Mark the plan as a dry run (no deletions performed).
  --format <text|json>      Output format (default: text).
  --now <ISO-8601>          Override the reference "now" used for age checks.
  --max-age-days <n>        Override policy.maxAgeDays.
  --max-total-size <bytes>  Override policy.maxTotalSizeBytes.
  --keep-latest <n>         Override policy.keepLatestNPerWorkflow.
  -h, --help                Show this help.`;

/** Parse a flag value as a finite number, throwing a clear error otherwise. */
function asNumber(flag: string, value: string | undefined): number {
  if (value === undefined) {
    throw new Error(`option ${flag} requires a numeric value`);
  }
  const n = Number(value);
  if (!Number.isFinite(n)) {
    throw new Error(`option ${flag} expects a number, got "${value}"`);
  }
  return n;
}

/**
 * Parse argv (already sliced past the runtime/script). Supports both
 * `--flag value` and `--flag=value` forms.
 */
export function parseArgs(argv: string[]): CliOptions {
  const opts: CliOptions = { dryRun: false, format: "text", overrides: {}, help: false };

  for (let i = 0; i < argv.length; i++) {
    const token = argv[i]!;
    // Support --flag=value by splitting on the first '='.
    let flag = token;
    let inlineValue: string | undefined;
    if (token.startsWith("--") && token.includes("=")) {
      const eq = token.indexOf("=");
      flag = token.slice(0, eq);
      inlineValue = token.slice(eq + 1);
    }
    const next = (): string | undefined => (inlineValue !== undefined ? inlineValue : argv[++i]);

    switch (flag) {
      case "-h":
      case "--help":
        opts.help = true;
        break;
      case "--dry-run":
        opts.dryRun = true;
        break;
      case "--format": {
        const value = next();
        if (value !== "text" && value !== "json") {
          throw new Error(`--format must be "text" or "json", got "${String(value)}"`);
        }
        opts.format = value;
        break;
      }
      case "--now":
        opts.now = next();
        break;
      case "--max-age-days":
        opts.overrides.maxAgeDays = asNumber("--max-age-days", next());
        break;
      case "--max-total-size":
        opts.overrides.maxTotalSizeBytes = asNumber("--max-total-size", next());
        break;
      case "--keep-latest":
        opts.overrides.keepLatestNPerWorkflow = asNumber("--keep-latest", next());
        break;
      default:
        if (flag.startsWith("-")) {
          throw new Error(`unknown option "${flag}"`);
        }
        if (opts.configPath !== undefined) {
          throw new Error(`unexpected extra argument "${flag}"`);
        }
        opts.configPath = flag;
    }
  }
  return opts;
}

/**
 * Resolve the reference "now": CLI flag > env var > config value > wall clock.
 * Throws when an explicitly-supplied value is not a valid date.
 */
function resolveNow(cliNow: string | undefined, configNow: Date | undefined): Date {
  const explicit = cliNow ?? Bun.env.CLEANUP_NOW;
  if (explicit !== undefined) {
    const d = new Date(explicit);
    if (Number.isNaN(d.getTime())) {
      throw new Error(`invalid --now / CLEANUP_NOW date: "${explicit}"`);
    }
    return d;
  }
  return configNow ?? new Date();
}

/** Run the CLI. Returns the process exit code. */
export async function run(argv: string[]): Promise<number> {
  let opts: CliOptions;
  try {
    opts = parseArgs(argv);
  } catch (err) {
    process.stderr.write(`Error: ${(err as Error).message}\n\n${USAGE}\n`);
    return 1;
  }

  if (opts.help) {
    process.stdout.write(`${USAGE}\n`);
    return 0;
  }

  if (opts.configPath === undefined) {
    process.stderr.write(`Error: no config file provided.\n\n${USAGE}\n`);
    return 1;
  }

  try {
    const file = Bun.file(opts.configPath);
    if (!(await file.exists())) {
      throw new Error(`config file not found: ${opts.configPath}`);
    }
    const text = await file.text();
    let raw: unknown;
    try {
      raw = JSON.parse(text);
    } catch (parseErr) {
      throw new Error(`config file is not valid JSON: ${(parseErr as Error).message}`);
    }

    const config = parseConfig(raw);
    // Merge CLI policy overrides on top of the config's policy.
    const policy: RetentionPolicy = { ...config.policy, ...opts.overrides };
    const now = resolveNow(opts.now, config.now);

    const plan = planCleanup(config.artifacts, policy, { now, dryRun: opts.dryRun });
    const output = opts.format === "json" ? formatPlanJson(plan) : formatPlanText(plan);
    process.stdout.write(`${output}\n`);
    return 0;
  } catch (err) {
    process.stderr.write(`Error: ${(err as Error).message}\n`);
    return 1;
  }
}

// Only execute when run directly (not when imported by tests).
if (import.meta.main) {
  process.exit(await run(Bun.argv.slice(2)));
}
