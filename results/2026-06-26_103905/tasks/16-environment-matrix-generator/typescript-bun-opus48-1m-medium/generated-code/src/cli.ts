#!/usr/bin/env bun
/**
 * CLI entry point for the environment matrix generator.
 *
 * Usage:
 *   bun run src/cli.ts <config.json> [--pretty]
 *
 * Reads a JSON configuration file, generates the GitHub Actions strategy matrix
 * and prints it as JSON to stdout. On any error it prints a meaningful message
 * to stderr and exits with a non-zero status code.
 *
 * When the environment variable `GITHUB_OUTPUT` is set (as it is inside a GitHub
 * Actions / act runner), the generated matrix is additionally appended there as
 * a `matrix=<json>` output so downstream jobs can consume it via `fromJSON`.
 */

import { readFileSync, appendFileSync } from "node:fs";
import { generateMatrix, type MatrixConfig } from "./matrix";

function fail(message: string): never {
  process.stderr.write(`error: ${message}\n`);
  process.exit(1);
}

function main(): void {
  const args = process.argv.slice(2);
  const pretty = args.includes("--pretty");
  const configPath = args.find((a) => !a.startsWith("--"));

  if (!configPath) {
    process.stderr.write("usage: bun run src/cli.ts <config.json> [--pretty]\n");
    process.exit(2);
  }

  // Read and parse the configuration file.
  let raw: string;
  try {
    raw = readFileSync(configPath, "utf8");
  } catch {
    fail(`could not read config file: ${configPath}`);
  }

  let config: MatrixConfig;
  try {
    config = JSON.parse(raw) as MatrixConfig;
  } catch (err) {
    fail(`config file is not valid JSON: ${(err as Error).message}`);
  }

  // Generate the matrix; generateMatrix throws meaningful, typed errors.
  let strategy;
  try {
    strategy = generateMatrix(config);
  } catch (err) {
    fail((err as Error).message);
  }

  const json = JSON.stringify(strategy, null, pretty ? 2 : 0);
  process.stdout.write(json + "\n");

  // Expose the matrix as a step output when running inside GitHub Actions/act.
  const githubOutput = process.env.GITHUB_OUTPUT;
  if (githubOutput) {
    const compact = JSON.stringify(strategy.matrix);
    appendFileSync(githubOutput, `matrix=${compact}\n`);
  }
}

main();
