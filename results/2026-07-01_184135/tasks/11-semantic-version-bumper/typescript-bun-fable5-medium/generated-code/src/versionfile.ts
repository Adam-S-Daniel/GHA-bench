// Version-file I/O. Two formats are supported, chosen by filename:
//   *.json (e.g. package.json) -> the "version" field of a JSON object
//   anything else (e.g. VERSION) -> the whole file is the version string

import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { basename } from "node:path";

const isJsonFile = (path: string): boolean => basename(path).endsWith(".json");

/** Read the current version string from a package.json or plain version file. */
export function readVersion(path: string): string {
  if (!existsSync(path)) {
    throw new Error(`Version file not found: ${path}`);
  }
  const content = readFileSync(path, "utf8");

  if (isJsonFile(path)) {
    let parsed: unknown;
    try {
      parsed = JSON.parse(content);
    } catch (err) {
      throw new Error(`Failed to parse ${path} as JSON: ${(err as Error).message}`);
    }
    const version = (parsed as Record<string, unknown>)?.["version"];
    if (typeof version !== "string") {
      throw new Error(`${path} has no "version" field`);
    }
    return version;
  }

  return content.trim();
}

/** Write the new version back, preserving the file's format. */
export function writeVersion(path: string, version: string): void {
  if (isJsonFile(path)) {
    const content = readFileSync(path, "utf8");
    // Replace only the version value textually so the rest of the file's
    // formatting (key order, indentation) is left untouched.
    const updated = content.replace(
      /("version"\s*:\s*)"[^"]*"/,
      `$1"${version}"`,
    );
    if (updated === content && !content.includes(`"${version}"`)) {
      throw new Error(`Could not locate a "version" field to update in ${path}`);
    }
    writeFileSync(path, updated);
  } else {
    writeFileSync(path, version + "\n");
  }
}
