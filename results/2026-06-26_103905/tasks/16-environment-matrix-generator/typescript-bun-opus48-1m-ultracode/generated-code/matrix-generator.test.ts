/**
 * Unit tests for the Environment Matrix Generator.
 *
 * These tests drive the implementation via red/green TDD. They cover the pure
 * matrix-expansion logic (cartesian product, exclude, include — matching
 * GitHub Actions' documented semantics), max-size validation, strategy
 * assembly, and the CLI/error-handling surface.
 *
 * The end-to-end behaviour (the script running inside a real GitHub Actions
 * pipeline via `act`) is verified separately in `workflow.test.ts`.
 */
import { describe, expect, test } from "bun:test";
import {
  applyExclude,
  applyInclude,
  cartesianProduct,
  generateMatrix,
  MatrixConfigError,
  MatrixSizeError,
} from "./matrix-generator.ts";

describe("cartesianProduct", () => {
  test("expands a single dimension into one combination per value", () => {
    const result = cartesianProduct([["os", ["ubuntu-latest", "windows-latest"]]]);
    expect(result).toEqual([
      { os: "ubuntu-latest" },
      { os: "windows-latest" },
    ]);
  });

  test("expands two dimensions with the first varying slowest (GHA order)", () => {
    const result = cartesianProduct([
      ["os", ["ubuntu-latest", "windows-latest"]],
      ["node", ["18", "20"]],
    ]);
    expect(result).toEqual([
      { os: "ubuntu-latest", node: "18" },
      { os: "ubuntu-latest", node: "20" },
      { os: "windows-latest", node: "18" },
      { os: "windows-latest", node: "20" },
    ]);
  });

  test("produces the product of all dimension sizes", () => {
    const result = cartesianProduct([
      ["os", ["ubuntu-latest", "windows-latest", "macos-latest"]],
      ["node", ["18", "20"]],
      ["feature", ["minimal", "full"]],
    ]);
    expect(result).toHaveLength(3 * 2 * 2);
  });

  test("returns an empty list when there are no dimensions (include-only matrix)", () => {
    expect(cartesianProduct([])).toEqual([]);
  });
});

describe("applyExclude", () => {
  const base: ReturnType<typeof cartesianProduct> = [
    { os: "ubuntu-latest", node: "18" },
    { os: "ubuntu-latest", node: "20" },
    { os: "windows-latest", node: "18" },
    { os: "windows-latest", node: "20" },
  ];

  test("removes a fully-specified combination", () => {
    const result = applyExclude(base, [{ os: "windows-latest", node: "18" }]);
    expect(result).toEqual([
      { os: "ubuntu-latest", node: "18" },
      { os: "ubuntu-latest", node: "20" },
      { os: "windows-latest", node: "20" },
    ]);
  });

  test("treats a partial exclude as a match on the specified keys only", () => {
    // Excluding just { os: windows-latest } drops every windows row.
    const result = applyExclude(base, [{ os: "windows-latest" }]);
    expect(result).toEqual([
      { os: "ubuntu-latest", node: "18" },
      { os: "ubuntu-latest", node: "20" },
    ]);
  });

  test("applies multiple exclude rules", () => {
    const result = applyExclude(base, [
      { node: "18" },
      { os: "windows-latest" },
    ]);
    expect(result).toEqual([{ os: "ubuntu-latest", node: "20" }]);
  });

  test("returns the input unchanged when there are no exclude rules", () => {
    expect(applyExclude(base, [])).toEqual(base);
  });

  test("an exclude key absent from a combination never matches it", () => {
    const result = applyExclude(base, [{ arch: "arm64" }]);
    expect(result).toEqual(base);
  });
});

