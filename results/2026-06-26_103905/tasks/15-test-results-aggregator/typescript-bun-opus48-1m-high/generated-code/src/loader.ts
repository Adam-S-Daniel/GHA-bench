/**
 * Filesystem layer: resolve input paths to concrete result files, read them,
 * parse each, and aggregate. This is the only module that touches the disk, so
 * the parser/aggregator/summary modules stay pure and trivially testable.
 */

import { readdir, stat, readFile } from "node:fs/promises";
import { join } from "node:path";
import { parseContent } from "./parser.ts";
import { aggregate } from "./aggregator.ts";
import type { AggregateResult, TestRun } from "./types.ts";

/** File extensions we know how to parse. */
const SUPPORTED = [".xml", ".json"];

function isSupported(name: string): boolean {
  const lower = name.toLowerCase();
  return SUPPORTED.some((ext) => lower.endsWith(ext));
}

/**
 * Expand a list of paths (files and/or directories) into a flat, sorted list
 * of concrete result-file paths. Directories are scanned (non-recursively) for
 * supported extensions; explicit file paths are kept as-is. A missing path is
 * a hard error so a typo'd input never silently aggregates to nothing.
 */
export async function collectResultFiles(paths: string[]): Promise<string[]> {
  const files: string[] = [];

  for (const path of paths) {
    let info;
    try {
      info = await stat(path);
    } catch {
      throw new Error(`Input path not found: "${path}" (no such file or directory)`);
    }

    if (info.isDirectory()) {
      const entries = await readdir(path);
      for (const entry of entries.sort()) {
        if (isSupported(entry)) files.push(join(path, entry));
      }
    } else if (isSupported(path)) {
      files.push(path);
    } else {
      throw new Error(
        `Unsupported file format for "${path}". Supported extensions: ${SUPPORTED.join(", ")}`,
      );
    }
  }

  return files;
}

/** Read and parse a single result file into a `TestRun`. */
export async function loadRun(filePath: string): Promise<TestRun> {
  const content = await readFile(filePath, "utf8");
  // Use just the basename as the run name so reports are path-independent.
  const baseName = filePath.split("/").pop() ?? filePath;
  return parseContent(content, baseName);
}

/**
 * Full pipeline over a set of input paths: collect -> load+parse each ->
 * aggregate. Returns the `AggregateResult` ready to render.
 */
export async function aggregatePaths(paths: string[]): Promise<AggregateResult> {
  const files = await collectResultFiles(paths);
  if (files.length === 0) {
    throw new Error(
      `No result files found in: ${paths.join(", ")}. ` +
        `Expected at least one ${SUPPORTED.join(" or ")} file.`,
    );
  }

  const runs: TestRun[] = [];
  for (const file of files) {
    runs.push(await loadRun(file));
  }
  return aggregate(runs);
}
