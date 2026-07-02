import { readdir, readFile, writeFile } from "node:fs/promises";
import { extname, join } from "node:path";
import { parseJUnitXml } from "./junit-parser";
import { parseJsonResults } from "./json-parser";
import { aggregate } from "./aggregator";
import { generateMarkdownSummary } from "./markdown-report";
import type { ParsedFile } from "./types";

// Loads every .xml/.json test result file from a directory (simulating the
// artifacts collected from a GitHub Actions matrix build), parses each with
// the appropriate format parser, and returns them as ParsedFile[].
export async function loadResultFiles(dir: string): Promise<ParsedFile[]> {
  const entries = await readdir(dir);
  const files: ParsedFile[] = [];

  for (const entry of entries.sort()) {
    const ext = extname(entry);
    const fullPath = join(dir, entry);
    const contents = await readFile(fullPath, "utf-8");

    if (ext === ".xml") {
      files.push(parseJUnitXml(contents, entry));
    } else if (ext === ".json") {
      files.push(parseJsonResults(contents, entry));
    } else {
      throw new Error(`Unsupported test result file format: "${entry}". Expected .xml or .json`);
    }
  }

  return files;
}

async function main(): Promise<void> {
  const dir = process.argv[2] ?? "fixtures";
  const outputPath = process.env.GITHUB_STEP_SUMMARY ?? "summary.md";

  const files = await loadResultFiles(dir);
  const result = aggregate(files);
  const markdown = generateMarkdownSummary(result);

  await writeFile(outputPath, markdown, { flag: "a" });
  console.log(markdown);

  if (result.totals.failed > 0) {
    process.exitCode = 1;
  }
}

if (import.meta.main) {
  main().catch((err) => {
    console.error(`Test results aggregation failed: ${(err as Error).message}`);
    process.exit(1);
  });
}
