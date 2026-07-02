import { describe, expect, test } from "bun:test";
import { aggregate } from "../src/aggregate";
import { parseJUnitXml } from "../src/parsers/junit";
import { parseJsonResults } from "../src/parsers/json";

describe("aggregate", () => {
  test("computes totals across multiple matrix-build files", async () => {
    const ubuntuXml = await Bun.file("fixtures/junit-run-ubuntu-node18.xml").text();
    const macosXml = await Bun.file("fixtures/junit-run-macos-node18.xml").text();
    const windowsJson = await Bun.file("fixtures/json-run-windows-node18.json").text();

    const files = [
      parseJUnitXml(ubuntuXml, "junit-run-ubuntu-node18.xml"),
      parseJUnitXml(macosXml, "junit-run-macos-node18.xml"),
      parseJsonResults(windowsJson, "json-run-windows-node18.json"),
    ];

    const result = aggregate(files);

    // ubuntu: 2 passed, 1 failed, 1 skipped
    // macos:  2 passed, 1 failed, 1 skipped
    // windows: 3 passed, 1 failed, 1 skipped
    expect(result.totals).toEqual({
      total: 13,
      passed: 7,
      failed: 3,
      skipped: 3,
      duration: expect.closeTo(0.3 + 0.25 + 0.1 + 0.2 + 0.35 + 0.25 + 0.1 + 0.2 + 0.28 + 0.22 + 0.12 + 0.18 + 0, 5),
    });
  });

  test("identifies flaky tests that pass in some runs and fail in others", async () => {
    const ubuntuXml = await Bun.file("fixtures/junit-run-ubuntu-node18.xml").text();
    const macosXml = await Bun.file("fixtures/junit-run-macos-node18.xml").text();
    const windowsJson = await Bun.file("fixtures/json-run-windows-node18.json").text();

    const files = [
      parseJUnitXml(ubuntuXml, "junit-run-ubuntu-node18.xml"),
      parseJUnitXml(macosXml, "junit-run-macos-node18.xml"),
      parseJsonResults(windowsJson, "json-run-windows-node18.json"),
    ];

    const result = aggregate(files);

    const flakyNames = result.flakyTests.map((f) => f.name).sort();
    // "adds two numbers": passed, failed, passed -> flaky
    // "divides by zero throws": failed, passed, failed -> flaky
    // "handles unicode": skipped, skipped, passed -> flaky
    // "reverses a string": passed, passed, passed -> NOT flaky
    // "supports emoji": only in one run -> NOT flaky
    expect(flakyNames).toEqual(["adds two numbers", "divides by zero throws", "handles unicode"]);

    const addsTwoNumbers = result.flakyTests.find((f) => f.name === "adds two numbers")!;
    expect(addsTwoNumbers.outcomes).toEqual([
      { source: "junit-run-ubuntu-node18.xml", status: "passed" },
      { source: "junit-run-macos-node18.xml", status: "failed" },
      { source: "json-run-windows-node18.json", status: "passed" },
    ]);
  });

  test("returns no flaky tests when a single file is aggregated", async () => {
    const raw = await Bun.file("fixtures/json-simple.json").text();
    const result = aggregate([parseJsonResults(raw, "json-simple.json")]);
    expect(result.flakyTests).toEqual([]);
  });

  test("throws a meaningful error when given zero files", () => {
    expect(() => aggregate([])).toThrow(/at least one/i);
  });
});
