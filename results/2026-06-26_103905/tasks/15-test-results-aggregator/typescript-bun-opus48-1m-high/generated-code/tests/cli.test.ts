import { describe, expect, it } from "bun:test";
import { parseArgs, main } from "../src/index.ts";

const FIXTURES = new URL("../fixtures/", import.meta.url).pathname;

describe("parseArgs", () => {
  it("collects positional paths and the --fail-on-failure flag", () => {
    const opts = parseArgs(["a.xml", "b.json", "--fail-on-failure"]);
    expect(opts.paths).toEqual(["a.xml", "b.json"]);
    expect(opts.failOnFailure).toBe(true);
  });

  it("defaults failOnFailure to false", () => {
    expect(parseArgs(["dir"]).failOnFailure).toBe(false);
  });

  it("clears paths on --help so the caller can show usage", () => {
    expect(parseArgs(["--help"]).paths).toEqual([]);
  });
});

describe("main (process-level behavior)", () => {
  it("returns 1 and prints usage when given no paths", async () => {
    expect(await main([])).toBe(1);
  });

  it("returns 0 when aggregating valid fixtures", async () => {
    expect(await main([FIXTURES])).toBe(0);
  });

  it("returns 1 for a missing input path", async () => {
    expect(await main([FIXTURES + "does-not-exist.xml"])).toBe(1);
  });

  it("returns 1 with --fail-on-failure when there are failures", async () => {
    // The fixtures contain failing tests, so this should gate to 1.
    expect(await main([FIXTURES, "--fail-on-failure"])).toBe(1);
  });
});