describe("applyInclude", () => {
  test("adds a new key to every combination when no keys conflict", () => {
    const base = [
      { os: "ubuntu-latest", node: "18" },
      { os: "ubuntu-latest", node: "20" },
    ];
    const result = applyInclude(base, [{ npm: "9" }], ["os", "node"]);
    expect(result).toEqual([
      { os: "ubuntu-latest", node: "18", npm: "9" },
      { os: "ubuntu-latest", node: "20", npm: "9" },
    ]);
  });

  test("only merges into combinations whose dimension values match", () => {
    const base = [
      { os: "ubuntu-latest", node: "18" },
      { os: "windows-latest", node: "18" },
    ];
    const result = applyInclude(base, [{ os: "windows-latest", experimental: true }], [
      "os",
      "node",
    ]);
    expect(result).toEqual([
      { os: "ubuntu-latest", node: "18" },
      { os: "windows-latest", node: "18", experimental: true },
    ]);
  });

  test("appends a new combination when an include matches no existing row", () => {
    const base = [{ os: "ubuntu-latest", node: "18" }];
    const result = applyInclude(base, [{ os: "macos-latest", node: "20" }], ["os", "node"]);
    expect(result).toEqual([
      { os: "ubuntu-latest", node: "18" },
      { os: "macos-latest", node: "20" },
    ]);
  });

  test("turns an include-only matrix into one job per include entry", () => {
    const result = applyInclude([], [{ os: "ubuntu-latest" }, { os: "macos-latest" }], []);
    expect(result).toEqual([{ os: "ubuntu-latest" }, { os: "macos-latest" }]);
  });

  test("reproduces GitHub's documented include example exactly", () => {
    // From the GitHub Actions docs: fruit x animal with five include entries.
    const base = cartesianProduct([
      ["fruit", ["apple", "pear"]],
      ["animal", ["cat", "dog"]],
    ]);
    const result = applyInclude(
      base,
      [
        { color: "green" },
        { color: "pink", animal: "cat" },
        { fruit: "apple", shape: "circle" },
        { fruit: "banana" },
        { fruit: "banana", animal: "cat" },
      ],
      ["fruit", "animal"],
    );
    expect(result).toEqual([
      { fruit: "apple", animal: "cat", color: "pink", shape: "circle" },
      { fruit: "apple", animal: "dog", color: "green", shape: "circle" },
      { fruit: "pear", animal: "cat", color: "pink" },
      { fruit: "pear", animal: "dog", color: "green" },
      { fruit: "banana" },
      { fruit: "banana", animal: "cat" },
    ]);
  });

  test("does not mutate the input combinations", () => {
    const base = [{ os: "ubuntu-latest" }];
    const snapshot = structuredClone(base);
    applyInclude(base, [{ npm: "9" }], ["os"]);
    expect(base).toEqual(snapshot);
  });
});

