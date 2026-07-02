#!/usr/bin/env bun
// CLI entry point for the PR label assigner.
//
// Reads a path-to-label rule config and a changed-files list (both file
// paths are configurable via flags, with defaults matching the fixtures
// shipped in this repo), computes the label set, and prints it in a
// machine-parseable "LABELS=a,b,c" line that a GitHub Actions step can grep
// out of the job log and expose as a step output.
import { assignLabels, parseChangedFiles, parseConfig } from "./labeler";

/** Parsed CLI flags. */
export interface CliArgs {
  configPath: string;
  filesPath: string;
}

const DEFAULT_CONFIG_PATH = ".github/labeler-config.json";
const DEFAULT_FILES_PATH = "fixtures/changed-files.txt";

/**
 * Parses `--config <path>` and `--files <path>` flags, defaulting to the
 * repo's standard config/fixture locations. Throws a descriptive error for
 * unknown flags or a flag with no value.
 */
export function parseArgs(argv: string[]): CliArgs {
  let configPath = DEFAULT_CONFIG_PATH;
  let filesPath = DEFAULT_FILES_PATH;

  for (let i = 0; i < argv.length; i++) {
    const flag = argv[i];
    if (flag === "--config" || flag === "--files") {
      const value = argv[i + 1];
      if (value === undefined) {
        throw new Error(`parseArgs: ${flag} requires a value`);
      }
      if (flag === "--config") configPath = value;
      else filesPath = value;
      i++;
    } else {
      throw new Error(`parseArgs: unrecognized flag "${flag}"`);
    }
  }

  return { configPath, filesPath };
}

/** Formats the final label list as the "LABELS=a,b,c" line the workflow greps for. */
export function formatLabelsLine(labels: string[]): string {
  return `LABELS=${labels.join(",")}`;
}

async function main(): Promise<void> {
  const { configPath, filesPath } = parseArgs(process.argv.slice(2));

  const [configText, filesText] = await Promise.all([
    Bun.file(configPath)
      .text()
      .catch((err: unknown) => {
        throw new Error(
          `Could not read config file "${configPath}": ${
            err instanceof Error ? err.message : String(err)
          }`,
        );
      }),
    Bun.file(filesPath)
      .text()
      .catch((err: unknown) => {
        throw new Error(
          `Could not read changed-files list "${filesPath}": ${
            err instanceof Error ? err.message : String(err)
          }`,
        );
      }),
  ]);

  const rules = parseConfig(configText);
  const files = parseChangedFiles(filesText);
  const labels = assignLabels(files, rules);

  console.log(`Config:  ${configPath} (${rules.length} rule(s))`);
  console.log(`Files:   ${filesPath} (${files.length} changed file(s))`);
  console.log(formatLabelsLine(labels));
}

// Only run when executed directly (`bun run src/cli.ts`), not when imported
// by tests.
if (import.meta.main) {
  main().catch((err: unknown) => {
    console.error(`pr-label-assigner: ${err instanceof Error ? err.message : String(err)}`);
    process.exit(1);
  });
}
