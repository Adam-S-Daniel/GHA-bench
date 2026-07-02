#!/usr/bin/env bun
// CLI entrypoint: reads a version file + a commit log, determines the next
// semantic version from Conventional Commits, updates the version file,
// prepends a changelog entry, and prints/reports the result.
//
// This file is intentionally a thin wrapper around src/bump.ts's runBump():
// all the interesting logic is unit-tested directly in tests/bump.test.ts.
// End-to-end CLI behavior (this file, run exactly as CI runs it) is
// exercised by the GitHub Actions workflow via `act` instead of being
// re-tested here.
//
// Usage:
//   bun run bump-version.ts [--version-file <path>] [--commits <path>] [--changelog <path>] [--date <YYYY-MM-DD>]
//
// Defaults: --version-file package.json, --commits commits.log, --changelog CHANGELOG.md
//
// When run inside GitHub Actions ($GITHUB_OUTPUT set), also writes
// `new_version`, `previous_version`, and `bump_type` outputs.
import { runBump } from "./src/bump.ts";

interface CliArgs {
  versionFilePath: string;
  commitsLogPath: string;
  changelogPath: string;
  date: string;
}

function todayIso(): string {
  return new Date().toISOString().slice(0, 10);
}

function parseArgs(argv: string[]): CliArgs {
  const args: CliArgs = {
    versionFilePath: "package.json",
    commitsLogPath: "commits.log",
    changelogPath: "CHANGELOG.md",
    date: todayIso(),
  };

  for (let i = 0; i < argv.length; i += 1) {
    const flag = argv[i];
    const value = argv[i + 1];
    if (value === undefined) {
      throw new Error(`Missing value for flag "${flag}".`);
    }
    switch (flag) {
      case "--version-file":
        args.versionFilePath = value;
        break;
      case "--commits":
        args.commitsLogPath = value;
        break;
      case "--changelog":
        args.changelogPath = value;
        break;
      case "--date":
        args.date = value;
        break;
      default:
        throw new Error(`Unknown flag "${flag}".`);
    }
    i += 1;
  }

  return args;
}

async function appendGithubOutput(entries: Record<string, string>): Promise<void> {
  const outputPath = process.env.GITHUB_OUTPUT;
  if (!outputPath) return;
  const existing = (await Bun.file(outputPath).exists())
    ? await Bun.file(outputPath).text()
    : "";
  const lines = Object.entries(entries)
    .map(([key, value]) => `${key}=${value}`)
    .join("\n");
  await Bun.write(outputPath, `${existing}${lines}\n`);
}

async function main(): Promise<void> {
  const args = parseArgs(process.argv.slice(2));

  const result = await runBump(args);

  console.log(`Previous version: ${result.previousVersion}`);
  console.log(`Bump type: ${result.bumpType}`);
  console.log(`New version: ${result.newVersion}`);
  if (result.changelogEntry) {
    console.log("Changelog entry:");
    console.log(result.changelogEntry);
  } else {
    console.log("No conventional commits found; version unchanged.");
  }

  await appendGithubOutput({
    previous_version: result.previousVersion,
    new_version: result.newVersion,
    bump_type: result.bumpType,
  });
}

main().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : String(error);
  console.error(`Error: ${message}`);
  process.exit(1);
});
