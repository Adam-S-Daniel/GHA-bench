/**
 * PR Label Assigner — CLI entry point.
 *
 * Usage:
 *   bun run src/cli.ts --files <changed-files.json> --rules <rules.json>
 *
 * Output (stdout):
 *   LABELS: a,b,c        — comma-joined sorted label set (`<none>` when empty)
 *   LABEL_COUNT: N
 *   JSON: [...]          — the same set as a JSON array
 *
 * Exits 1 with `error: ...` on stderr for any invalid input.
 */
import { readFileSync } from "node:fs";
import {
  assignLabels,
  ConfigError,
  parseChangedFiles,
  parseRules,
} from "./label-assigner.ts";

/** Extract the value following a `--flag`; undefined when absent. */
function argValue(argv: string[], flag: string): string | undefined {
  const idx = argv.indexOf(flag);
  return idx >= 0 ? argv[idx + 1] : undefined;
}

/** Read and JSON-parse a file, converting failures into ConfigError. */
function readJson(path: string): unknown {
  let text: string;
  try {
    text = readFileSync(path, "utf8");
  } catch {
    throw new ConfigError(`cannot read ${path}`);
  }
  try {
    return JSON.parse(text);
  } catch {
    throw new ConfigError(`invalid JSON in ${path}`);
  }
}

function main(argv: string[]): number {
  const filesPath = argValue(argv, "--files");
  const rulesPath = argValue(argv, "--rules");
  if (!filesPath || !rulesPath) {
    throw new ConfigError(
      "usage: bun run src/cli.ts --files <changed-files.json> --rules <rules.json>",
    );
  }
  const files = parseChangedFiles(readJson(filesPath));
  const rules = parseRules(readJson(rulesPath));
  const labels = assignLabels(files, rules);

  console.log(`LABELS: ${labels.length > 0 ? labels.join(",") : "<none>"}`);
  console.log(`LABEL_COUNT: ${labels.length}`);
  console.log(`JSON: ${JSON.stringify(labels)}`);
  return 0;
}

try {
  process.exit(main(process.argv.slice(2)));
} catch (err) {
  const message = err instanceof Error ? err.message : String(err);
  console.error(`error: ${message}`);
  process.exit(1);
}
