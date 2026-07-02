import { describe, expect, test } from "bun:test";
import { buildDeletionPlan } from "../src/planner";
import { parseArtifactsJson, parsePolicyJson } from "../src/parse";
import type { Artifact } from "../src/types";

const NOW = new Date("2026-07-01T00:00:00Z");

const valid: Artifact = {
  id: 1,
  name: "ok",
  sizeBytes: 10,
  createdAt: "2026-06-30T00:00:00Z",
  workflowRunId: 7,
};

describe("policy validation", () => {
  test("negative maxAgeDays is rejected with a clear message", () => {
    expect(() => buildDeletionPlan([valid], { maxAgeDays: -1 }, { referenceDate: NOW })).toThrow(
      "maxAgeDays must be a non-negative number, got -1",
    );
  });

  test("negative maxTotalSizeBytes is rejected", () => {
    expect(() =>
      buildDeletionPlan([valid], { maxTotalSizeBytes: -5 }, { referenceDate: NOW }),
    ).toThrow("maxTotalSizeBytes must be a non-negative number, got -5");
  });

  test("fractional keepLatestPerWorkflow is rejected", () => {
    expect(() =>
      buildDeletionPlan([valid], { keepLatestPerWorkflow: 1.5 }, { referenceDate: NOW }),
    ).toThrow("keepLatestPerWorkflow must be a non-negative integer, got 1.5");
  });
});

describe("artifact validation", () => {
  test("unparseable createdAt is rejected and names the offender", () => {
    const bad = { ...valid, createdAt: "not-a-date" };
    expect(() => buildDeletionPlan([bad], {}, { referenceDate: NOW })).toThrow(
      'artifact "ok" (id=1) has invalid createdAt: "not-a-date"',
    );
  });

  test("negative sizeBytes is rejected", () => {
    const bad = { ...valid, sizeBytes: -3 };
    expect(() => buildDeletionPlan([bad], {}, { referenceDate: NOW })).toThrow(
      'artifact "ok" (id=1) has invalid sizeBytes: -3',
    );
  });

  test("duplicate artifact ids are rejected", () => {
    expect(() =>
      buildDeletionPlan([valid, { ...valid, name: "twin" }], {}, { referenceDate: NOW }),
    ).toThrow("duplicate artifact id: 1");
  });
});

describe("JSON parsing", () => {
  test("parses a well-formed artifact array", () => {
    const parsed = parseArtifactsJson(JSON.stringify([valid]));
    expect(parsed).toEqual([valid]);
  });

  test("rejects a top-level non-array", () => {
    expect(() => parseArtifactsJson('{"nope": true}')).toThrow(
      "artifacts JSON must be an array",
    );
  });

  test("rejects malformed JSON with a helpful prefix", () => {
    expect(() => parseArtifactsJson("{oops")).toThrow(/invalid JSON/);
  });

  test("rejects an artifact entry missing required fields", () => {
    expect(() => parseArtifactsJson('[{"id": 1, "name": "x"}]')).toThrow(
      /artifact at index 0 is missing or has invalid "sizeBytes"/,
    );
  });

  test("parses a policy config including referenceDate and dryRun", () => {
    const cfg = parsePolicyJson(
      '{"maxAgeDays": 7, "keepLatestPerWorkflow": 2, "maxTotalSizeBytes": 100, "referenceDate": "2026-07-01T00:00:00Z", "dryRun": true}',
    );
    expect(cfg.policy).toEqual({ maxAgeDays: 7, keepLatestPerWorkflow: 2, maxTotalSizeBytes: 100 });
    expect(cfg.referenceDate?.toISOString()).toBe("2026-07-01T00:00:00.000Z");
    expect(cfg.dryRun).toBe(true);
  });

  test("rejects a policy config with an invalid referenceDate", () => {
    expect(() => parsePolicyJson('{"referenceDate": "yesterday-ish"}')).toThrow(
      /invalid referenceDate/,
    );
  });

  test("rejects unknown policy keys to catch typos", () => {
    expect(() => parsePolicyJson('{"maxAgeDay": 7}')).toThrow(
      /unknown policy key "maxAgeDay"/,
    );
  });
});
