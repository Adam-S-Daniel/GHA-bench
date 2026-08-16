import { generateMatrix } from "./matrix";
import { readFileSync } from "fs";

interface CLIOptions {
  config?: string;
  output?: string;
}

// Parse command-line arguments
function parseArgs(): CLIOptions {
  const args = process.argv.slice(2);
  const opts: CLIOptions = {};

  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--config" && i + 1 < args.length) {
      opts.config = args[i + 1];
      i++;
    } else if (args[i] === "--output" && i + 1 < args.length) {
      opts.output = args[i + 1];
      i++;
    }
  }

  return opts;
}

// Load configuration from file or parse JSON string
function loadConfig(configPath: string): Record<string, unknown> {
  try {
    // Try to read as file first
    const content = readFileSync(configPath, "utf-8");
    return JSON.parse(content);
  } catch {
    // If file read fails, try to parse as JSON string directly
    try {
      return JSON.parse(configPath);
    } catch (parseErr) {
      throw new Error(
        `Failed to load config from file or parse as JSON: ${configPath}`
      );
    }
  }
}

// Main CLI function
export async function main() {
  try {
    const opts = parseArgs();

    if (!opts.config) {
      console.error("Usage: bun run cli.ts --config <file-or-json> [--output <file>]");
      console.error("  --config: Path to JSON config file or JSON string");
      console.error("  --output: Output file (default: stdout)");
      process.exit(1);
    }

    const config = loadConfig(opts.config);
    const matrix = generateMatrix(config);
    const output = JSON.stringify(matrix, null, 2);

    if (opts.output) {
      await Bun.write(opts.output, output);
      console.log(`Matrix written to ${opts.output}`);
    } else {
      console.log(output);
    }
  } catch (error) {
    if (error instanceof Error) {
      console.error(`Error: ${error.message}`);
    } else {
      console.error("Unknown error occurred");
    }
    process.exit(1);
  }
}

main();
