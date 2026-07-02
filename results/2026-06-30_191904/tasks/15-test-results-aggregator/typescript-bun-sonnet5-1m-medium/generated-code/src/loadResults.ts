// Discovers and parses all supported test result files (*.xml, *.json) in a
// directory, auto-detecting format from the file extension.

import { readdir, stat } from "node:fs/promises";
import { join } from "node:path";
import { parseJUnitXml } from "./parsers/junit";
import { parseJsonResults } from "./parsers/json";
import type { ParsedFile } from "./types";

export async function loadResultsFromDirectory(dir: string): Promise<ParsedFile[]> {
  let entries: string[];
  try {
    const dirStat = await stat(dir);
    if (!dirStat.isDirectory()) {
      throw new Error(`"${dir}" is not a directory`);
    }
    entries = await readdir(dir);
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === "ENOENT") {
      throw new Error(`Results directory "${dir}" does not exist`);
    }
    throw err;
  }

  const resultFiles = entries.filter((name) => name.endsWith(".xml") || name.endsWith(".json")).sort();

  if (resultFiles.length === 0) {
    throw new Error(`No .xml or .json test result files found in "${dir}"`);
  }

  const parsed: ParsedFile[] = [];
  for (const name of resultFiles) {
    const filePath = join(dir, name);
    const raw = await Bun.file(filePath).text();
    parsed.push(name.endsWith(".xml") ? parseJUnitXml(raw, name) : parseJsonResults(raw, name));
  }

  return parsed;
}
