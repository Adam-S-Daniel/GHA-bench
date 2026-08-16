import { readFileSync, writeFileSync } from "fs";

// Read version from package.json file
export function readPackageVersion(filePath: string): string {
  try {
    const content = readFileSync(filePath, "utf-8");
    const pkg = JSON.parse(content);

    if (!pkg.version) {
      throw new Error("package.json does not contain a version field");
    }

    return pkg.version;
  } catch (error) {
    if (error instanceof Error) {
      throw new Error(`Failed to read version from ${filePath}: ${error.message}`);
    }
    throw error;
  }
}

// Write version to package.json file
export function writePackageVersion(filePath: string, version: string): void {
  try {
    const content = readFileSync(filePath, "utf-8");
    const pkg = JSON.parse(content);

    pkg.version = version;

    writeFileSync(filePath, JSON.stringify(pkg, null, 2) + "\n", "utf-8");
  } catch (error) {
    if (error instanceof Error) {
      throw new Error(
        `Failed to write version to ${filePath}: ${error.message}`
      );
    }
    throw error;
  }
}
