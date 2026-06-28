#!/usr/bin/env bun
// Executable entry point for the Secret Rotation Validator.
//
// Thin shell around src/cli.ts: it owns the side effects (reading the config
// file, writing output, setting the process exit code) while all decision
// logic lives in the pure, unit-tested modules.

import { HELP_TEXT, parseArgs, runReport } from "./src/cli.ts";

async function main(): Promise<number> {
  const opts = parseArgs(Bun.argv.slice(2));

  if (opts.help) {
    console.log(HELP_TEXT);
    return 0;
  }

  // Load the config file, failing loudly if it is missing or not valid JSON.
  const file = Bun.file(opts.config);
  if (!(await file.exists())) {
    throw new Error(`Config file not found: ${opts.config}`);
  }

  let rawConfig: unknown;
  try {
    rawConfig = await file.json();
  } catch (err) {
    const reason = err instanceof Error ? err.message : String(err);
    throw new Error(`Config file '${opts.config}' is not valid JSON: ${reason}`);
  }

  const { output, exitCode } = runReport(rawConfig, opts);

  // Emit to stdout (always) and optionally to a file for artifact upload.
  console.log(output);
  if (opts.output) {
    await Bun.write(opts.output, output.endsWith("\n") ? output : output + "\n");
  }

  return exitCode;
}

// Top-level error handling: surface a clear message and use a distinct exit
// code (2) for operational errors vs. (1) for policy violations.
main()
  .then((code) => {
    process.exit(code);
  })
  .catch((err: unknown) => {
    const message = err instanceof Error ? err.message : String(err);
    console.error(`Error: ${message}`);
    process.exit(2);
  });
