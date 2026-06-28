#!/usr/bin/env bun
/**
 * PR Label Assigner — command-line interface.
 *
 * Reads a labeler config (path-to-label rules) and a list of changed file paths
 * (the "PR" being triaged), computes the label set, and prints it. Designed to
 * be driven from a GitHub Actions workflow: when `GITHUB_OUTPUT` /
 * `GITHUB_STEP_SUMMARY` are present it also writes a job output and a summary.
 *
 * Usage:
 *   bun run src/cli.ts --config <config.json> --files <files.json|.txt> \
 *       [--format text|json|csv]
 *
 * The first stdout line is always a stable, machine-readable marker:
 *   __PR_LABELS__=<comma-separated labels in priority order>
 * so CI pipelines (and our act-based test harness) can assert on it directly.
 */
import { parseArgs } from "node:util";
import { readFile, appendFile } from "node:fs/promises";
import {
  assignLabels,
  parseConfig,
  type LabelResult,
} from "./labeler.ts";

/** Stable marker prefix for the machine-readable output line. */
export const LABELS_MARKER = "__PR_LABELS__=";

const USAGE = `PR Label Assigner

Assign labels to a PR based on its changed file paths and configurable
glob-based path-to-label rules.

Usage:
  bun run src/cli.ts --config <config.json> --files <files> [--format <fmt>]

Options:
  --config <path>   Path to the labeler rules config (JSON). Required.
  --files  <path>   Path to the changed-files list. Either a JSON array of
                    strings or a newline-separated list (# comments allowed).
                    Required.
  --format <fmt>    Output format: text (default), json, or csv.
  --help            Show this help.
`;

/**
 * Parse a changed-files list from raw file content.
 *
 * Accepts either a JSON array of strings (content starting with '[') or a
 * newline-separated list where blank lines and lines beginning with '#' are
 * ignored. Returning a normalized string[] keeps fixtures flexible.
 */
export function parseFileList(content: string): string[] {
  const trimmed = content.trim();
  if (trimmed === "") return [];

  if (trimmed.startsWith("[")) {
    let data: unknown;
    try {
      data = JSON.parse(trimmed);
    } catch (err) {
      throw new Error(
        `changed-files JSON is not valid: ${(err as Error).message}`,
      );
    }
    if (!Array.isArray(data) || !data.every((x) => typeof x === "string")) {
      throw new Error("changed-files JSON must be an array of strings.");
    }
    return data;
  }

  return trimmed
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line !== "" && !line.startsWith("#"));
}

/** Render an evaluation result in the requested format. */
export function formatResult(result: LabelResult, format: string): string {
  switch (format) {
    case "csv":
      return result.labels.join(",");
    case "json":
      return JSON.stringify(result, null, 2);
    case "text": {
      const lines: string[] = [];
      lines.push("PR Label Assigner");
      lines.push("=================");
      if (result.labels.length === 0) {
        lines.push("No labels matched the changed files.");
        return lines.join("\n");
      }
      lines.push(
        `Labels applied (${result.labels.length}): ${result.labels.join(", ")}`,
      );
      lines.push("");
      for (const label of result.labels) {
        lines.push(`  ${label}`);
        for (const file of result.matches[label] ?? []) {
          lines.push(`    - ${file}`);
        }
      }
      return lines.join("\n");
    }
    default:
      throw new Error(
        `unknown --format "${format}" (expected text, json, or csv)`,
      );
  }
}

/** Read a file as UTF-8, mapping a missing file to a friendly error. */
async function readTextFile(path: string, kind: string): Promise<string> {
  try {
    return await readFile(path, "utf8");
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === "ENOENT") {
      throw new Error(`${kind} file not found: ${path}`);
    }
    throw new Error(`could not read ${kind} file "${path}": ${(err as Error).message}`);
  }
}

/**
 * Entry point. Returns the desired process exit code (0 success, 1 error,
 * 2 usage error). Accepting argv/env explicitly keeps `main` testable.
 */
export async function main(
  argv: string[],
  env: Record<string, string | undefined> = process.env,
): Promise<number> {
  let parsed;
  try {
    parsed = parseArgs({
      args: argv,
      options: {
        config: { type: "string" },
        files: { type: "string" },
        format: { type: "string", default: "text" },
        help: { type: "boolean", default: false },
      },
      allowPositionals: false,
    });
  } catch (err) {
    process.stderr.write(`Error: ${(err as Error).message}\n\n${USAGE}`);
    return 2;
  }

  const { config: configPath, files: filesPath, format, help } = parsed.values;

  if (help) {
    process.stdout.write(USAGE);
    return 0;
  }

  if (!configPath || !filesPath) {
    process.stderr.write(
      "Error: both --config and --files are required.\n\n" + USAGE,
    );
    return 2;
  }

  try {
    // --- Load and validate the config ---
    const configRaw = await readTextFile(configPath, "config");
    let configJson: unknown;
    try {
      configJson = JSON.parse(configRaw);
    } catch (err) {
      throw new Error(
        `config file "${configPath}" is not valid JSON: ${(err as Error).message}`,
      );
    }
    const config = parseConfig(configJson);

    // --- Load the changed-files list ---
    const filesRaw = await readTextFile(filesPath, "changed-files");
    const files = parseFileList(filesRaw);

    // --- Evaluate ---
    const result = assignLabels(config, files);
    const csv = result.labels.join(",");

    // Machine-readable marker line first, so pipelines can grep it reliably.
    process.stdout.write(`${LABELS_MARKER}${csv}\n`);
    process.stdout.write(formatResult(result, format ?? "text") + "\n");

    // --- GitHub Actions integration (no-ops outside CI) ---
    if (env.GITHUB_OUTPUT) {
      await appendFile(
        env.GITHUB_OUTPUT,
        `labels=${csv}\ncount=${result.labels.length}\n`,
      );
    }
    if (env.GITHUB_STEP_SUMMARY) {
      await appendFile(env.GITHUB_STEP_SUMMARY, renderSummary(result));
    }

    return 0;
  } catch (err) {
    process.stderr.write(`Error: ${(err as Error).message}\n`);
    return 1;
  }
}

/** Build a Markdown job summary for the GitHub Actions step summary. */
function renderSummary(result: LabelResult): string {
  const lines: string[] = [];
  lines.push("## PR Label Assigner");
  lines.push("");
  if (result.labels.length === 0) {
    lines.push("_No labels matched the changed files._");
    lines.push("");
    return lines.join("\n");
  }
  lines.push(`**Labels (${result.labels.length}):** ${result.labels.join(", ")}`);
  lines.push("");
  lines.push("| Label | Matched files |");
  lines.push("| ----- | ------------- |");
  for (const label of result.labels) {
    const files = (result.matches[label] ?? []).join("<br>");
    lines.push(`| ${label} | ${files} |`);
  }
  lines.push("");
  return lines.join("\n");
}

// Only execute when run directly (not when imported by tests).
if (import.meta.main) {
  main(process.argv.slice(2)).then((code) => process.exit(code));
}
