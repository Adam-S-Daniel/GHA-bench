#!/usr/bin/env bun
import { appendFile, readdir, stat } from "node:fs/promises";
import { join } from "node:path";
import { parseJUnitXml } from "./parsers/junit";
import { parseJsonResults } from "./parsers/json";
import { aggregate } from "./aggregator";
import { generateMarkdownSummary } from "./markdown";
import type { AggregatedResults, TestSuiteResult } from "./types";

/**
 * Expands a mix of file and directory paths into a sorted list of concrete
 * test result files. Directories are scanned (non-recursively) for .xml/.json
 * files; explicit file paths are passed through unchanged.
 */
export async function resolveInputFiles(paths: string[]): Promise<string[]> {
  const resolved: string[] = [];

  for (const path of paths) {
    let stats;
    try {
      stats = await stat(path);
    } catch {
      throw new Error(`Input path "${path}" does not exist`);
    }

    if (stats.isDirectory()) {
      const entries = await readdir(path);
      const matched = entries
        .filter((entry) => entry.endsWith(".xml") || entry.endsWith(".json"))
        .sort()
        .map((entry) => join(path, entry));
      resolved.push(...matched);
    } else {
      resolved.push(path);
    }
  }

  return resolved;
}

/** Parses a single result file, dispatching on file extension. */
async function parseFile(path: string): Promise<TestSuiteResult> {
  if (path.endsWith(".xml")) {
    const raw = await Bun.file(path).text();
    return parseJUnitXml(raw, path);
  }
  if (path.endsWith(".json")) {
    const raw = await Bun.file(path).text();
    return parseJsonResults(raw, path);
  }
  throw new Error(`Unsupported file extension for "${path}" (expected .xml or .json)`);
}

/** Parses and aggregates a list of test result files, producing a markdown report. */
export async function runAggregation(
  files: string[],
): Promise<{ aggregated: AggregatedResults; markdown: string }> {
  const suites = await Promise.all(files.map(parseFile));
  const aggregated = aggregate(suites);
  const markdown = generateMarkdownSummary(aggregated);
  return { aggregated, markdown };
}

/** Plain-text summary lines, easy to grep from CI logs or shell scripts. */
export function formatTextSummary(result: AggregatedResults): string {
  return [
    "=== Test Results Summary ===",
    `Total Tests: ${result.totalTests}`,
    `Passed: ${result.passed}`,
    `Failed: ${result.failed}`,
    `Skipped: ${result.skipped}`,
    `Duration: ${result.totalDuration.toFixed(3)}s`,
    `Flaky Tests: ${result.flakyTests.length}`,
  ].join("\n");
}

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  const summaryOutIndex = args.indexOf("--summary-out");
  let summaryOutPath: string | undefined;
  let inputArgs = args;

  if (summaryOutIndex !== -1) {
    summaryOutPath = args[summaryOutIndex + 1];
    if (!summaryOutPath) {
      throw new Error("--summary-out requires a file path argument");
    }
    inputArgs = [...args.slice(0, summaryOutIndex), ...args.slice(summaryOutIndex + 2)];
  }

  const inputPaths = inputArgs.length > 0 ? inputArgs : ["fixtures"];

  const files = await resolveInputFiles(inputPaths);
  if (files.length === 0) {
    throw new Error(`No .xml or .json test result files found in: ${inputPaths.join(", ")}`);
  }

  const { aggregated, markdown } = await runAggregation(files);

  console.log(formatTextSummary(aggregated));

  if (summaryOutPath) {
    await appendFile(summaryOutPath, `${markdown}\n`);
  }
}

if (import.meta.main) {
  main().catch((err) => {
    console.error(`test-results-aggregator: ${(err as Error).message}`);
    process.exit(1);
  });
}
