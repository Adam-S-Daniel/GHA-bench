import { describe, expect, test } from "bun:test";
import { validateArtifacts, validatePolicy } from "../src/validation";
import { makeArtifact } from "./helpers";

describe("validatePolicy", () => {
  test("rejects a negative maxAgeInDays with a descriptive message", () => {
    expect(() => validatePolicy({ maxAgeInDays: -1 })).toThrow(
      "maxAgeInDays must be >= 0, got -1",
    );
  });

  test("rejects a negative keepLatestN with a descriptive message", () => {
    expect(() => validatePolicy({ keepLatestN: -3 })).toThrow(
      "keepLatestN must be >= 0, got -3",
    );
  });

  test("rejects a negative maxTotalSizeInBytes with a descriptive message", () => {
    expect(() => validatePolicy({ maxTotalSizeInBytes: -100 })).toThrow(
      "maxTotalSizeInBytes must be >= 0, got -100",
    );
  });

  test("accepts an empty policy and a policy with all fields set", () => {
    expect(() => validatePolicy({})).not.toThrow();
    expect(() =>
      validatePolicy({ maxAgeInDays: 30, keepLatestN: 5, maxTotalSizeInBytes: 1000 }),
    ).not.toThrow();
  });
});

describe("validateArtifacts", () => {
  test("rejects an artifact with a negative size", () => {
    const artifacts = [makeArtifact({ id: "bad", sizeInBytes: -1 })];
    expect(() => validateArtifacts(artifacts)).toThrow(
      'artifact "bad" has invalid sizeInBytes: -1 (must be >= 0)',
    );
  });

  test("rejects an artifact with an invalid createdAt date", () => {
    const artifacts = [makeArtifact({ id: "bad", createdAt: new Date("not-a-date") })];
    expect(() => validateArtifacts(artifacts)).toThrow(
      'artifact "bad" has an invalid createdAt date',
    );
  });

  test("rejects an artifact with an empty id", () => {
    const artifacts = [makeArtifact({ id: "" })];
    expect(() => validateArtifacts(artifacts)).toThrow("artifact is missing a non-empty id");
  });

  test("rejects duplicate artifact ids", () => {
    const artifacts = [makeArtifact({ id: "dup" }), makeArtifact({ id: "dup" })];
    expect(() => validateArtifacts(artifacts)).toThrow('duplicate artifact id: "dup"');
  });

  test("accepts a well-formed artifact list", () => {
    const artifacts = [makeArtifact({ id: "a" }), makeArtifact({ id: "b" })];
    expect(() => validateArtifacts(artifacts)).not.toThrow();
  });
});
