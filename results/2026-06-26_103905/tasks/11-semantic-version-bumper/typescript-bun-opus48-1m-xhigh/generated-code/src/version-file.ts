// version-file.ts — read and write the on-disk version source.
//
// Two shapes are supported, distinguished by file extension:
//   - "*.json"  : a package.json-like document; we read/write only its
//                 "version" field and preserve everything else verbatim.
//   - otherwise : a plain text file containing just the version string,
//                 optionally prefixed with "v".

/** Detected on-disk representation of the version. */
export type VersionFileFormat = "json" | "plain";

/** A version source loaded from disk, plus the metadata needed to write it back. */
export interface VersionFile {
  /** Absolute or relative path to the file. */
  path: string;
  /** How the version is stored on disk. */
  format: VersionFileFormat;
  /** The current version string, normalised (no leading "v"). */
  version: string;
  /** For plain files: whether the original used a "v" prefix. */
  hasVPrefix: boolean;
  /** For json files: the fully-parsed document, so non-version keys survive. */
  json?: Record<string, unknown>;
}

/**
 * Read a version file from disk.
 * @throws Error with a clear message when the file is missing, unparseable,
 *         or lacks a version.
 */
export async function readVersionFile(path: string): Promise<VersionFile> {
  const file = Bun.file(path);
  if (!(await file.exists())) {
    throw new Error(`Version file not found: ${path}`);
  }
  const raw = await file.text();

  if (path.endsWith(".json")) {
    let doc: Record<string, unknown>;
    try {
      doc = JSON.parse(raw) as Record<string, unknown>;
    } catch (err) {
      throw new Error(
        `Could not parse JSON version file ${path}: ${(err as Error).message}`,
      );
    }
    const version = doc.version;
    if (typeof version !== "string" || version.trim() === "") {
      throw new Error(`No "version" field found in ${path}`);
    }
    return {
      path,
      format: "json",
      version: version.trim(),
      hasVPrefix: false,
      json: doc,
    };
  }

  // Plain text: a single version token, optionally "v"-prefixed.
  const text = raw.trim();
  if (text === "") {
    throw new Error(`Version file ${path} is empty`);
  }
  const hasVPrefix = /^v/i.test(text);
  return {
    path,
    format: "plain",
    version: text.replace(/^v/i, ""),
    hasVPrefix,
  };
}

/**
 * Persist a new version to the file, preserving its original shape: JSON
 * documents keep all other keys and key order; plain files restore the "v"
 * prefix if the original had one. Both end with a trailing newline.
 */
export async function writeVersionFile(
  file: VersionFile,
  newVersion: string,
): Promise<void> {
  if (file.format === "json") {
    const doc = { ...(file.json ?? {}), version: newVersion };
    await Bun.write(file.path, `${JSON.stringify(doc, null, 2)}\n`);
    return;
  }
  const prefix = file.hasVPrefix ? "v" : "";
  await Bun.write(file.path, `${prefix}${newVersion}\n`);
}
