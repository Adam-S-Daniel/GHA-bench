// CLI entry point: reads a changed-files list and a rules config from JSON
// files (mocking what a PR event would provide) and prints the final label set.
import { assignLabels, type LabelRule } from "./labeler";

interface Config {
  files: string[];
  rules: LabelRule[];
  exclusive?: boolean;
}

function loadConfig(path: string): Config {
  let raw: string;
  try {
    raw = require("node:fs").readFileSync(path, "utf-8");
  } catch (err) {
    throw new Error(`Could not read config file at "${path}": ${(err as Error).message}`);
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch (err) {
    throw new Error(`Config file at "${path}" is not valid JSON: ${(err as Error).message}`);
  }

  const config = parsed as Partial<Config>;
  if (!Array.isArray(config.files)) {
    throw new Error(`Config file at "${path}" must have a "files" array`);
  }
  if (!Array.isArray(config.rules)) {
    throw new Error(`Config file at "${path}" must have a "rules" array`);
  }

  return {
    files: config.files as string[],
    rules: config.rules as LabelRule[],
    exclusive: config.exclusive,
  };
}

function main(): void {
  const configPath = process.argv[2];
  if (!configPath) {
    console.error("Usage: bun run app.ts <config.json>");
    process.exit(1);
  }

  const config = loadConfig(configPath);
  const labels = assignLabels(config.files, config.rules, {
    exclusive: config.exclusive,
  });

  console.log(`Changed files: ${config.files.length}`);
  console.log(`Labels: ${JSON.stringify(labels.sort())}`);
}

main();
