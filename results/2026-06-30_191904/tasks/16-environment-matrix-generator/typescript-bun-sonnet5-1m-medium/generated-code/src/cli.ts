#!/usr/bin/env bun
// CLI entry point: reads a MatrixConfig JSON file (path given as argv[2]) and
// prints the generated GitHub Actions strategy.matrix JSON to stdout.
import { generateMatrix, type MatrixConfig } from "./matrix-generator";

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  const compact = args.includes("--compact");
  const configPath = args.find((arg) => arg !== "--compact");

  if (!configPath) {
    throw new Error("Missing required argument: path to config JSON file.");
  }

  const file = Bun.file(configPath);
  if (!(await file.exists())) {
    throw new Error(`Config file not found: ${configPath}`);
  }

  let rawText: string;
  try {
    rawText = await file.text();
  } catch (err) {
    throw new Error(`Failed to read config file ${configPath}: ${(err as Error).message}`);
  }

  let config: MatrixConfig;
  try {
    config = JSON.parse(rawText);
  } catch (err) {
    throw new Error(`Config file ${configPath} is not valid JSON: ${(err as Error).message}`);
  }

  const result = generateMatrix(config);

  if (compact) {
    // Single-line JSON of just the matrix object, suitable for piping into
    // GITHUB_OUTPUT and consuming via `fromJson(...)` in a downstream job.
    console.log(JSON.stringify(result.matrix));
  } else {
    console.log(JSON.stringify(result, null, 2));
  }
}

main().catch((err: Error) => {
  console.error(`Error: ${err.message}`);
  process.exit(1);
});
