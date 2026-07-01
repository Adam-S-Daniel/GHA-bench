import { describe, test, expect } from "bun:test";
import { parsePolicyFromEnv, isDryRun } from "../src/main";

describe("parsePolicyFromEnv", () => {
  test("parses numeric env vars into a policy", () => {
    const policy = parsePolicyFromEnv({
      MAX_AGE_DAYS: "30",
      MAX_TOTAL_SIZE_BYTES: "1000000",
      KEEP_LATEST_PER_WORKFLOW: "2",
    } as NodeJS.ProcessEnv);

    expect(policy).toEqual({
      maxAgeDays: 30,
      maxTotalSizeBytes: 1000000,
      keepLatestPerWorkflow: 2,
    });
  });

  test("leaves fields undefined when env vars are absent", () => {
    const policy = parsePolicyFromEnv({} as NodeJS.ProcessEnv);
    expect(policy).toEqual({
      maxAgeDays: undefined,
      maxTotalSizeBytes: undefined,
      keepLatestPerWorkflow: undefined,
    });
  });

  test("throws a meaningful error for a non-numeric env var", () => {
    expect(() =>
      parsePolicyFromEnv({ MAX_AGE_DAYS: "not-a-number" } as NodeJS.ProcessEnv),
    ).toThrow(/Invalid environment value for MAX_AGE_DAYS/);
  });
});

describe("isDryRun", () => {
  test("defaults to dry-run when no flags are passed", () => {
    expect(isDryRun([])).toBe(true);
  });

  test("is false when --apply is passed", () => {
    expect(isDryRun(["--apply"])).toBe(false);
  });
});
