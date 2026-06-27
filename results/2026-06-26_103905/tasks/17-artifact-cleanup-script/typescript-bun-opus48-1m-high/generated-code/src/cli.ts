#!/usr/bin/env bun
/**
 * Command-line entry point for the artifact cleanup tool.
 *
 * Responsibilities (and ONLY these — all logic lives in the pure modules):
 *   1. Resolve the fixture path and dry-run flag from argv / env.
 *   2. Read + JSON-parse the fixture, surfacing friendly errors.
 *   3. Validate via parseCleanupInput, plan via planCleanup, render via renderPlan.
 *   4. Return an exit code + captured stdout/stderr so it is unit-testable.
 *
 * Usage:
 *   bun run src/cli.ts --fixture data.json [--dry-run]
 *   FIXTURE_FILE=data.json DRY_RUN=true bun run src/cli.ts
 *
 * Exit codes: 0 success, 1 runtime/validation error, 2 usage error.
 */
import { readFileSync } from "node:fs";
import { planCleanup } from "./cleanup.ts";
import { parseCleanupInput } from "./parse.ts";
import { renderPlan } from "./render.ts";

/** Result of a CLI run, returned instead of touching process directly. */
export interface CliResult {
  exitCode: number;
  stdout: string;
  stderr: string;
}

/** Minimal argv parser: supports "--flag value" and boolean "--flag". */
function parseArgs(argv: string[]): { fixture?: string; dryRun: boolean } {
  let fixture: string | undefined;
  let dryRun = false;
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--fixture") {
      fixture = argv[++i];
    } else if (arg === "--dry-run") {
      dryRun = true;
    }
  }
  return { fixture, dryRun };
}

/**
 * Run the cleanup tool with the given argv and environment.
 * Pure with respect to process state: it returns a CliResult rather than
 * printing or exiting, which is what makes it directly testable.
 */
export function runCleanup(argv: string[], env: Record<string, string | undefined> = {}): CliResult {
  const args = parseArgs(argv);

  // Resolve inputs: CLI flags take precedence over environment variables.
  const fixturePath = args.fixture ?? env.FIXTURE_FILE;
  const dryRun = args.dryRun || env.DRY_RUN === "true" || env.DRY_RUN === "1";

  if (!fixturePath) {
    return {
      exitCode: 2,
      stdout: "",
      stderr:
        "Error: no fixture provided. Pass --fixture <path> or set FIXTURE_FILE.\n",
    };
  }

  // Read the file.
  let contents: string;
  try {
    contents = readFileSync(fixturePath, "utf8");
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return { exitCode: 1, stdout: "", stderr: `Error: could not read fixture '${fixturePath}': ${message}\n` };
  }

  // Parse JSON.
  let raw: unknown;
  try {
    raw = JSON.parse(contents);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return { exitCode: 1, stdout: "", stderr: `Error: invalid JSON in '${fixturePath}': ${message}\n` };
  }

  // Validate, plan, render. Validation errors carry actionable messages.
  try {
    const input = parseCleanupInput(raw);
    const plan = planCleanup(input.artifacts, input.policy, { now: input.now });
    const output = renderPlan(plan, { dryRun });
    return { exitCode: 0, stdout: output + "\n", stderr: "" };
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return { exitCode: 1, stdout: "", stderr: `Error: ${message}\n` };
  }
}

// When executed directly (not imported by a test), wire to real process I/O.
if (import.meta.main) {
  const result = runCleanup(process.argv.slice(2), process.env);
  if (result.stdout) process.stdout.write(result.stdout);
  if (result.stderr) process.stderr.write(result.stderr);
  process.exit(result.exitCode);
}
