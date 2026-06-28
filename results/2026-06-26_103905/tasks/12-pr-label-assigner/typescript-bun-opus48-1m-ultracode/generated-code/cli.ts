#!/usr/bin/env bun
// CLI entrypoint for the PR label assigner.
//
// This is the surface the GitHub Actions workflow drives. It loads a rule
// config and a "changed files" list (the mocked PR), assigns labels, and prints
// both a human-readable summary and two machine-readable marker lines that CI
// (and our `act` harness) parse:
//
//     RESULT_LABELS=<comma-separated labels, in final order>
//     RESULT_COUNT=<number of labels>
//
// Inputs are resolved in this order (most specific wins):
//   1. positional args:  bun run cli.ts <configPath> <changedFilesPath>
//   2. environment:      LABELER_CONFIG, CHANGED_FILES_FILE
//   3. defaults:         labeler.config.json, changed-files.txt
//
// All errors are reported to stderr with an actionable message and a non-zero
// exit code, so a misconfigured pipeline fails loudly instead of silently
// labelling nothing.

import { assignLabels, loadChangedFiles, loadConfig } from "./src/labeler.ts";

function resolveInputPaths(argv: string[]): { configPath: string; filesPath: string } {
  const [configArg, filesArg] = argv.slice(2);
  const configPath = configArg ?? process.env.LABELER_CONFIG ?? "labeler.config.json";
  const filesPath = filesArg ?? process.env.CHANGED_FILES_FILE ?? "changed-files.txt";
  return { configPath, filesPath };
}

function main(): number {
  const { configPath, filesPath } = resolveInputPaths(process.argv);

  // Load + validate inputs. Any failure throws a descriptive Error which we
  // surface below; we don't want a stack trace, just the message.
  const config = loadConfig(configPath);
  const files = loadChangedFiles(filesPath);

  const result = assignLabels(files, config);

  // ---- Human-readable summary (stdout) ----
  console.log("PR Label Assigner");
  console.log("=================");
  console.log(`Config:        ${configPath} (${config.rules.length} rule(s))`);
  console.log(`Changed files: ${filesPath} (${files.length} file(s))`);
  console.log("");
  console.log("Per-file labels:");
  for (const file of files) {
    const labels = result.byFile[file] ?? [];
    console.log(`  ${file} -> ${labels.length ? labels.join(", ") : "(none)"}`);
  }
  console.log("");
  console.log(`Final label set (${result.labels.length}): ${result.labels.join(", ") || "(none)"}`);
  console.log("");

  // ---- Machine-readable markers (stdout) ----
  // Kept on their own lines with stable prefixes so CI / the act harness can
  // grep them out of the surrounding log noise.
  console.log(`RESULT_LABELS=${result.labels.join(",")}`);
  console.log(`RESULT_COUNT=${result.labels.length}`);

  return 0;
}

try {
  process.exit(main());
} catch (err) {
  const message = err instanceof Error ? err.message : String(err);
  console.error(`Error: ${message}`);
  process.exit(1);
}
