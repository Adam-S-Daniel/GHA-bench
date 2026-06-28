import { describe, expect, test } from "bun:test";
import { buildStrategy, formatStrategy } from "../src/cli.ts";

// ---------------------------------------------------------------------------
// TDD cycle 6 — the testable core of the CLI.
//
// `buildStrategy` turns raw JSON *text* (as read from a file or stdin) into a
// generated strategy, surfacing JSON syntax errors and validation errors as
// clear messages. `formatStrategy` renders the strategy back to JSON text.
// Keeping these pure means the executable wrapper (src/generate.ts) only has to
// deal with process plumbing (argv / files / exit codes).
// ---------------------------------------------------------------------------
describe("buildStrategy", () => {
  test("builds a strategy from valid JSON config text", () => {
    const text = JSON.stringify({
      matrix: { os: ["ubuntu-latest", "windows-latest"], node: [18, 20] },
      exclude: [{ os: "windows-latest", node: 18 }],
      maxParallel: 2,
      failFast: true,
      maxSize: 10,
    });

    const strategy = buildStrategy(text);

    expect(strategy.count).toBe(3);
    expect(strategy["max-parallel"]).toBe(2);
    expect(strategy["fail-fast"]).toBe(true);
    expect(strategy.matrix.include).toEqual([
      { os: "ubuntu-latest", node: 18 },
      { os: "ubuntu-latest", node: 20 },
      { os: "windows-latest", node: 20 },
    ]);
  });

  test("throws a clear error for malformed JSON", () => {
    expect(() => buildStrategy("{ not valid json ")).toThrow(
      /Invalid JSON configuration/,
    );
  });

  test("propagates validation errors from parseConfig", () => {
    expect(() => buildStrategy(JSON.stringify({}))).toThrow(
      'Configuration is missing the required "matrix" object',
    );
  });

  test("propagates the max-size error", () => {
    const text = JSON.stringify({
      matrix: { os: ["a", "b", "c"], node: [1, 2, 3] },
      maxSize: 4,
    });
    expect(() => buildStrategy(text)).toThrow(/exceeds the configured maxSize/);
  });
});

describe("formatStrategy", () => {
  const strategy = buildStrategy(
    JSON.stringify({ matrix: { os: ["ubuntu-latest"] } }),
  );

  test("compact output is single-line valid JSON that round-trips", () => {
    const out = formatStrategy(strategy, false);
    expect(out).not.toContain("\n");
    expect(JSON.parse(out)).toEqual({
      matrix: { include: [{ os: "ubuntu-latest" }] },
      count: 1,
    });
  });

  test("pretty output is indented multi-line JSON", () => {
    const out = formatStrategy(strategy, true);
    expect(out).toContain("\n");
    expect(out).toContain("  ");
    expect(JSON.parse(out)).toEqual(JSON.parse(formatStrategy(strategy, false)));
  });
});
