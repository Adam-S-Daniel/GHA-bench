/**
 * Test-results aggregator CLI.
 *
 * Usage:
 *   bun run src/cli.ts --dir <results-dir> [--out <summary.md>]
 *
 * Reads every *.xml (JUnit) and *.json (JSON results) file in the directory,
 * aggregates totals + flaky tests, and:
 *   - prints the markdown summary to stdout
 *   - prints one machine-readable line:  RESULT total=.. passed=.. ...
 *   - writes the summary to --out (if given)
 *   - appends the summary to $GITHUB_STEP_SUMMARY (if set, i.e. inside CI)
 *
 * Exit codes: 0 success, 1 usage/parse error.
 */
import {
  appendFileSync,
  readdirSync,
  readFileSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { extname, join } from "node:path";
import { aggregate } from "./aggregate";
import { parseJUnitXml } from "./junit";
import { parseJsonResults } from "./jsonResults";
import { renderMarkdownSummary } from "./markdown";
import type { AggregateSummary, TestFileResult } from "./types";

/**
 * Parse every recognized result file in `dir` (sorted by name so output is
 * deterministic). *.xml -> JUnit, *.json -> JSON results; other files are
 * ignored. Throws with the directory or file name on any problem.
 */
export function collectResults(dir: string): TestFileResult[] {
  let entries: string[];
  try {
    if (!statSync(dir).isDirectory()) throw new Error("not a directory");
    entries = readdirSync(dir).sort();
  } catch {
    throw new Error(`"${dir}" is not a readable directory`);
  }

  const results: TestFileResult[] = [];
  for (const entry of entries) {
    const ext = extname(entry).toLowerCase();
    if (ext !== ".xml" && ext !== ".json") continue;
    const text = readFileSync(join(dir, entry), "utf8");
    results.push(
      ext === ".xml" ? parseJUnitXml(text, entry) : parseJsonResults(text, entry),
    );
  }
  return results;
}

/** Stable single-line form of the summary for log-based assertions. */
export function resultLine(summary: AggregateSummary): string {
  return (
    `RESULT total=${summary.total} passed=${summary.passed} ` +
    `failed=${summary.failed} skipped=${summary.skipped} ` +
    `duration=${summary.durationSec.toFixed(2)} flaky=${summary.flaky.length}`
  );
}

/** Minimal flag parser for --dir / --out. */
function parseArgs(argv: string[]): { dir?: string; out?: string } {
  const opts: { dir?: string; out?: string } = {};
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--dir") opts.dir = argv[++i];
    else if (argv[i] === "--out") opts.out = argv[++i];
    else throw new Error(`Unknown argument "${argv[i]}"`);
  }
  return opts;
}

function main(argv: string[]): number {
  let opts: { dir?: string; out?: string };
  try {
    opts = parseArgs(argv);
  } catch (err) {
    console.error(err instanceof Error ? err.message : String(err));
    console.error("Usage: bun run src/cli.ts --dir <results-dir> [--out <summary.md>]");
    return 1;
  }
  if (!opts.dir) {
    console.error("Usage: bun run src/cli.ts --dir <results-dir> [--out <summary.md>]");
    return 1;
  }

  let markdown: string;
  let summary: AggregateSummary;
  try {
    const files = collectResults(opts.dir);
    summary = aggregate(files);
    markdown = renderMarkdownSummary(summary);
  } catch (err) {
    console.error(`Error: ${err instanceof Error ? err.message : String(err)}`);
    return 1;
  }

  console.log(markdown);
  console.log(resultLine(summary));

  if (opts.out) writeFileSync(opts.out, markdown);

  // Inside GitHub Actions, also publish the summary to the job summary page.
  const stepSummary = process.env["GITHUB_STEP_SUMMARY"];
  if (stepSummary) appendFileSync(stepSummary, markdown);

  return 0;
}

// Only run when invoked directly (not when imported by tests).
if (import.meta.main) {
  process.exit(main(process.argv.slice(2)));
}
