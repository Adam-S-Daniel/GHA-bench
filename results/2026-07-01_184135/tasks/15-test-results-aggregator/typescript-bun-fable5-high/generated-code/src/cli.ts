/**
 * CLI entry point: aggregate every test-result file in a directory and emit a
 * GitHub Actions job summary.
 *
 * Usage:
 *   bun run src/cli.ts <results-dir> [--out <file.md>]
 *
 * Behavior:
 *   - .xml files are parsed as JUnit reports, .json files with our JSON
 *     schema; other extensions are ignored.
 *   - Prints a stable machine-readable AGGREGATE_RESULT line (the act test
 *     harness asserts exact values on it), one FLAKY_TEST line per flaky
 *     test, then the markdown summary.
 *   - Appends the markdown to $GITHUB_STEP_SUMMARY when running in Actions.
 *   - Exits 0 even when tests failed: this tool is a *reporter*; gating the
 *     build on failures belongs to the test jobs themselves.
 */
import { readdir, stat } from "node:fs/promises";
import { join } from "node:path";
import { aggregate } from "./aggregate";
import { renderMarkdownSummary } from "./markdown";
import { parseJUnitXml } from "./parsers/junit";
import { parseJsonResults } from "./parsers/json";
import type { AggregateReport, TestRun } from "./types";

/** Find aggregatable result files (.xml / .json) in a directory, sorted for determinism. */
export async function discoverResultFiles(dir: string): Promise<string[]> {
  try {
    const s = await stat(dir);
    if (!s.isDirectory()) throw new Error(`${dir}: not a directory`);
  } catch (err) {
    if (err instanceof Error && err.message.includes("not a directory")) throw err;
    throw new Error(`${dir}: does not exist or is not readable`);
  }

  const entries = await readdir(dir);
  const files = entries
    .filter((name) => name.endsWith(".xml") || name.endsWith(".json"))
    .sort()
    .map((name) => join(dir, name));

  if (files.length === 0) {
    throw new Error(`${dir}: no .xml or .json result files found`);
  }
  return files;
}

/** Parse one result file, choosing the parser by extension. */
export async function parseResultFile(path: string): Promise<TestRun> {
  const source = path.split("/").pop() ?? path;
  const content = await Bun.file(path).text();
  return path.endsWith(".xml") ? parseJUnitXml(content, source) : parseJsonResults(content, source);
}

/** End-to-end: discover, parse and aggregate every result file in a directory. */
export async function aggregateDirectory(dir: string): Promise<AggregateReport> {
  const files = await discoverResultFiles(dir);
  const runs = await Promise.all(files.map(parseResultFile));
  return aggregate(runs);
}

/** The exact one-line result the act harness greps for and asserts on. */
export function machineLine(report: AggregateReport): string {
  const t = report.totals;
  return (
    `AGGREGATE_RESULT total=${t.total} passed=${t.passed} failed=${t.failed} ` +
    `skipped=${t.skipped} duration=${t.durationSeconds.toFixed(2)}s flaky=${report.flaky.length}`
  );
}

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  const outFlag = args.indexOf("--out");
  const outFile = outFlag !== -1 ? args[outFlag + 1] : undefined;
  const positional = args.filter((_, i) => outFlag === -1 || (i !== outFlag && i !== outFlag + 1));
  const dir = positional[0] ?? "results";

  const report = await aggregateDirectory(dir);
  const markdown = renderMarkdownSummary(report);

  console.log(machineLine(report));
  for (const flakyTest of report.flaky) console.log(`FLAKY_TEST ${flakyTest.id}`);
  console.log("");
  console.log(markdown);

  if (outFile !== undefined) await Bun.write(outFile, markdown);

  // Inside GitHub Actions (and act), append to the job summary.
  const summaryPath = process.env["GITHUB_STEP_SUMMARY"];
  if (summaryPath) {
    const existing = await Bun.file(summaryPath)
      .text()
      .catch(() => "");
    await Bun.write(summaryPath, existing + markdown + "\n");
  }
}

if (import.meta.main) {
  main().catch((err: unknown) => {
    console.error(`test-results-aggregator: ${err instanceof Error ? err.message : String(err)}`);
    process.exit(1);
  });
}
