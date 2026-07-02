import { describe, expect, test } from "bun:test";
import { generateMockArtifacts } from "../src/mockData";

describe("generateMockArtifacts", () => {
  test("returns a deterministic, well-formed fixture set", () => {
    const now = new Date("2026-07-01T00:00:00Z");
    const artifacts = generateMockArtifacts(now);

    // Fixture must be non-trivial: spans multiple workflows, ages, and sizes
    // so every retention policy has something to act on in the CLI demo.
    expect(artifacts.length).toBeGreaterThanOrEqual(10);

    const workflowIds = new Set(artifacts.map((a) => a.workflowId));
    expect(workflowIds.size).toBeGreaterThanOrEqual(2);

    const ids = artifacts.map((a) => a.id);
    expect(new Set(ids).size).toBe(ids.length); // no duplicate ids

    for (const artifact of artifacts) {
      expect(artifact.sizeInBytes).toBeGreaterThan(0);
      expect(artifact.createdAt.getTime()).toBeLessThanOrEqual(now.getTime());
    }
  });

  test("is deterministic across calls given the same reference date", () => {
    const now = new Date("2026-07-01T00:00:00Z");
    const first = generateMockArtifacts(now);
    const second = generateMockArtifacts(now);

    expect(second).toEqual(first);
  });

  test("defaults to the 'baseline' fixture", () => {
    const now = new Date("2026-07-01T00:00:00Z");
    expect(generateMockArtifacts(now, "baseline")).toEqual(generateMockArtifacts(now));
  });

  test("supports an 'empty-workload' fixture with nothing eligible for deletion", () => {
    const now = new Date("2026-07-01T00:00:00Z");
    const artifacts = generateMockArtifacts(now, "empty-workload");

    expect(artifacts.length).toBeGreaterThan(0);
    for (const artifact of artifacts) {
      expect(artifact.createdAt.getTime()).toBeLessThanOrEqual(now.getTime());
    }
  });

  test("throws a descriptive error for an unknown fixture name", () => {
    const now = new Date("2026-07-01T00:00:00Z");
    expect(() => generateMockArtifacts(now, "does-not-exist")).toThrow(
      'Unknown mock data fixture: "does-not-exist"',
    );
  });
});
