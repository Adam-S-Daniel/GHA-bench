import { describe, expect, test } from "bun:test";
import { resolveInputFiles, runAggregation, formatTextSummary } from "../src/aggregate";

describe("resolveInputFiles", () => {
  test("expands a directory into its .xml and .json files, sorted", async () => {
    const files = await resolveInputFiles(["fixtures"]);
    expect(files).toEqual([
      "fixtures/junit-macos-node20.xml",
      "fixtures/junit-ubuntu-node18.xml",
      "fixtures/junit-ubuntu-node20.xml",
      "fixtures/results-integration-node18.json",
      "fixtures/results-integration-node20.json",
    ]);
  });

  test("passes through explicit file paths unchanged", async () => {
    const files = await resolveInputFiles(["fixtures/junit-ubuntu-node18.xml"]);
    expect(files).toEqual(["fixtures/junit-ubuntu-node18.xml"]);
  });

  test("throws a descriptive error when a path does not exist", async () => {
    await expect(resolveInputFiles(["fixtures/does-not-exist"])).rejects.toThrow(
      /does-not-exist/,
    );
  });
});

describe("runAggregation", () => {
  test("parses mixed JUnit and JSON files and aggregates them", async () => {
    const files = await resolveInputFiles(["fixtures"]);
    const { aggregated, markdown } = await runAggregation(files);

    expect(aggregated.totalTests).toBe(21);
    expect(aggregated.passed).toBe(12);
    expect(aggregated.failed).toBe(6);
    expect(aggregated.skipped).toBe(3);
    expect(aggregated.flakyTests).toHaveLength(2);
    expect(markdown).toContain("# Test Results Summary");
  });

  test("throws a descriptive error for an unsupported file extension", async () => {
    await expect(runAggregation(["fixtures/README.txt"])).rejects.toThrow(
      /unsupported/i,
    );
  });
});

describe("formatTextSummary", () => {
  test("renders plain-text lines with exact totals for log/CI parsing", () => {
    const text = formatTextSummary({
      totalTests: 21,
      passed: 12,
      failed: 6,
      skipped: 3,
      totalDuration: 1.933,
      suites: [],
      flakyTests: [
        {
          suiteName: "UnitTests",
          classname: "math.Calculator",
          name: "testDivideByZero",
          outcomes: [],
          passCount: 1,
          failCount: 2,
        },
        {
          suiteName: "IntegrationTests",
          classname: "AuthTests",
          name: "testTokenRefresh",
          outcomes: [],
          passCount: 1,
          failCount: 1,
        },
      ],
    });

    expect(text).toContain("Total Tests: 21");
    expect(text).toContain("Passed: 12");
    expect(text).toContain("Failed: 6");
    expect(text).toContain("Skipped: 3");
    expect(text).toContain("Flaky Tests: 2");
  });
});
