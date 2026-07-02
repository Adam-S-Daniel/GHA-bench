// Reads/writes the semantic version tracked in a project's version file.
// Two formats are supported:
//   - JSON files (e.g. package.json): the version lives in a top-level
//     "version" string field; writing back preserves every other field.
//   - Plain-text files (e.g. VERSION): the entire (trimmed) file content
//     IS the version string.
// The format is auto-detected by attempting a JSON parse.

export interface VersionFileHandle {
  /** The version string currently in the file. */
  version: string;
  /** Rewrites the file in place with `newVersion` substituted for `version`. */
  write(newVersion: string): Promise<void>;
}

export async function readVersionFile(path: string): Promise<VersionFileHandle> {
  const file = Bun.file(path);
  if (!(await file.exists())) {
    throw new Error(
      `Version file not found: "${path}". Provide a JSON file with a "version" field (e.g. package.json) or a plain-text file containing just the version string.`,
    );
  }

  const raw = await file.text();

  let parsedJson: Record<string, unknown> | undefined;
  try {
    const candidate = JSON.parse(raw);
    if (candidate !== null && typeof candidate === "object" && !Array.isArray(candidate)) {
      parsedJson = candidate as Record<string, unknown>;
    }
  } catch {
    parsedJson = undefined;
  }

  if (parsedJson !== undefined) {
    const version = parsedJson.version;
    if (typeof version !== "string") {
      throw new Error(`"${path}" is missing a "version" field (or it isn't a string).`);
    }
    return {
      version,
      async write(newVersion: string): Promise<void> {
        const updated = { ...parsedJson, version: newVersion };
        await Bun.write(path, `${JSON.stringify(updated, null, 2)}\n`);
      },
    };
  }

  return {
    version: raw.trim(),
    async write(newVersion: string): Promise<void> {
      await Bun.write(path, `${newVersion}\n`);
    },
  };
}
