import { existsSync } from "node:fs";

/**
 * Picks which manifest file to parse. An explicit path always wins; otherwise
 * the first candidate that exists on disk is used. This lets the CLI default
 * to "whichever manifest is checked into fixtures/" without the caller having
 * to know if the project is npm- or pip-based.
 */
export function resolveManifestPath(
  explicitPath: string | undefined,
  candidates: readonly string[],
): string {
  if (explicitPath) return explicitPath;

  for (const candidate of candidates) {
    if (existsSync(candidate)) return candidate;
  }

  throw new Error(`No manifest found. Looked for: ${candidates.join(", ")}`);
}
