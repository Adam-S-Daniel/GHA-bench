import { describe, expect, test } from "bun:test";
import {
  DEFAULT_POLICY,
  parseDryRunFlag,
  parseFixtureName,
  parsePolicyFromEnv,
} from "../src/envConfig";

describe("parsePolicyFromEnv", () => {
  test("falls back to sane defaults when no env vars are set", () => {
    expect(parsePolicyFromEnv({})).toEqual(DEFAULT_POLICY);
  });

  test("overrides individual fields from env vars", () => {
    const policy = parsePolicyFromEnv({ MAX_AGE_DAYS: "10", KEEP_LATEST_N: "1" });

    expect(policy).toEqual({
      ...DEFAULT_POLICY,
      maxAgeInDays: 10,
      keepLatestN: 1,
    });
  });

  test("throws a descriptive error for a non-numeric env var", () => {
    expect(() => parsePolicyFromEnv({ MAX_AGE_DAYS: "not-a-number" })).toThrow(
      'MAX_AGE_DAYS must be a number, got "not-a-number"',
    );
  });
});

describe("parseDryRunFlag", () => {
  test("defaults to true (safe) when DRY_RUN is unset", () => {
    expect(parseDryRunFlag({})).toBe(true);
  });

  test("parses explicit true/false values", () => {
    expect(parseDryRunFlag({ DRY_RUN: "false" })).toBe(false);
    expect(parseDryRunFlag({ DRY_RUN: "true" })).toBe(true);
  });

  test("throws a descriptive error for an unrecognized value", () => {
    expect(() => parseDryRunFlag({ DRY_RUN: "maybe" })).toThrow(
      'DRY_RUN must be "true" or "false", got "maybe"',
    );
  });
});

describe("parseFixtureName", () => {
  test("defaults to 'baseline' when MOCK_DATA_FIXTURE is unset", () => {
    expect(parseFixtureName({})).toBe("baseline");
  });

  test("passes through an explicit fixture name", () => {
    expect(parseFixtureName({ MOCK_DATA_FIXTURE: "empty-workload" })).toBe("empty-workload");
  });
});
