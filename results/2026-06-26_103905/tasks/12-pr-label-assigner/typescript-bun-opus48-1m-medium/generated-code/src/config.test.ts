// RED: drive out config parsing/validation with graceful, meaningful errors.
import { describe, expect, test } from "bun:test";
import { parseConfig, parseFileList } from "./config.ts";

describe("parseConfig", () => {
  test("parses a valid rules array", () => {
    const cfg = parseConfig(
      JSON.stringify({
        rules: [{ pattern: "docs/**", label: "documentation", priority: 10 }],
      }),
    );
    expect(cfg.rules).toEqual([
      { pattern: "docs/**", label: "documentation", priority: 10 },
    ]);
  });

  test("throws a meaningful error on invalid JSON", () => {
    expect(() => parseConfig("{not json")).toThrow(/Invalid config JSON/);
  });

  test("throws when 'rules' is missing", () => {
    expect(() => parseConfig(JSON.stringify({}))).toThrow(
      /must contain a "rules" array/,
    );
  });

  test("throws when a rule is missing pattern or label", () => {
    expect(() =>
      parseConfig(JSON.stringify({ rules: [{ pattern: "x" }] })),
    ).toThrow(/rule at index 0 .* "label"/);
  });
});

describe("parseFileList", () => {
  test("splits on newlines and trims, dropping blanks", () => {
    expect(parseFileList("docs/a.md\n\n  src/b.ts  \n")).toEqual([
      "docs/a.md",
      "src/b.ts",
    ]);
  });
});
