import { describe, expect, test } from "bun:test";
import { parseCleanupInput } from "../src/parse.ts";

describe("parseCleanupInput", () => {
  test("parses a well-formed input document", () => {
    const raw = {
      now: "2026-06-30T00:00:00Z",
      policy: { maxAgeDays: 30, keepLatestNPerWorkflow: 2, maxTotalSizeBytes: 5000 },
      artifacts: [
        { name: "build", sizeBytes: 1024, createdAt: "2026-06-01T00:00:00Z", workflowRunId: 1 },
      ],
    };

    const parsed = parseCleanupInput(raw);

    expect(parsed.now).toEqual(new Date("2026-06-30T00:00:00Z"));
    expect(parsed.policy).toEqual({ maxAgeDays: 30, keepLatestNPerWorkflow: 2, maxTotalSizeBytes: 5000 });
    expect(parsed.artifacts).toHaveLength(1);
    expect(parsed.artifacts[0]!.name).toBe("build");
  });

  test("defaults policy to empty and now to undefined when omitted", () => {
    const parsed = parseCleanupInput({ artifacts: [] });
    expect(parsed.policy).toEqual({});
    expect(parsed.now).toBeUndefined();
    expect(parsed.artifacts).toEqual([]);
  });

  test("throws a meaningful error when the root is not an object", () => {
    expect(() => parseCleanupInput(null)).toThrow(/input must be a JSON object/i);
    expect(() => parseCleanupInput([])).toThrow(/input must be a JSON object/i);
  });

  test("throws when artifacts is missing or not an array", () => {
    expect(() => parseCleanupInput({})).toThrow(/"artifacts" must be an array/i);
    expect(() => parseCleanupInput({ artifacts: 5 })).toThrow(/"artifacts" must be an array/i);
  });

  test("throws identifying the offending artifact index on a bad field", () => {
    const raw = {
      artifacts: [
        { name: "ok", sizeBytes: 1, createdAt: "2026-06-01T00:00:00Z", workflowRunId: 1 },
        { name: "bad", sizeBytes: -3, createdAt: "2026-06-01T00:00:00Z", workflowRunId: 1 },
      ],
    };
    expect(() => parseCleanupInput(raw)).toThrow(/artifacts\[1\].*sizeBytes.*non-negative/i);
  });

  test("throws on an unparseable createdAt timestamp", () => {
    const raw = {
      artifacts: [{ name: "x", sizeBytes: 1, createdAt: "not-a-date", workflowRunId: 1 }],
    };
    expect(() => parseCleanupInput(raw)).toThrow(/artifacts\[0\].*createdAt.*valid ISO/i);
  });

  test("throws on a negative policy value", () => {
    expect(() => parseCleanupInput({ artifacts: [], policy: { maxAgeDays: -1 } })).toThrow(
      /maxAgeDays.*non-negative/i,
    );
  });
});
