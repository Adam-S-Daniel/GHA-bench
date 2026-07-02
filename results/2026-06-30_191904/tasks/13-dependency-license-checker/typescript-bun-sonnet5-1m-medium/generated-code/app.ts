#!/usr/bin/env bun
// CLI entrypoint: bun run app.ts --manifest <path> --policy <path> --license-db <path> [--format text|json]
//
// Exits 0 when no dependency license is on the deny-list, 1 when at least
// one is denied. This lets a CI job fail the build on a policy violation.

import { runCli } from "./src/cli";

function parseArgs(argv: string[]): Record<string, string> {
  const args: Record<string, string> = {};
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg.startsWith("--")) {
      const key = arg.slice(2);
      const value = argv[i + 1];
      if (value === undefined || value.startsWith("--")) {
        throw new Error(`Missing value for --${key}`);
      }
      args[key] = value;
      i += 1;
    }
  }
  return args;
}

async function main(): Promise<void> {
  const args = parseArgs(process.argv.slice(2));

  const manifestPath = args["manifest"];
  const policyPath = args["policy"];
  const licenseDbPath = args["license-db"];
  const format = args["format"] === "json" ? "json" : "text";

  if (!manifestPath || !policyPath || !licenseDbPath) {
    throw new Error(
      "Usage: bun run app.ts --manifest <path> --policy <path> --license-db <path> [--format text|json]"
    );
  }

  const { output, exitCode } = await runCli({ manifestPath, policyPath, licenseDbPath, format });
  console.log(output);
  process.exitCode = exitCode;
}

main().catch((err: unknown) => {
  console.error(`dependency-license-checker: ${(err as Error).message}`);
  process.exitCode = 2;
});
