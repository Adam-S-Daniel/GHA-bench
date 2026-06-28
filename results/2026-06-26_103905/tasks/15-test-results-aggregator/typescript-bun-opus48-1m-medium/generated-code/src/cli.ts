// Command-line entry point.
//
// Usage:
//   bun run src/cli.ts <file1> <file2> ... [--out summary.md]
//
// Reads each result file, parses it by extension, aggregates, renders a
// markdown summary, prints it, and (in CI) appends it to the file named by
// $GITHUB_STEP_SUMMARY. Exits nonzero if any test failed so the CI job fails.

import { aggregate } from "./aggregator.ts";
import { parseContent } from "./parser.ts";
import { renderSummary } from "./summary.ts";
import type { Aggregation, ParsedFile } from "./types.ts";

export interface CliResult {
  markdown: string;
  aggregation: Aggregation;
  exitCode: number;
}

export interface CliOptions {
  /** Path to write the markdown summary to (defaults to $GITHUB_STEP_SUMMARY). */
  summaryFile?: string;
}

/**
 * Core CLI logic, separated from process wiring so it is unit-testable.
 * Reads + parses each file, aggregates, renders markdown, optionally writes a
 * summary file, and computes the exit code.
 */
export async function runCli(
  files: string[],
  opts: CliOptions = {},
): Promise<CliResult> {
  if (files.length === 0) {
    throw new Error(
      "No input files provided. Usage: bun run src/cli.ts <file1> <file2> ...",
    );
  }

  const parsed: ParsedFile[] = [];
  for (const path of files) {
    const file = Bun.file(path);
    let content: string;
    try {
      content = await file.text();
    } catch (err) {
      throw new Error(`Could not read file "${path}": ${(err as Error).message}`);
    }
    try {
      parsed.push({ source: path, results: parseContent(path, content) });
    } catch (err) {
      // Wrap parse errors with the offending filename for actionable output.
      throw new Error(`Failed to parse "${path}": ${(err as Error).message}`);
    }
  }

  const aggregation = aggregate(parsed);
  const markdown = renderSummary(aggregation);

  // Write the summary to the GitHub step-summary file when available.
  const summaryFile = opts.summaryFile ?? process.env.GITHUB_STEP_SUMMARY;
  if (summaryFile) {
    await Bun.write(summaryFile, markdown);
  }

  const exitCode = aggregation.totals.failed > 0 ? 1 : 0;
  return { markdown, aggregation, exitCode };
}

// Direct-invocation guard: only run when executed as a script, not when
// imported by tests.
if (import.meta.main) {
  // Flags:
  //   --out <path>  write the summary to <path> (defaults to $GITHUB_STEP_SUMMARY)
  //   --no-fail     always exit 0 (reporting shouldn't fail the reporting job;
  //                 a downstream gate job can decide based on the summary)
  const argv = process.argv.slice(2);
  const files: string[] = [];
  let out: string | undefined;
  let noFail = false;
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--out") {
      out = argv[++i];
    } else if (argv[i] === "--no-fail") {
      noFail = true;
    } else {
      files.push(argv[i]);
    }
  }

  try {
    const { markdown, exitCode } = await runCli(files, { summaryFile: out });
    // Always print the summary to stdout for log visibility.
    console.log(markdown);
    process.exit(noFail ? 0 : exitCode);
  } catch (err) {
    console.error(`Error: ${(err as Error).message}`);
    process.exit(2);
  }
}
