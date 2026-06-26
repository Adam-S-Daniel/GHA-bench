// CLI entry point invoked by `bun run src/cli.ts` (and by the CI workflow).
//
// Usage:
//   bun run src/cli.ts \
//     --version-file package.json \
//     --commits-file commits.txt \
//     --changelog CHANGELOG.md \
//     [--date YYYY-MM-DD]
//
// Emits stable KEY=VALUE lines on stdout so CI can parse exact values:
//   PREVIOUS_VERSION=<x>  NEW_VERSION=<y>  BUMP=<major|minor|patch|none>
import { runBump } from "./bumper";

interface CliArgs {
  versionFile: string;
  commitsFile: string;
  changelogFile: string;
  date: string;
}

/** Minimal, dependency-free flag parser for our known options. */
function parseArgs(argv: string[]): CliArgs {
  const opts: Record<string, string> = {};
  for (let i = 0; i < argv.length; i += 2) {
    const flag = argv[i];
    const value = argv[i + 1];
    if (!flag?.startsWith("--") || value === undefined) {
      throw new Error(`Malformed argument near "${flag}"`);
    }
    opts[flag.slice(2)] = value;
  }

  const required = ["version-file", "commits-file", "changelog"] as const;
  for (const key of required) {
    if (!opts[key]) {
      throw new Error(`Missing required --${key} argument`);
    }
  }

  // Default the changelog date to today unless explicitly provided.
  const date = opts["date"] ?? new Date().toISOString().slice(0, 10);

  return {
    versionFile: opts["version-file"]!,
    commitsFile: opts["commits-file"]!,
    changelogFile: opts["changelog"]!,
    date,
  };
}

function main(): void {
  let args: CliArgs;
  try {
    args = parseArgs(Bun.argv.slice(2));
  } catch (err) {
    console.error(`Argument error: ${(err as Error).message}`);
    process.exit(2);
  }

  try {
    const result = runBump({
      versionFile: args.versionFile,
      commitsFile: args.commitsFile,
      changelogFile: args.changelogFile,
      date: args.date,
    });

    // Machine-parseable output first...
    console.log(`PREVIOUS_VERSION=${result.previousVersion}`);
    console.log(`NEW_VERSION=${result.newVersion}`);
    console.log(`BUMP=${result.bump ?? "none"}`);

    // ...then a human-friendly summary.
    if (result.bump === null) {
      console.log("No conventional commits warranted a release; version unchanged.");
    } else {
      console.log(
        `Bumped ${result.previousVersion} -> ${result.newVersion} (${result.bump}).`,
      );
    }
  } catch (err) {
    console.error(`Error: ${(err as Error).message}`);
    process.exit(1);
  }
}

main();
