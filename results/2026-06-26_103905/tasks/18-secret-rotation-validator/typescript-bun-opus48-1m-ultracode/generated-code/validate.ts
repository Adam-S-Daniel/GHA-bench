#!/usr/bin/env bun
/**
 * Entrypoint for the secret rotation validator CLI.
 *
 * Run with:  bun run validate.ts --config <path> [--warning-days N]
 *                                 [--format markdown|json|github]
 *                                 [--now YYYY-MM-DD] [--fail-on none|warning|expired]
 *
 * This thin wrapper wires the real Bun-backed I/O into the testable `main()`
 * orchestrator in src/cli.ts, then exits with the returned status code.
 */
import { main, type CliIO } from "./src/cli";

const io: CliIO = {
  // Read a UTF-8 file, turning "missing file" into a friendly message.
  readFile: async (path: string): Promise<string> => {
    const file = Bun.file(path);
    if (!(await file.exists())) {
      throw new Error(`Config file "${path}" not found.`);
    }
    return file.text();
  },
  stdout: (text: string): void => {
    process.stdout.write(text);
  },
  stderr: (text: string): void => {
    process.stderr.write(text);
  },
  now: (): Date => new Date(),
};

const code = await main(Bun.argv.slice(2), io);
process.exit(code);
