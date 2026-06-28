#!/usr/bin/env bun
/**
 * CLI entry point: aggregate test-result files and emit a GitHub Actions job
 * summary.
 *
 * Usage:
 *   bun run src/cli.ts [paths...]
 *
 * Each path may be a result file (.xml / .json) or a directory containing such
 * files (scanned non-recursively). With no paths, defaults to "fixtures/sample".
 *
 * Output:
 *   - Human-facing markdown is appended to $GITHUB_STEP_SUMMARY (when set) and
 *     also echoed to stdout so it appears in the build log.
 *   - A delimited "=== AGGREGATE SUMMARY ===" key=value block is printed to
 *     stdout for reliable machine assertions in CI.
 *
 * Exit status:
 *   - 0 when aggregation succeeds (even if some tests failed — failing the
 *     *summary* job on red tests is the test job's responsibility, not ours).
 *   - 1 when no result files could be found or parsed, or on bad arguments.
 */
import { readdir, appendFile } from "node:fs/promises";
import { statSync } from "node:fs";
import { aggregate } from "./aggregator.ts";
import { parseFile } from "./parser.ts";
import { renderMarkdown, renderMachineSummary } from "./markdown.ts";
import type { TestRun } from "./types.ts";

/** Expand the given paths into a sorted, de-duplicated list of result files. */
async function collectResultFiles(paths: string[]): Promise<string[]> {
  const files = new Set<string>();
  for (const p of paths) {
    let isDir = false;
    try {
      isDir = statSync(p).isDirectory();
    } catch {
      throw new Error(`Input path does not exist: "${p}"`);
    }
    if (isDir) {
      const entries = await readdir(p, { withFileTypes: true });
      for (const e of entries) {
        if (!e.isFile()) continue;
        const lower = e.name.toLowerCase();
        if (lower.endsWith(".xml") || lower.endsWith(".json")) {
          files.add(`${p.replace(/\/$/, "")}/${e.name}`);
        }
      }
    } else {
      files.add(p);
    }
  }
  return [...files].sort();
}

export async function main(argv: string[]): Promise<number> {
  const paths = argv.length > 0 ? argv : ["fixtures/sample"];

  let resultFiles: string[];
  try {
    resultFiles = await collectResultFiles(paths);
  } catch (err) {
    console.error(`error: ${err instanceof Error ? err.message : String(err)}`);
    return 1;
  }

  if (resultFiles.length === 0) {
    console.error(
      `error: no .xml or .json result files found in: ${paths.join(", ")}`,
    );
    return 1;
  }

  console.log(`Aggregating ${resultFiles.length} result file(s):`);
  for (const f of resultFiles) console.log(`  - ${f}`);
  console.log("");

  // Parse each file independently; a single malformed file is reported but does
  // not abort the whole run, so a partial matrix still produces a summary.
  const runs: TestRun[] = [];
  for (const file of resultFiles) {
    try {
      runs.push(await parseFile(file));
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      // GitHub Actions renders ::warning:: annotations in the run UI.
      console.error(`::warning::skipping "${file}": ${msg}`);
    }
  }

  if (runs.length === 0) {
    console.error("error: no result files could be parsed successfully.");
    return 1;
  }

  const agg = aggregate(runs);
  const markdown = renderMarkdown(agg);
  const machine = renderMachineSummary(agg);

  // Write the human-facing summary to the GitHub Actions job summary, if present.
  const summaryPath = process.env.GITHUB_STEP_SUMMARY;
  if (summaryPath) {
    try {
      await appendFile(summaryPath, markdown + "\n");
      console.log(`Wrote job summary to $GITHUB_STEP_SUMMARY (${summaryPath}).`);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      console.error(`::warning::could not write job summary: ${msg}`);
    }
  }

  // Echo the markdown to the log, then the machine-readable block.
  console.log("");
  console.log(markdown);
  console.log("");
  console.log(machine);

  return 0;
}

// Run only when executed directly (not when imported by tests).
if (import.meta.main) {
  const code = await main(Bun.argv.slice(2));
  process.exit(code);
}
