import { describe, expect, test } from "bun:test";
import {
  existsSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { parseArgs } from "../src/generate.ts";

// ---------------------------------------------------------------------------
// TDD cycle 7 — the executable wrapper (src/generate.ts).
//
// `parseArgs` is unit tested directly; the end-to-end behaviour (reading a
// config file, emitting JSON to stdout, writing --out, and exiting non-zero on
// error) is exercised by actually spawning the script with Bun, which is the
// same way the GitHub Actions workflow invokes it.
// ---------------------------------------------------------------------------
const GENERATE = join(import.meta.dir, "..", "src", "generate.ts");
const FIXTURES = join(import.meta.dir, "..", "fixtures");

/** Run the generator as a subprocess and capture stdout/stderr/exit code. */
function runGenerate(
  args: string[],
  opts: { env?: Record<string, string> } = {},
): { stdout: string; stderr: string; exitCode: number } {
  const proc = Bun.spawnSync(["bun", "run", GENERATE, ...args], {
    env: { ...process.env, ...opts.env },
  });
  return {
    stdout: proc.stdout.toString(),
    stderr: proc.stderr.toString(),
    exitCode: proc.exitCode ?? -1,
  };
}

describe("parseArgs", () => {
  test("parses --config, --out and --pretty", () => {
    const opts = parseArgs(["--config", "a.json", "--out", "b.json", "--pretty"]);
    expect(opts).toEqual({
      configPath: "a.json",
      outPath: "b.json",
      pretty: true,
      help: false,
    });
  });

  test("supports short flags", () => {
    const opts = parseArgs(["-c", "a.json", "-p"]);
    expect(opts.configPath).toBe("a.json");
    expect(opts.pretty).toBe(true);
  });

  test("throws on an unknown argument", () => {
    expect(() => parseArgs(["--bogus"])).toThrow("Unknown argument: --bogus");
  });

  test("throws when a flag is missing its value", () => {
    expect(() => parseArgs(["--config"])).toThrow("Missing value for --config");
  });
});

describe("generate.ts (subprocess)", () => {
  test("emits valid strategy JSON and exits 0 for a valid config", () => {
    const { stdout, exitCode } = runGenerate([
      "--config",
      join(FIXTURES, "basic.json"),
    ]);
    expect(exitCode).toBe(0);
    const parsed = JSON.parse(stdout);
    expect(parsed.count).toBe(4);
    expect(parsed["max-parallel"]).toBe(2);
    expect(parsed["fail-fast"]).toBe(true);
  });

  test("reads the config path from $MATRIX_CONFIG_FILE", () => {
    const { stdout, exitCode } = runGenerate([], {
      env: { MATRIX_CONFIG_FILE: join(FIXTURES, "feature-flags.json") },
    });
    expect(exitCode).toBe(0);
    expect(JSON.parse(stdout).count).toBe(2);
  });

  test("--out writes the strategy JSON to a file", () => {
    const dir = mkdtempSync(join(tmpdir(), "matrix-out-"));
    const outFile = join(dir, "matrix.json");
    try {
      const { exitCode } = runGenerate([
        "--config",
        join(FIXTURES, "include-exclude.json"),
        "--out",
        outFile,
      ]);
      expect(exitCode).toBe(0);
      expect(existsSync(outFile)).toBe(true);
      expect(JSON.parse(readFileSync(outFile, "utf8")).count).toBe(4);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  test("exits non-zero with a clear error for a missing file", () => {
    const { stderr, exitCode } = runGenerate([
      "--config",
      "/no/such/config.json",
    ]);
    expect(exitCode).toBe(1);
    expect(stderr).toContain("Error:");
    expect(stderr).toContain("Configuration file not found");
  });

  test("exits non-zero when the matrix exceeds max-size", () => {
    const dir = mkdtempSync(join(tmpdir(), "matrix-big-"));
    const cfg = join(dir, "too-big.json");
    try {
      writeFileSync(
        cfg,
        JSON.stringify({
          matrix: { os: ["a", "b", "c"], node: [1, 2, 3] },
          maxSize: 4,
        }),
      );
      const { stderr, exitCode } = runGenerate(["--config", cfg]);
      expect(exitCode).toBe(1);
      expect(stderr).toContain("exceeds the configured maxSize");
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
});
