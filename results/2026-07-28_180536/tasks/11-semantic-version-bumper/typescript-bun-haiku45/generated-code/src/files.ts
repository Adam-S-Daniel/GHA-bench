// File I/O operations for version and package files

import { readFileSync, writeFileSync } from "fs";

export enum FileType {
  PACKAGE_JSON = "package.json",
  VERSION = "version",
}

// Read version from file (package.json or plain version file)
export function readVersionFromFile(
  filePath: string,
  fileType: FileType
): string {
  const content = readFileSync(filePath, "utf-8");

  if (fileType === FileType.PACKAGE_JSON) {
    try {
      const pkg = JSON.parse(content);
      if (!pkg.version) {
        throw new Error("version field not found in package.json");
      }
      return pkg.version;
    } catch (error) {
      throw new Error(
        `Failed to parse package.json: ${error instanceof Error ? error.message : String(error)}`
      );
    }
  }

  // For VERSION file type, just trim and remove 'v' prefix if present
  return content.replace(/^v/, "").trim();
}

// Write version to file (package.json or plain version file)
export function writeVersionToFile(
  filePath: string,
  newVersion: string,
  fileType: FileType
): void {
  if (fileType === FileType.PACKAGE_JSON) {
    const content = readFileSync(filePath, "utf-8");
    const pkg = JSON.parse(content);
    pkg.version = newVersion;
    writeFileSync(filePath, JSON.stringify(pkg, null, 2) + "\n");
  } else {
    // For VERSION file type, write plain text
    writeFileSync(filePath, newVersion + "\n");
  }
}
