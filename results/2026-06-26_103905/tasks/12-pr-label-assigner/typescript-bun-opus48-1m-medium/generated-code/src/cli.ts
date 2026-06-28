// CLI entrypoint for the PR label assigner.
//
// Usage:
//   bun run src/cli.ts --config <config.json> --files <changed-files.txt>
//
// Reads a JSON rules config and a newline-delimited list of changed file paths
// (the mocked PR diff), computes the final label set, prints a human + machine
// readable report, and — when running inside GitHub Actions — appends the
// markers to $GITHUB_OUTPUT so downstream steps can consume them.
import { parseConfig, parseFileList } from "./config.ts";
import { assignLabels } from "./label-assigner.ts";
import { renderResult } from "./render.ts";

interface CliArgs {
  configPath: string;
  filesPath: string;
}

function parseArgs(argv: string[]): CliArgs {
  let configPath = "label-config.json";
  let filesPath = "changed-files.txt";
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--config") {
      const value = argv[++i];
      if (value === undefined) throw new Error("--config requires a path");
      configPath = value;
    } else if (arg === "--files") {
      const value = argv[++i];
      if (value === undefined) throw new Error("--files requires a path");
      filesPath = value;
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }
  return { configPath, filesPath };
}

async function readFileOrThrow(path: string, kind: string): Promise<string> {
  const file = Bun.file(path);
  if (!(await file.exists())) {
    throw new Error(`${kind} file not found: ${path}`);
  }
  return await file.text();
}

export async function main(argv: string[]): Promise<number> {
  let args: CliArgs;
  try {
    args = parseArgs(argv);
  } catch (err) {
    console.error(`Error: ${(err as Error).message}`);
    console.error(
      "Usage: bun run src/cli.ts --config <config.json> --files <files.txt>",
    );
    return 2;
  }

  try {
    const config = parseConfig(
      await readFileOrThrow(args.configPath, "Config"),
    );
    const files = parseFileList(
      await readFileOrThrow(args.filesPath, "Changed-files"),
    );

    const result = assignLabels(files, config.rules);
    const output = renderResult(result, files.length);
    console.log(output);

    // Surface markers to GitHub Actions outputs when available.
    const githubOutput = process.env.GITHUB_OUTPUT;
    if (githubOutput) {
      await Bun.write(
        githubOutput,
        (await Bun.file(githubOutput).text().catch(() => "")) +
          `labels=${result.labels.join(",")}\n` +
          `label_count=${result.labels.length}\n`,
      );
    }
    return 0;
  } catch (err) {
    console.error(`Error: ${(err as Error).message}`);
    return 1;
  }
}

// Run only when executed directly (not when imported by tests).
if (import.meta.main) {
  const code = await main(Bun.argv.slice(2));
  process.exit(code);
}
