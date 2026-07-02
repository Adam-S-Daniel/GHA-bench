// Unit tests for the CLI's pure helper functions: argument parsing and
// output formatting. The actual file-reading / process.exit glue in main()
// is exercised end-to-end by the GitHub Actions workflow via act (see
// run-act-tests.ts), per the "test through the pipeline" requirement.
import { describe, expect, test } from "bun:test";
import { parseArgs, formatLabelsLine } from "./cli";

describe("parseArgs", () => {
  test("uses sensible defaults when no flags are given", () => {
    expect(parseArgs([])).toEqual({
      configPath: ".github/labeler-config.json",
      filesPath: "fixtures/changed-files.txt",
    });
  });

  test("honors --config and --files overrides", () => {
    expect(
      parseArgs(["--config", "custom-config.json", "--files", "list.txt"]),
    ).toEqual({ configPath: "custom-config.json", filesPath: "list.txt" });
  });

  test("throws a clear error when a flag is missing its value", () => {
    expect(() => parseArgs(["--config"])).toThrow(/--config/);
  });

  test("throws a clear error on an unrecognized flag", () => {
    expect(() => parseArgs(["--bogus", "x"])).toThrow(/--bogus/);
  });
});

describe("formatLabelsLine", () => {
  test("joins labels with commas", () => {
    expect(formatLabelsLine(["api", "tests"])).toBe("LABELS=api,tests");
  });

  test("produces an empty value when there are no labels", () => {
    expect(formatLabelsLine([])).toBe("LABELS=");
  });
});
