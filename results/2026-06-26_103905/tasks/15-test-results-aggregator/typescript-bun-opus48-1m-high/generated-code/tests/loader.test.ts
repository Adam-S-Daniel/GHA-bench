import { describe, expect, it } from "bun:test";
import { collectResultFiles, aggregatePaths } from "../src/loader.ts";

const FIXTURES = new URL("../fixtures/", import.meta.url).pathname;

describe("collectResultFiles", () => {
  it("expands a directory to its .xml and .json result files", async () => {
    const files = await collectResultFiles([FIXTURES]);
    const names = files.map((f) => f.split("/").pop()).sort();
    expect(names).toEqual([
      "macos-junit.xml",
      "ubuntu-junit.xml",
      "windows-results.json",
    ]);
  });

  it("accepts explicit file paths too", async () => {
    const one = FIXTURES + "windows-results.json";
    const files = await collectResultFiles([one]);
    expect(files).toEqual([one]);
  });

  it("throws a meaningful error for a missing path", async () => {
    await expect(collectResultFiles([FIXTURES + "nope.xml"])).rejects.toThrow(
      /No such file or directory|not found/i,
    );
  });
});

describe("aggregatePaths (end-to-end over the fixtures)", () => {
  it("produces the known-good totals for the 3-leg matrix fixtures", async () => {
    const result = await aggregatePaths([FIXTURES]);
    expect(result.runCount).toBe(3);
    expect(result.totals.passed).toBe(7);
    expect(result.totals.failed).toBe(4);
    expect(result.totals.skipped).toBe(1);
    expect(result.totals.total).toBe(12);
    expect(result.totals.duration).toBeCloseTo(1.8, 5);
  });

  it("identifies auth > login as the one flaky test", async () => {
    const result = await aggregatePaths([FIXTURES]);
    expect(result.flaky).toHaveLength(1);
    expect(result.flaky[0]!.id).toBe("auth > login");
    expect(result.flaky[0]!.passed).toBe(2);
    expect(result.flaky[0]!.failed).toBe(1);
  });
});
