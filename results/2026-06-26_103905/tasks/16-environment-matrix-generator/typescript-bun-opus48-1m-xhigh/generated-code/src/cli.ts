// ---------------------------------------------------------------------------
// CLI core — pure, side-effect-free helpers that bridge raw text <-> strategy.
// The executable entry point (src/generate.ts) handles all process plumbing
// (argv parsing, file/stdin reads, stdout/stderr writes, exit codes) and leans
// on these functions for the actual work, so the interesting logic stays unit
// testable.
// ---------------------------------------------------------------------------
import { generateMatrix, parseConfig } from "./matrix.ts";
import type { GeneratedStrategy } from "./types.ts";

/**
 * Parse JSON configuration *text* and produce a generated strategy.
 *
 * JSON syntax errors are caught and re-thrown with a friendlier prefix so a
 * malformed config file produces an actionable message rather than a raw
 * `SyntaxError`. Validation and generation errors (from parseConfig /
 * generateMatrix) propagate unchanged — they are already descriptive.
 */
export function buildStrategy(text: string): GeneratedStrategy {
  let raw: unknown;
  try {
    raw = JSON.parse(text);
  } catch (err) {
    const detail = err instanceof Error ? err.message : String(err);
    throw new Error(`Invalid JSON configuration: ${detail}`);
  }
  const config = parseConfig(raw);
  return generateMatrix(config);
}

/**
 * Render a strategy back to JSON text. `pretty` selects 2-space-indented,
 * human-readable output; otherwise a compact single line suitable for piping
 * into `jq` or assigning to a GitHub Actions step output.
 */
export function formatStrategy(
  strategy: GeneratedStrategy,
  pretty: boolean,
): string {
  return pretty
    ? JSON.stringify(strategy, null, 2)
    : JSON.stringify(strategy);
}
