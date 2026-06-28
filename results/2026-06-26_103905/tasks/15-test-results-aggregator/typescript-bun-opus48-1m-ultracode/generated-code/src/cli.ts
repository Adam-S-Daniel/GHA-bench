#!/usr/bin/env bun
/**
 * Command-line entry point for the test-results aggregator.
 *
 * Usage:
 *   bun run src/cli.ts <file-or-dir> [<file-or-dir> ...] [options]
 *
 * Options:
 *   --fail-on-failure   exit 1 when any test failed (default: exit 0; this is a
 *                       reporting tool, so by default it never fails the build)
 *   --json              also print the full aggregate as JSON to stdout
 *   --help, -h          show usage
 *
 * Behaviour:
 *   - Directories are expanded to their `.json` and `.xml` result files.
 *   - The markdown report is appended to `$GITHUB_STEP_SUMMARY` when that
 *     environment variable is set (the GitHub Actions job summary), and is
 *     always echoed to stdout so it appears in the workflow logs.
 *   - A machine-readable `AGGREGATE ...` summary line is printed for easy
 *     assertion, and key=value pairs are appended to `$GITHUB_OUTPUT`.
 */
import { appendFile, readdir, stat } from "node:fs/promises";
import { join } from "node:path";
import { aggregate } from "./aggregate";
import { formatDuration, renderMarkdown } from "./markdown";
import { parseResultFile } from "./parsers";
import type { AggregateResult, TestRun } from "./types";

/** Parsed command-line options. */
export interface CliOptions {
  paths: string[];
  failOnFailure: boolean;
  json: boolean;
  help: boolean;
}

const USAGE = `test-results-aggregator

Aggregate JUnit XML and JSON test result files across a matrix build, compute
totals, detect flaky tests, and render a markdown job summary.

Usage:
  bun run src/cli.ts <file-or-dir> [<file-or-dir> ...] [options]

Options:
  --fail-on-failure   Exit 1 if any test failed (default: always exit 0).
  --json              Also print the full aggregate result as JSON.
  -h, --help          Show this help.`;

/** Parse argv (already sliced past the runtime + script). Throws on unknown flags. */
export function parseArgs(argv: string[]): CliOptions {
  const opts: CliOptions = { paths: [], failOnFailure: false, json: false, help: false };
  for (const arg of argv) {
    switch (arg) {
      case "--fail-on-failure":
        opts.failOnFailure = true;
        break;
      case "--json":
        opts.json = true;
        break;
      case "-h":
      case "--help":
        opts.help = true;
        break;
      default:
        if (arg.startsWith("-")) {
          throw new Error(`unknown option: ${arg}`);
        }
        opts.paths.push(arg);
    }
  }
  return opts;
}

/** True when a path looks like a result file we can parse. */
function isResultFile(path: string): boolean {
  return /\.(json|xml|junit)$/i.test(path);
}

/**
 * Expand the provided paths into a concrete, sorted list of result files.
 * Directories are searched recursively; explicit file paths pass through.
 * A non-existent path raises an error naming the path.
 */
export async function collectInputFiles(paths: string[]): Promise<string[]> {
  const files = new Set<string>();
  for (const p of paths) {
    let info;
    try {
      info = await stat(p);
    } catch {
      throw new Error(`path not found: ${p}`);
    }
    if (info.isDirectory()) {
      const entries = await readdir(p, { recursive: true });
      for (const entry of entries) {
        if (isResultFile(entry)) files.add(join(p, entry));
      }
    } else {
      files.add(p);
    }
  }
  return [...files].sort();
}

/** Read and parse every file into a normalised run. */
export async function loadRuns(files: string[]): Promise<TestRun[]> {
  const runs: TestRun[] = [];
  for (const file of files) {
    const body = await Bun.file(file).text();
    runs.push(parseResultFile(body, file));
  }
  return runs;
}

/** A compact, stable, machine-readable one-liner for log assertions. */
export function formatSummaryLine(result: AggregateResult): string {
  const t = result.totals;
  return (
    `AGGREGATE status=${result.passed ? "PASSED" : "FAILED"} ` +
    `passed=${t.passed} failed=${t.failed} skipped=${t.skipped} total=${t.total} ` +
    `duration=${formatDuration(t.durationSeconds)} flaky=${result.flaky.length} runs=${result.runCount}`
  );
}

/** Build the `key=value` block appended to `$GITHUB_OUTPUT`. */
function formatGithubOutputs(result: AggregateResult): string {
  const t = result.totals;
  return (
    [
      `status=${result.passed ? "passed" : "failed"}`,
      `passed=${t.passed}`,
      `failed=${t.failed}`,
      `skipped=${t.skipped}`,
      `total=${t.total}`,
      `duration_seconds=${t.durationSeconds}`,
      `flaky=${result.flaky.length}`,
      `runs=${result.runCount}`,
    ].join("\n") + "\n"
  );
}

/**
 * Program body. Returns the intended process exit code so it stays testable.
 *   0 — success (default, even with test failures present)
 *   1 — failures present and --fail-on-failure was given
 *   2 — usage / input error
 */
export async function main(argv: string[]): Promise<number> {
  let opts: CliOptions;
  try {
    opts = parseArgs(argv);
  } catch (err) {
    console.error(`error: ${err instanceof Error ? err.message : String(err)}`);
    console.error(USAGE);
    return 2;
  }

  if (opts.help) {
    console.log(USAGE);
    return 0;
  }

  if (opts.paths.length === 0) {
    console.error("error: no input paths given");
    console.error(USAGE);
    return 2;
  }

  let files: string[];
  try {
    files = await collectInputFiles(opts.paths);
  } catch (err) {
    console.error(`error: ${err instanceof Error ? err.message : String(err)}`);
    return 2;
  }

  if (files.length === 0) {
    console.error("error: no .json or .xml result files found in the given path(s)");
    return 2;
  }

  let runs: TestRun[];
  try {
    runs = await loadRuns(files);
  } catch (err) {
    console.error(`error: ${err instanceof Error ? err.message : String(err)}`);
    return 2;
  }

  const result = aggregate(runs);
  const markdown = renderMarkdown(result);

  // Write the markdown to the GitHub Actions job summary, if available.
  const summaryPath = process.env.GITHUB_STEP_SUMMARY;
  if (summaryPath && summaryPath.length > 0) {
    try {
      await appendFile(summaryPath, markdown + "\n");
    } catch (err) {
      console.error(
        `warning: could not write job summary: ${err instanceof Error ? err.message : String(err)}`,
      );
    }
  }

  // Always echo the report and the machine summary line to stdout.
  console.log(markdown);
  console.log(formatSummaryLine(result));

  // Expose key numbers as step outputs for downstream steps.
  const outputPath = process.env.GITHUB_OUTPUT;
  if (outputPath && outputPath.length > 0) {
    try {
      await appendFile(outputPath, formatGithubOutputs(result));
    } catch (err) {
      console.error(
        `warning: could not write step outputs: ${err instanceof Error ? err.message : String(err)}`,
      );
    }
  }

  if (opts.json) {
    console.log(JSON.stringify(result, null, 2));
  }

  return opts.failOnFailure && !result.passed ? 1 : 0;
}

// Only run when executed directly (not when imported by tests).
if (import.meta.main) {
  process.exit(await main(process.argv.slice(2)));
}
