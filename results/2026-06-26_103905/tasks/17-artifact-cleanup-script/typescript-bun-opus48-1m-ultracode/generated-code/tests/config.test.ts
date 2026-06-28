import { describe, test, expect } from "bun:test";
import { parseConfig } from "../src/config.ts";

describe("parseConfig", () => {
  test("parses a full config with artifacts, policy and now", () => {
    const cfg = parseConfig({
      now: "2026-01-01T00:00:00Z",
      policy: { maxAgeDays: 30, keepLatestNPerWorkflow: 2, maxTotalSizeBytes: 10000 },
      artifacts: [
        { id: "a1", name: "build", sizeBytes: 10, createdAt: "2025-12-31T00:00:00Z", workflowRunId: "wf-1" },
      ],
    });
    expect(cfg.artifacts.length).toBe(1);
    expect(cfg.policy.maxAgeDays).toBe(30);
    expect(cfg.now).toBeInstanceOf(Date);
    expect(cfg.now?.toISOString()).toBe("2026-01-01T00:00:00.000Z");
  });

  test("defaults policy to an empty object and now to undefined when omitted", () => {
    const cfg = parseConfig({ artifacts: [] });
    expect(cfg.policy).toEqual({});
    expect(cfg.now).toBeUndefined();
  });

  test("throws a meaningful error when artifacts is missing", () => {
    expect(() => parseConfig({ policy: {} })).toThrow(/"artifacts"/);
  });

  test("throws when the top-level value is not an object", () => {
    expect(() => parseConfig(42)).toThrow(/config must be an object/);
  });

  test("throws when 'now' is not a valid date string", () => {
    expect(() => parseConfig({ artifacts: [], now: "nonsense" })).toThrow(/"now"/);
  });
});
