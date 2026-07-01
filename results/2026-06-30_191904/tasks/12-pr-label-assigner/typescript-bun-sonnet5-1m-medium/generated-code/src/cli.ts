import { existsSync, readFileSync } from "node:fs";
import { assignLabels } from "./labeler";
import type { LabelRule } from "./types";

/** Reads and validates the path-to-label rule configuration from a JSON file. */
export function readRules(path: string): LabelRule[] {
  const parsed = readJsonFile(path);
  if (!Array.isArray(parsed)) {
    throw new Error(`Rules file "${path}" must contain a JSON array of rule objects.`);
  }
  return parsed as LabelRule[];
}

/** Reads a mocked/fixture list of changed file paths from a JSON file. */
export function readChangedFiles(path: string): string[] {
  const parsed = readJsonFile(path);
  if (!Array.isArray(parsed) || !parsed.every((item) => typeof item === "string")) {
    throw new Error(`Fixture file "${path}" must contain a JSON array of file paths (strings).`);
  }
  return parsed as string[];
}

/** Computes the sorted, final label set for a fixture's changed files against a rules config. */
export function computeLabelsForFixture(fixturePath: string, rulesPath: string): string[] {
  const files = readChangedFiles(fixturePath);
  const rules = readRules(rulesPath);
  return assignLabels(files, rules).sort();
}

function readJsonFile(path: string): unknown {
  if (!existsSync(path)) {
    throw new Error(`File not found: "${path}". No such file or directory.`);
  }
  const contents = readFileSync(path, "utf-8");
  try {
    return JSON.parse(contents);
  } catch {
    throw new Error(`File "${path}" does not contain valid JSON.`);
  }
}

// Entry point when invoked directly via `bun run src/cli.ts <fixturePath> [rulesPath]`.
if (import.meta.main) {
  const fixturePath = process.argv[2];
  const rulesPath = process.argv[3] ?? "rules.json";

  if (!fixturePath) {
    console.error("Usage: bun run src/cli.ts <fixturePath> [rulesPath]");
    process.exit(1);
  }

  try {
    const labels = computeLabelsForFixture(fixturePath, rulesPath);
    console.log(`Changed files fixture: ${fixturePath}`);
    console.log(`Rules file: ${rulesPath}`);
    console.log(`LABELS=${JSON.stringify(labels)}`);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(`Error: ${message}`);
    process.exit(1);
  }
}
