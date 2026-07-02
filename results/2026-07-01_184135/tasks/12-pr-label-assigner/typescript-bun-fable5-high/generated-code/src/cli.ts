// CLI entry point — what the GitHub Actions workflow runs.
//
//   bun run src/cli.ts --config fixtures/rules.json --files fixtures/changed-files.json
//
// Reads a rules config and a (mocked) changed-file list, prints a per-file
// breakdown for debuggability, and ends with one machine-parseable line the
// CI harness asserts on exactly:
//   FINAL LABELS: api,backend,tests     (or "FINAL LABELS: (none)")
import {
  assignLabels,
  InputError,
  parseChangedFiles,
  parseRules,
  type LabelRule,
} from "./labeler";

const USAGE =
  "Usage: bun run src/cli.ts --config <rules.json> --files <changed-files.json>";

/** Parse --config/--files flags; throws InputError on anything malformed. */
function parseArgs(argv: string[]): { config: string; files: string } {
  const flags = new Map<string, string>();
  for (let i = 0; i < argv.length; i += 2) {
    const flag = argv[i];
    const value = argv[i + 1];
    if (flag !== "--config" && flag !== "--files") {
      throw new InputError(`Unknown argument "${flag}".\n${USAGE}`);
    }
    if (value === undefined) {
      throw new InputError(`Flag ${flag} needs a value.\n${USAGE}`);
    }
    flags.set(flag, value);
  }
  const config = flags.get("--config");
  const files = flags.get("--files");
  if (config === undefined || files === undefined) {
    throw new InputError(`Both --config and --files are required.\n${USAGE}`);
  }
  return { config, files };
}

/** Read a file, converting ENOENT and friends into a friendly InputError. */
async function readInput(path: string, what: string): Promise<string> {
  try {
    return await Bun.file(path).text();
  } catch (cause) {
    const detail = cause instanceof Error ? cause.message : String(cause);
    throw new InputError(`Cannot read ${what} at "${path}": ${detail}`);
  }
}

async function main(): Promise<void> {
  const { config, files } = parseArgs(Bun.argv.slice(2));

  const rules: LabelRule[] = parseRules(await readInput(config, "rules config"));
  const changed: string[] = parseChangedFiles(
    await readInput(files, "changed-files list"),
  );

  console.log(`Evaluating ${changed.length} changed file(s) against ${rules.length} rule(s):`);
  for (const file of changed) {
    const labels = assignLabels([file], rules);
    console.log(`  ${file} -> ${labels.length > 0 ? labels.join(",") : "(no labels)"}`);
  }

  const finalLabels = assignLabels(changed, rules);
  console.log(
    `FINAL LABELS: ${finalLabels.length > 0 ? finalLabels.join(",") : "(none)"}`,
  );
}

main().catch((error: unknown) => {
  if (error instanceof InputError) {
    console.error(`pr-label-assigner: ${error.message}`);
  } else {
    console.error("pr-label-assigner: unexpected failure:", error);
  }
  process.exit(1);
});
