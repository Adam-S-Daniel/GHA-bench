import { describe, it, expect } from "bun:test";
import { loadResultFiles } from "../src/index";
import { aggregate } from "../src/aggregator";

describe("loadResultFiles", () => {
  it("loads and parses all XML and JSON fixture files from a directory", async () => {
    const files = await loadResultFiles("fixtures");

    expect(files).toHaveLength(3);
    const sources = files.map((f) => f.source);
    expect(sources).toContain("run1.xml");
    expect(sources).toContain("run2.xml");
    expect(sources).toContain("run3.json");
  });

  it("aggregates the fixture files into expected totals and flaky tests", async () => {
    const files = await loadResultFiles("fixtures");
    const result = aggregate(files);

    // 4 tests/run x 2 xml runs + 4 tests in json run = 12 total
    expect(result.totals.total).toBe(12);
    expect(result.totals.failed).toBe(4);
    expect(result.totals.skipped).toBe(3);
    expect(result.totals.passed).toBe(5);

    const flakyNames = result.flakyTests.map((f) => f.name);
    expect(flakyNames).toContain("testSubtraction");
  });

  it("throws a meaningful error for unsupported file extensions", async () => {
    await expect(loadResultFiles("src")).rejects.toThrow(/unsupported/i);
  });
});
