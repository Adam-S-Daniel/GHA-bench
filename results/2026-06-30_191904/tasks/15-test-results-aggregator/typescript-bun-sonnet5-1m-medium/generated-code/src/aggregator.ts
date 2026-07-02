// CLI entrypoint: aggregates JUnit XML + JSON test result files from a
// directory (simulating a GitHub Actions matrix build's downloaded
// artifacts), and writes a markdown summary suitable for GITHUB_STEP_SUMMARY.
//
// Usage: bun run src/aggregator.ts [resultsDir] [--strict]
//   resultsDir  Directory containing *.xml / *.json test result files.
//               Defaults to "test-results".
//   --strict    Exit with code 1 if any test failed (useful to fail the CI
//               job on aggregated failures across the whole matrix).

import { appendFile } from "node:fs/promises";
import { loadResultsFromDirectory } from "./loadResults";
import { aggregate } from "./aggregate";
import { generateMarkdownSummary } from "./report";

export interface RunOptions {
  resultsDir: string;
  strict: boolean;
}

export interface RunOutcome {
  markdown: string;
  exitCode: number;
}

export async function runAggregator(options: RunOptions): Promise<RunOutcome> {
  try {
    const files = await loadResultsFromDirectory(options.resultsDir);
    const result = aggregate(files);
    const markdown = generateMarkdownSummary(result);
    const exitCode = options.strict && result.totals.failed > 0 ? 1 : 0;
    return { markdown, exitCode };
  } catch (err) {
    const reason = err instanceof Error ? err.message : String(err);
    return { markdown: `# Test Results Summary ❌\n\nError: ${reason}\n`, exitCode: 1 };
  }
}

function parseArgs(argv: string[]): RunOptions {
  const strict = argv.includes("--strict");
  const resultsDir = argv.find((a) => !a.startsWith("--")) ?? "test-results";
  return { resultsDir, strict };
}

// Only run as a script when executed directly (not when imported by tests).
if (import.meta.main) {
  const options = parseArgs(Bun.argv.slice(2));
  const outcome = await runAggregator(options);

  console.log(outcome.markdown);

  const summaryPath = process.env.GITHUB_STEP_SUMMARY;
  if (summaryPath) {
    // GITHUB_STEP_SUMMARY is meant to be appended to, not overwritten.
    await appendFile(summaryPath, outcome.markdown + "\n");
  }

  process.exit(outcome.exitCode);
}
