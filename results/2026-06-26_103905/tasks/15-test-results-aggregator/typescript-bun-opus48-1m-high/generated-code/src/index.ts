#!/usr/bin/env bun
/**
 * CLI entry point for the test-results aggregator.
 *
 * Usage:
 *   bun run src/index.ts <path> [<path> ...]
 *
 * Each <path> is a directory of result files or an individual .xml/.json file.
 * The aggregated markdown summary is printed to stdout and, when running under
 * GitHub Actions, appended to the file named by $GITHUB_STEP_SUMMARY so it
 * shows up on the job's summary page.
 *
 * Exit code: 0 on a successful aggregation (this is a *reporter*, not a gate —
 * it does not fail the job just because some tests failed). Pass
 * `--fail-on-failure` to make the process exit 1 when any test failed, for
 * callers who want the report step to also gate the pipeline. Genuine errors
 * (bad input, unreadable files) always exit 1 with a clear message on stderr.
 */

import { appendFile } from "node:fs/promises";
import { aggregatePaths } from "./loader.ts";
import { renderMarkdown } from "./summary.ts";

interface CliOptions {
  paths: string[];
  failOnFailure: boolean;
}

/** Split argv into option flags and positional paths. */
export function parseArgs(argv: string[]): CliOptions {
  const paths: string[] = [];
  let failOnFailure = false;

  for (const arg of argv) {
    if (arg === "--fail-on-failure") {
      failOnFailure = true;
    } else if (arg === "--help" || arg === "-h") {
      // Handled by the caller; treat as no path.
      paths.length = 0;
      return { paths, failOnFailure };
    } else {
      paths.push(arg);
    }
  }

  return { paths, failOnFailure };
}

const USAGE = `test-results-aggregator

Usage:
  bun run src/index.ts <path> [<path> ...] [--fail-on-failure]

Arguments:
  <path>               A directory of result files, or a single .xml/.json file.

Options:
  --fail-on-failure    Exit with code 1 if any aggregated test failed.
  -h, --help           Show this help.`;

export async function main(argv: string[]): Promise<number> {
  const { paths, failOnFailure } = parseArgs(argv);

  if (paths.length === 0) {
    console.error(USAGE);
    return 1;
  }

  let result;
  try {
    result = await aggregatePaths(paths);
  } catch (err) {
    console.error(`Error: ${(err as Error).message}`);
    return 1;
  }

  const markdown = renderMarkdown(result);

  // Always print to stdout so the report is visible in plain CI logs.
  console.log(markdown);

  // When under GitHub Actions, also append to the job summary file.
  const summaryPath = process.env.GITHUB_STEP_SUMMARY;
  if (summaryPath) {
    try {
      await appendFile(summaryPath, markdown + "\n");
    } catch (err) {
      console.error(
        `Warning: could not write GITHUB_STEP_SUMMARY: ${(err as Error).message}`,
      );
    }
  }

  if (failOnFailure && result.totals.failed > 0) {
    console.error(`::error::${result.totals.failed} test(s) failed.`);
    return 1;
  }

  return 0;
}

// Run only when executed directly (not when imported by a test).
if (import.meta.main) {
  main(Bun.argv.slice(2)).then((code) => process.exit(code));
}
