import { describe, expect, test } from "bun:test";
import { aggregate } from "../src/aggregator";
import { parseJUnitXml } from "../src/parsers/junit";
import { parseJsonResults } from "../src/parsers/json";
import type { TestSuiteResult } from "../src/types";

describe("aggregate", () => {
  test("sums totals across multiple suites", () => {
    const suites: TestSuiteResult[] = [
      {
        suiteName: "A",
        source: "a.xml",
        tests: [
          { name: "t1", classname: "C", status: "passed", duration: 1 },
          { name: "t2", classname: "C", status: "failed", duration: 2 },
        ],
      },
      {
        suiteName: "A",
        source: "b.xml",
        tests: [
          { name: "t1", classname: "C", status: "passed", duration: 1.5 },
          { name: "t3", classname: "C", status: "skipped", duration: 0 },
        ],
      },
    ];

    const result = aggregate(suites);

    expect(result.totalTests).toBe(4);
    expect(result.passed).toBe(2);
    expect(result.failed).toBe(1);
    expect(result.skipped).toBe(1);
    expect(result.totalDuration).toBeCloseTo(4.5);
    expect(result.suites).toEqual(suites);
  });

  test("identifies a test as flaky when it passes in one run and fails in another", () => {
    const suites: TestSuiteResult[] = [
      {
        suiteName: "A",
        source: "run1.xml",
        tests: [{ name: "t1", classname: "C", status: "failed", duration: 1 }],
      },
      {
        suiteName: "A",
        source: "run2.xml",
        tests: [{ name: "t1", classname: "C", status: "passed", duration: 1 }],
      },
    ];

    const result = aggregate(suites);

    expect(result.flakyTests).toHaveLength(1);
    expect(result.flakyTests[0]).toEqual({
      suiteName: "A",
      classname: "C",
      name: "t1",
      outcomes: [
        { source: "run1.xml", status: "failed" },
        { source: "run2.xml", status: "passed" },
      ],
      passCount: 1,
      failCount: 1,
    });
  });

  test("does not flag a consistently failing test as flaky", () => {
    const suites: TestSuiteResult[] = [
      {
        suiteName: "A",
        source: "run1.xml",
        tests: [{ name: "t1", classname: "C", status: "failed", duration: 1 }],
      },
      {
        suiteName: "A",
        source: "run2.xml",
        tests: [{ name: "t1", classname: "C", status: "failed", duration: 1 }],
      },
    ];

    const result = aggregate(suites);
    expect(result.flakyTests).toHaveLength(0);
  });

  test("does not flag a consistently skipped test as flaky", () => {
    const suites: TestSuiteResult[] = [
      {
        suiteName: "A",
        source: "run1.xml",
        tests: [{ name: "t1", classname: "C", status: "skipped", duration: 0 }],
      },
      {
        suiteName: "A",
        source: "run2.xml",
        tests: [{ name: "t1", classname: "C", status: "skipped", duration: 0 }],
      },
    ];

    const result = aggregate(suites);
    expect(result.flakyTests).toHaveLength(0);
  });

  test("aggregates the full fixture set (3 JUnit + 2 JSON runs) with expected totals and flaky tests", async () => {
    const files = [
      "fixtures/junit-ubuntu-node18.xml",
      "fixtures/junit-ubuntu-node20.xml",
      "fixtures/junit-macos-node20.xml",
    ];
    const junitSuites = await Promise.all(
      files.map(async (f) => parseJUnitXml(await Bun.file(f).text(), f)),
    );
    const jsonFiles = [
      "fixtures/results-integration-node18.json",
      "fixtures/results-integration-node20.json",
    ];
    const jsonSuites = await Promise.all(
      jsonFiles.map(async (f) => parseJsonResults(await Bun.file(f).text(), f)),
    );

    const result = aggregate([...junitSuites, ...jsonSuites]);

    expect(result.totalTests).toBe(21);
    expect(result.passed).toBe(12);
    expect(result.failed).toBe(6);
    expect(result.skipped).toBe(3);
    expect(result.totalDuration).toBeCloseTo(1.933, 3);

    const flakyNames = result.flakyTests.map((f) => f.name).sort();
    expect(flakyNames).toEqual(["testDivideByZero", "testTokenRefresh"]);

    const divideByZero = result.flakyTests.find((f) => f.name === "testDivideByZero");
    expect(divideByZero?.passCount).toBe(1);
    expect(divideByZero?.failCount).toBe(2);

    const tokenRefresh = result.flakyTests.find((f) => f.name === "testTokenRefresh");
    expect(tokenRefresh?.passCount).toBe(1);
    expect(tokenRefresh?.failCount).toBe(1);
  });
});
