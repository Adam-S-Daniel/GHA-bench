import { existsSync, readFileSync } from "node:fs";
import { formatJson, formatMarkdown } from "./formatters";
import { generateReport } from "./report";
import type { SecretsFile } from "./types";

export type OutputFormat = "markdown" | "json";

export interface RunOptions {
  configPath: string;
  format: OutputFormat;
  warningWindowDays: number;
  now?: Date;
}

/** Read and parse a secrets config JSON file, with meaningful error messages. */
export function loadConfigFromFile(path: string): SecretsFile {
  if (!existsSync(path)) {
    throw new Error(`Config file not found (ENOENT): ${path}`);
  }
  const raw = readFileSync(path, "utf-8");
  try {
    return JSON.parse(raw) as SecretsFile;
  } catch (err) {
    throw new Error(
      `Failed to parse config file "${path}" as JSON: ${(err as Error).message}`
    );
  }
}

export function run(options: RunOptions): string {
  const config = loadConfigFromFile(options.configPath);
  const report = generateReport(config, {
    now: options.now,
    warningWindowDays: options.warningWindowDays,
  });

  switch (options.format) {
    case "json":
      return formatJson(report);
    case "markdown":
      return formatMarkdown(report);
    default:
      throw new Error(
        `Unsupported output format: "${options.format}". Expected "markdown" or "json".`
      );
  }
}

// CLI entrypoint: `bun run src/cli.ts [configPath] [--format=json|markdown] [--warning-window=N]`
function parseArgs(argv: string[]): RunOptions {
  let configPath = "secrets.config.json";
  let format: OutputFormat = "markdown";
  let warningWindowDays = 14;

  for (const arg of argv) {
    if (arg.startsWith("--format=")) {
      const value = arg.split("=")[1];
      if (value !== "json" && value !== "markdown") {
        throw new Error(`Invalid --format value: "${value}". Expected "markdown" or "json".`);
      }
      format = value;
    } else if (arg.startsWith("--warning-window=")) {
      const value = Number(arg.split("=")[1]);
      if (!Number.isFinite(value) || value < 0) {
        throw new Error(`Invalid --warning-window value: "${arg.split("=")[1]}"`);
      }
      warningWindowDays = value;
    } else if (!arg.startsWith("--")) {
      configPath = arg;
    }
  }

  return { configPath, format, warningWindowDays };
}

if (import.meta.main) {
  try {
    const options = parseArgs(process.argv.slice(2));
    const output = run(options);
    console.log(output);
  } catch (err) {
    console.error(`Error: ${(err as Error).message}`);
    process.exit(1);
  }
}
