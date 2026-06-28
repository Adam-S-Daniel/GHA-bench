// cli.ts
//
// Command-line entry point. Reads a matrix configuration as JSON (from a file
// path argument, or from stdin when given "-" or no argument) and prints the
// generated GitHub Actions matrix.
//
// Output uses unambiguous marker lines so a CI pipeline can parse them out of
// the surrounding log noise. We deliberately avoid the `::name::value` syntax
// because GitHub Actions / act interpret those as workflow commands and would
// swallow them instead of printing them. Markers used:
//
//   MTX_COUNT=<n>                 number of expanded combinations
//   MTX_STRATEGY=<json>          the strategy block (drop into a workflow)
//   MTX_JSON=<json>              the fully-expanded combinations array
//   MTX_ERROR=<message>          printed (to stderr) on any failure
//
// Run with:  bun run cli.ts <config.json>
//        or:  cat config.json | bun run cli.ts -

import { generateMatrix, parseConfig, type MatrixResult } from "./matrix-generator";

/** Render a successful result as marker lines plus a human-readable summary. */
export function renderResult(result: MatrixResult): string {
  const lines = [
    `MTX_COUNT=${result.count}`,
    `MTX_STRATEGY=${JSON.stringify(result.strategy)}`,
    `MTX_JSON=${JSON.stringify(result.combinations)}`,
    // A pretty block too, purely for humans reading the CI log.
    `Generated ${result.count} build combination(s):`,
    JSON.stringify(result.strategy, null, 2),
  ];
  return lines.join("\n");
}

/** Render an error as a marker line. */
export function renderError(error: unknown): string {
  const message = error instanceof Error ? error.message : String(error);
  return `MTX_ERROR=${message}`;
}

/** Read the entire contents of stdin as a string. */
async function readStdin(): Promise<string> {
  return await Bun.stdin.text();
}

/**
 * Run the CLI. Returns the process exit code (0 = success, 1 = failure).
 * Kept as a function so it is testable and so importing this module for its
 * `render*` helpers does not trigger execution.
 */
export async function main(argv: string[]): Promise<number> {
  const arg = argv[2];
  try {
    let source: string;
    if (!arg || arg === "-") {
      source = await readStdin();
    } else {
      const file = Bun.file(arg);
      if (!(await file.exists())) {
        throw new Error(`Configuration file not found: ${arg}`);
      }
      source = await file.text();
    }

    let raw: unknown;
    try {
      raw = JSON.parse(source);
    } catch {
      throw new Error(`Configuration is not valid JSON${arg && arg !== "-" ? ` (${arg})` : ""}.`);
    }

    const config = parseConfig(raw);
    const result = generateMatrix(config);
    console.log(renderResult(result));
    return 0;
  } catch (error) {
    console.error(renderError(error));
    return 1;
  }
}

// Only run when executed directly (not when imported by tests).
if (import.meta.main) {
  process.exit(await main(Bun.argv));
}
