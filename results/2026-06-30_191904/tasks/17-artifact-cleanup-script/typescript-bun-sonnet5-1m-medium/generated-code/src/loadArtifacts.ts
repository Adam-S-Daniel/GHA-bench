// Loads mock artifact metadata from a JSON file (stands in for the GitHub
// Actions "list artifacts" API in this exercise).
import type { Artifact } from "./types";

export async function loadArtifacts(filePath: string): Promise<Artifact[]> {
  const file = Bun.file(filePath);
  if (!(await file.exists())) {
    throw new Error(`Artifacts file not found: ${filePath}`);
  }

  const raw = await file.text();
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch (cause) {
    throw new Error(
      `Failed to parse artifacts file as JSON: ${filePath} (${(cause as Error).message})`,
    );
  }

  if (!Array.isArray(parsed)) {
    throw new Error(
      `Failed to parse artifacts file: expected a JSON array in ${filePath}`,
    );
  }

  return parsed as Artifact[];
}