describe("generateMatrix", () => {
  test("expands a plain OS x version x feature matrix into a strategy block", () => {
    const result = generateMatrix({
      matrix: {
        os: ["ubuntu-latest", "windows-latest"],
        node: ["18", "20"],
        feature: ["minimal", "full"],
      },
    });
    expect(result.size).toBe(8);
    expect(result["within-limit"]).toBe(true);
    expect(result.strategy.matrix.include).toHaveLength(8);
    expect(result.strategy.matrix.include[0]).toEqual({
      os: "ubuntu-latest",
      node: "18",
      feature: "minimal",
    });
  });

  test("defaults fail-fast to true and omits max-parallel when unset", () => {
    const result = generateMatrix({ matrix: { os: ["ubuntu-latest"] } });
    expect(result.strategy["fail-fast"]).toBe(true);
    expect(result.strategy["max-parallel"]).toBeUndefined();
    expect(result["max-size"]).toBe(256); // GitHub's hard limit is the default
  });

  test("threads fail-fast and max-parallel through to the strategy", () => {
    const result = generateMatrix({
      "fail-fast": false,
      "max-parallel": 3,
      matrix: { os: ["ubuntu-latest", "windows-latest"] },
    });
    expect(result.strategy["fail-fast"]).toBe(false);
    expect(result.strategy["max-parallel"]).toBe(3);
  });

  test("accepts camelCase aliases for the strategy knobs", () => {
    const result = generateMatrix({
      failFast: false,
      maxParallel: 2,
      maxSize: 10,
      matrix: { os: ["ubuntu-latest"] },
    });
    expect(result.strategy["fail-fast"]).toBe(false);
    expect(result.strategy["max-parallel"]).toBe(2);
    expect(result["max-size"]).toBe(10);
  });

  test("applies exclude then include in GitHub order", () => {
    const result = generateMatrix({
      matrix: {
        os: ["ubuntu-latest", "windows-latest"],
        node: ["18", "20"],
        exclude: [{ os: "windows-latest", node: "18" }],
        include: [{ os: "macos-latest", node: "20", experimental: true }],
      },
    });
    expect(result.strategy.matrix.include).toEqual([
      { os: "ubuntu-latest", node: "18" },
      { os: "ubuntu-latest", node: "20" },
      { os: "windows-latest", node: "20" },
      { os: "macos-latest", node: "20", experimental: true },
    ]);
    expect(result.size).toBe(4);
  });

  test("reports within-limit=false when size exceeds max-size (non-strict)", () => {
    const result = generateMatrix({
      "max-size": 3,
      matrix: { os: ["a", "b"], node: ["1", "2"] },
    });
    expect(result.size).toBe(4);
    expect(result["within-limit"]).toBe(false);
  });

  test("throws MatrixSizeError when size exceeds max-size in strict mode", () => {
    expect(() =>
      generateMatrix({ "max-size": 3, matrix: { os: ["a", "b"], node: ["1", "2"] } }, {
        strict: true,
      }),
    ).toThrow(MatrixSizeError);
  });

  test("supports an include-only matrix", () => {
    const result = generateMatrix({
      matrix: {
        include: [
          { os: "ubuntu-latest", node: "20" },
          { os: "macos-latest", node: "18" },
        ],
      },
    });
    expect(result.size).toBe(2);
    expect(result.strategy.matrix.include).toEqual([
      { os: "ubuntu-latest", node: "20" },
      { os: "macos-latest", node: "18" },
    ]);
  });

  describe("validation errors", () => {
    test("rejects a non-object config", () => {
      expect(() => generateMatrix("nope")).toThrow(MatrixConfigError);
    });

    test("rejects a missing matrix section", () => {
      expect(() => generateMatrix({})).toThrow(MatrixConfigError);
    });

    test("rejects a dimension whose values are not a non-empty array", () => {
      expect(() => generateMatrix({ matrix: { os: [] } })).toThrow(MatrixConfigError);
      expect(() => generateMatrix({ matrix: { os: "ubuntu-latest" } })).toThrow(
        MatrixConfigError,
      );
    });

    test("rejects a non-positive max-parallel", () => {
      expect(() =>
        generateMatrix({ "max-parallel": 0, matrix: { os: ["a"] } }),
      ).toThrow(MatrixConfigError);
    });

    test("rejects a non-positive max-size", () => {
      expect(() => generateMatrix({ "max-size": -1, matrix: { os: ["a"] } })).toThrow(
        MatrixConfigError,
      );
    });

    test("rejects include/exclude that are not arrays of objects", () => {
      expect(() =>
        generateMatrix({ matrix: { os: ["a"], include: "x" } }),
      ).toThrow(MatrixConfigError);
      expect(() =>
        generateMatrix({ matrix: { os: ["a"], exclude: [42] } }),
      ).toThrow(MatrixConfigError);
    });

    test("errors when expansion produces zero combinations", () => {
      expect(() =>
        generateMatrix({ matrix: { os: ["a"], exclude: [{ os: "a" }] } }),
      ).toThrow(MatrixConfigError);
    });

    test("error messages are meaningful (mention the offending field)", () => {
      expect(() => generateMatrix({ matrix: { os: [] } })).toThrow(/os/);
      expect(() => generateMatrix({ "max-size": -1, matrix: { os: ["a"] } })).toThrow(
        /max-size/,
      );
    });
  });
});

