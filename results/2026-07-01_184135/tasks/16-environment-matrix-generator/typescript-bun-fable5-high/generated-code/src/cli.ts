/**
 * CLI entry point for the environment matrix generator.
 *
 * Usage:
 *   bun run src/cli.ts <config.json> [--pretty]
 *
 * Reads a JSON configuration (os / languageVersions / featureFlags plus
 * include, exclude, maxParallel, failFast, maxSize), generates the GitHub
 * Actions strategy.matrix and prints it as JSON on stdout.
 *
 * Exit codes: 0 = success, 1 = any error (message on stderr).
 * Default output is compact single-line JSON so CI logs are easy to parse;
 * pass --pretty for human-readable output.
 */
import { generateMatrix, MatrixValidationError, validateConfig } from "./matrix";

/** Read and parse the config file, mapping failures to friendly messages. */
async function loadConfig(path: string): Promise<unknown> {
  let text: string;
  try {
    text = await Bun.file(path).text();
  } catch {
    throw new Error(`Cannot read config file "${path}": file is missing or unreadable`);
  }
  try {
    return JSON.parse(text);
  } catch (err) {
    const detail = err instanceof Error ? err.message : String(err);
    throw new Error(`Config file "${path}" is not valid JSON: ${detail}`);
  }
}

export async function main(argv: string[]): Promise<number> {
  const pretty = argv.includes("--pretty");
  const matrixOnly = argv.includes("--matrix-only");
  const positional = argv.filter((arg) => !arg.startsWith("--"));

  if (positional.length !== 1) {
    console.error(
      "Usage: bun run src/cli.ts <config.json> [--pretty] [--matrix-only]\n" +
        "Generates a GitHub Actions strategy.matrix from an environment config.",
    );
    return 1;
  }

  try {
    const raw = await loadConfig(positional[0]!);
    const config = validateConfig(raw);
    const result = generateMatrix(config);
    // --matrix-only emits just { include: [...] } — the exact shape a
    // workflow can splice in via `matrix: ${{ fromJSON(...) }}`.
    const payload: unknown = matrixOnly ? result.strategy.matrix : result;
    console.log(pretty ? JSON.stringify(payload, null, 2) : JSON.stringify(payload));
    return 0;
  } catch (err) {
    // MatrixValidationError and loader errors both carry actionable messages.
    const prefix = err instanceof MatrixValidationError ? "Validation error" : "Error";
    console.error(`${prefix}: ${err instanceof Error ? err.message : String(err)}`);
    return 1;
  }
}

// Only run when executed directly (keeps the module importable from tests).
if (import.meta.main) {
  process.exit(await main(process.argv.slice(2)));
}
