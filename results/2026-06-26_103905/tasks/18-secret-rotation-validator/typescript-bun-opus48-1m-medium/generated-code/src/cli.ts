#!/usr/bin/env bun
// CLI entry point. The orchestration is factored into `runCli`, which is pure
// with respect to I/O (it takes an injectable clock + file reader and returns a
// result object). The thin `main()` wrapper at the bottom wires it to the real
// process, so all behaviour is unit-testable without spawning subprocesses.
import { readFileSync } from "node:fs";
import { parseConfig } from "./config.ts";
import { renderJson, renderMarkdown } from "./format.ts";
import { buildReport } from "./report.ts";

/** Exit codes with stable meanings (documented for CI consumers). */
export const EXIT = {
  /** No expired secrets. */
  OK: 0,
  /** At least one expired secret (a validation failure CI should surface). */
  EXPIRED: 1,
  /** Usage / configuration / I/O error. */
  ERROR: 2,
} as const;

/** Dependencies injected into runCli so tests can stub the clock and filesystem. */
export interface CliDeps {
  now: Date;
  readFile: (path: string) => string;
}

/** The outcome of a CLI invocation, returned instead of mutating process state. */
export interface CliResult {
  stdout: string;
  stderr: string;
  exitCode: number;
}

type OutputFormat = "markdown" | "json";

interface ParsedArgs {
  configPath?: string;
  format: OutputFormat;
  warningWindowDays: number;
  /** Optional override for the reference "now" date (for deterministic CI runs). */
  now?: Date;
  help: boolean;
}

const HELP_TEXT = `Secret Rotation Validator

Usage:
  bun run src/cli.ts --config <path> [options]

Options:
  --config <path>            Path to the secrets JSON config (required).
  --format <markdown|json>   Output format (default: markdown).
  --warning-window <days>    Days ahead to warn before a secret is due (default: 14).
  --now <YYYY-MM-DD>         Override the reference date (for deterministic runs).
  --help                     Show this help.

Exit codes:
  0  All secrets OK (none expired).
  1  One or more secrets are expired.
  2  Usage, configuration, or I/O error.
`;

/** Parse argv into a structured options object, throwing on usage errors. */
function parseArgs(argv: string[]): ParsedArgs {
  const args: ParsedArgs = { format: "markdown", warningWindowDays: 14, help: false };

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    switch (arg) {
      case "--help":
      case "-h":
        args.help = true;
        break;
      case "--config": {
        const value = argv[++i];
        if (value === undefined) throw new Error("--config requires a path argument");
        args.configPath = value;
        break;
      }
      case "--format": {
        const value = argv[++i];
        if (value === undefined) throw new Error("--format requires a value");
        if (value !== "markdown" && value !== "json") {
          throw new Error(`Unknown format "${value}": expected "markdown" or "json"`);
        }
        args.format = value;
        break;
      }
      case "--warning-window": {
        const value = argv[++i];
        if (value === undefined) throw new Error("--warning-window requires a number");
        const days = Number(value);
        if (!Number.isFinite(days) || days < 0) {
          throw new Error(`--warning-window must be a non-negative number, got "${value}"`);
        }
        args.warningWindowDays = days;
        break;
      }
      case "--now": {
        const value = argv[++i];
        if (value === undefined) throw new Error("--now requires an ISO date (YYYY-MM-DD)");
        if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) {
          throw new Error(`--now must be an ISO date (YYYY-MM-DD), got "${value}"`);
        }
        const parsed = new Date(`${value}T00:00:00Z`);
        if (Number.isNaN(parsed.getTime())) {
          throw new Error(`--now is not a real calendar date: "${value}"`);
        }
        args.now = parsed;
        break;
      }
      default:
        throw new Error(`Unknown argument: ${arg}`);
    }
  }

  return args;
}

/** Run the validator end to end and return a result object (no process side effects). */
export function runCli(argv: string[], deps: CliDeps): CliResult {
  let args: ParsedArgs;
  try {
    args = parseArgs(argv);
  } catch (error) {
    return { stdout: "", stderr: errorMessage(error), exitCode: EXIT.ERROR };
  }

  if (args.help) {
    return { stdout: HELP_TEXT, stderr: "", exitCode: EXIT.OK };
  }

  if (!args.configPath) {
    return { stdout: "", stderr: "Missing required --config <path>\n\n" + HELP_TEXT, exitCode: EXIT.ERROR };
  }

  // Read the config file (the one place that can raise an I/O error).
  let raw: string;
  try {
    raw = deps.readFile(args.configPath);
  } catch (error) {
    return {
      stdout: "",
      stderr: `Could not read config file "${args.configPath}": ${errorMessage(error)}`,
      exitCode: EXIT.ERROR,
    };
  }

  // Parse + build + render. Any validation error becomes a clean exit-2.
  try {
    const config = parseConfig(raw);
    const now = args.now ?? deps.now;
    const report = buildReport(config, { now, warningWindowDays: args.warningWindowDays });
    const output = args.format === "json" ? renderJson(report) : renderMarkdown(report);
    return {
      stdout: output,
      stderr: "",
      exitCode: report.hasExpired ? EXIT.EXPIRED : EXIT.OK,
    };
  } catch (error) {
    return { stdout: "", stderr: errorMessage(error), exitCode: EXIT.ERROR };
  }
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

/** Real entry point: wire runCli to the actual process. */
function main(): void {
  const result = runCli(process.argv.slice(2), {
    now: new Date(),
    readFile: (path) => readFileSync(path, "utf8"),
  });
  if (result.stdout) process.stdout.write(result.stdout.endsWith("\n") ? result.stdout : result.stdout + "\n");
  if (result.stderr) process.stderr.write(result.stderr.endsWith("\n") ? result.stderr : result.stderr + "\n");
  process.exit(result.exitCode);
}

// Only run main() when executed directly (not when imported by tests).
if (import.meta.main) {
  main();
}
