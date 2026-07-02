/**
 * CLI entry point: `bun run src/cli.ts <config.json>`
 *
 * Reads a matrix configuration file, generates the build matrix, and
 * prints the complete matrix JSON (strategy + expanded combinations +
 * count) to stdout. All failures go to stderr with exit code 1 so CI
 * steps fail loudly and with a human-readable reason.
 */
import { readFileSync } from "node:fs";
import { generateMatrix, MatrixError } from "./matrix";
import type { MatrixConfig } from "./matrix";

function fail(message: string): never {
  console.error(`error: ${message}`);
  process.exit(1);
}

function main(argv: string[]): void {
  const configPath: string | undefined = argv[0];
  if (!configPath) {
    fail("Usage: bun run src/cli.ts <config.json>");
  }

  let raw: string;
  try {
    raw = readFileSync(configPath, "utf-8");
  } catch (err) {
    fail(`Cannot read config file "${configPath}": ${(err as Error).message}`);
  }

  let config: MatrixConfig;
  try {
    config = JSON.parse(raw) as MatrixConfig;
  } catch {
    fail(`Config file "${configPath}" is not valid JSON`);
  }

  try {
    const result = generateMatrix(config);
    // Single-line JSON: easy to parse from CI logs and to feed into
    // `fromJSON()` in a downstream GitHub Actions job.
    console.log(JSON.stringify(result));
  } catch (err) {
    if (err instanceof MatrixError) {
      fail(err.message);
    }
    throw err; // unexpected bugs should crash with a stack trace
  }
}

main(process.argv.slice(2));