describe("CLI (bun run matrix-generator.ts)", () => {
  const scriptPath = new URL("./matrix-generator.ts", import.meta.url).pathname;

  /** Run the CLI as a real subprocess, returning its stdout/stderr/exit code. */
  async function runCli(
    args: string[],
    stdin?: string,
  ): Promise<{ stdout: string; stderr: string; exitCode: number }> {
    const proc = Bun.spawn(["bun", "run", scriptPath, ...args], {
      stdin: stdin === undefined ? "ignore" : new TextEncoder().encode(stdin),
      stdout: "pipe",
      stderr: "pipe",
    });
    const [stdout, stderr, exitCode] = await Promise.all([
      new Response(proc.stdout).text(),
      new Response(proc.stderr).text(),
      proc.exited,
    ]);
    return { stdout, stderr, exitCode };
  }

  /** Write a config to a content-addressed temp file and return its path. */
  async function writeTempConfig(content: string): Promise<string> {
    const { tmpdir } = await import("node:os");
    const path = `${tmpdir()}/matrix-cli-${Bun.hash(content).toString(16)}.json`;
    await Bun.write(path, content);
    return path;
  }

  test("reads a config file and prints valid matrix JSON, exit 0", async () => {
    const path = await writeTempConfig(
      JSON.stringify({ matrix: { os: ["ubuntu-latest", "windows-latest"], node: ["20"] } }),
    );
    const { stdout, exitCode } = await runCli([path]);
    expect(exitCode).toBe(0);
    const parsed = JSON.parse(stdout);
    expect(parsed.size).toBe(2);
    expect(parsed.strategy.matrix.include).toHaveLength(2);
  });

  test("reads config from stdin when the path is '-'", async () => {
    const config = JSON.stringify({ matrix: { os: ["ubuntu-latest"], node: ["18", "20"] } });
    const { stdout, exitCode } = await runCli(["-"], config);
    expect(exitCode).toBe(0);
    expect(JSON.parse(stdout).size).toBe(2);
  });

  test("--compact emits single-line JSON", async () => {
    const path = await writeTempConfig(JSON.stringify({ matrix: { os: ["ubuntu-latest"] } }));
    const { stdout, exitCode } = await runCli([path, "--compact"]);
    expect(exitCode).toBe(0);
    expect(stdout.trim().split("\n")).toHaveLength(1);
  });

  test("--strict exits with code 2 and a clear message when over max-size", async () => {
    const path = await writeTempConfig(
      JSON.stringify({ "max-size": 1, matrix: { os: ["a", "b"] } }),
    );
    const { stderr, exitCode } = await runCli([path, "--strict"]);
    expect(exitCode).toBe(2);
    expect(stderr).toMatch(/exceeds the maximum/);
  });

  test("invalid JSON exits 1 with a meaningful error", async () => {
    const path = await writeTempConfig("{ this is not json ");
    const { stderr, exitCode } = await runCli([path]);
    expect(exitCode).toBe(1);
    expect(stderr).toMatch(/Error/);
    expect(stderr).toMatch(/JSON/i);
  });

  test("a missing config file exits 1 with a meaningful error", async () => {
    const { stderr, exitCode } = await runCli(["/no/such/file/here.json"]);
    expect(exitCode).toBe(1);
    expect(stderr).toMatch(/Error/);
  });

  test("a config validation error exits 1 and names the field", async () => {
    const path = await writeTempConfig(JSON.stringify({ matrix: { os: [] } }));
    const { stderr, exitCode } = await runCli([path]);
    expect(exitCode).toBe(1);
    expect(stderr).toMatch(/os/);
  });
});
