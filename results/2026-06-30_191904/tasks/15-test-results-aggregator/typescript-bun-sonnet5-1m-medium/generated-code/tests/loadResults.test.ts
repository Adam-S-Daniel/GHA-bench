import { describe, expect, test } from "bun:test";
import { loadResultsFromDirectory } from "../src/loadResults";

describe("loadResultsFromDirectory", () => {
  test("auto-detects .xml as JUnit and .json as the JSON format, sorted by filename", async () => {
    const files = await loadResultsFromDirectory("fixtures");

    const bySource = Object.fromEntries(files.map((f) => [f.source, f]));
    expect(bySource["junit-run-ubuntu-node18.xml"]?.format).toBe("junit");
    expect(bySource["json-simple.json"]?.format).toBe("json");

    // Deterministic ordering makes downstream output reproducible in CI logs.
    const sourceOrder = files.map((f) => f.source);
    expect(sourceOrder).toEqual([...sourceOrder].sort());
  });

  test("throws a meaningful error for a directory that does not exist", async () => {
    await expect(loadResultsFromDirectory("fixtures/does-not-exist")).rejects.toThrow(/does not exist/);
  });

  test("throws a meaningful error when the directory has no recognized result files", async () => {
    await expect(loadResultsFromDirectory("src")).rejects.toThrow(/no .xml or .json test result files/i);
  });
});
