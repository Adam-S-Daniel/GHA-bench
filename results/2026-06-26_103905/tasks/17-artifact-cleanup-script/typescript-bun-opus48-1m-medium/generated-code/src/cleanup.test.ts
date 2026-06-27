import { describe, expect, test } from "bun:test";
import {
  parseArtifacts,
  planDeletion,
  summarize,
  type Artifact,
  type RetentionPolicy,
} from "./cleanup.ts";

// A fixed "now" so age-based tests are deterministic regardless of wall clock.
const NOW = new Date("2026-06-27T00:00:00Z");

/** Helper: build an artifact with sensible defaults, overriding as needed. */
function makeArtifact(overrides: Partial<Artifact> = {}): Artifact {
  return {
    name: "build-output",
    sizeBytes: 1_000,
    createdAt: "2026-06-26T00:00:00Z",
    workflowRunId: "run-1",
    ...overrides,
  };
}

describe("max-age policy", () => {
  test("deletes artifacts older than maxAgeDays and retains newer ones", () => {
    const artifacts: Artifact[] = [
      makeArtifact({ name: "old", createdAt: "2026-06-01T00:00:00Z" }), // 26 days old
      makeArtifact({ name: "fresh", createdAt: "2026-06-25T00:00:00Z" }), // 2 days old
    ];
    const policy: RetentionPolicy = { maxAgeDays: 7 };

    const plan = planDeletion(artifacts, policy, NOW);

    expect(plan.toDelete.map((a) => a.name)).toEqual(["old"]);
    expect(plan.toRetain.map((a) => a.name)).toEqual(["fresh"]);
  });
});

describe("keep-latest-N-per-workflow policy", () => {
  test("keeps the N newest artifacts per workflow run, deletes older ones", () => {
    const artifacts: Artifact[] = [
      // workflow A: 3 artifacts, keep 2 newest (a3, a2), delete a1
      makeArtifact({ name: "a1", workflowRunId: "A", createdAt: "2026-06-01T00:00:00Z" }),
      makeArtifact({ name: "a2", workflowRunId: "A", createdAt: "2026-06-02T00:00:00Z" }),
      makeArtifact({ name: "a3", workflowRunId: "A", createdAt: "2026-06-03T00:00:00Z" }),
      // workflow B: 1 artifact, kept (under the limit)
      makeArtifact({ name: "b1", workflowRunId: "B", createdAt: "2026-06-01T00:00:00Z" }),
    ];
    const policy: RetentionPolicy = { keepLatestNPerWorkflow: 2 };

    const plan = planDeletion(artifacts, policy, NOW);

    expect(plan.toDelete.map((a) => a.name).sort()).toEqual(["a1"]);
    expect(plan.toRetain.map((a) => a.name).sort()).toEqual(["a2", "a3", "b1"]);
  });
});

describe("max-total-size policy", () => {
  test("deletes oldest artifacts until retained total fits the budget", () => {
    const artifacts: Artifact[] = [
      makeArtifact({ name: "newest", sizeBytes: 100, createdAt: "2026-06-25T00:00:00Z" }),
      makeArtifact({ name: "middle", sizeBytes: 100, createdAt: "2026-06-20T00:00:00Z" }),
      makeArtifact({ name: "oldest", sizeBytes: 100, createdAt: "2026-06-15T00:00:00Z" }),
    ];
    // Budget fits only two 100-byte artifacts; oldest must go.
    const policy: RetentionPolicy = { maxTotalSizeBytes: 200 };

    const plan = planDeletion(artifacts, policy, NOW);

    expect(plan.toDelete.map((a) => a.name)).toEqual(["oldest"]);
    expect(plan.toRetain.map((a) => a.name).sort()).toEqual(["middle", "newest"]);
  });
});

describe("combined policies", () => {
  test("an artifact removed by any policy is deleted (union of stages)", () => {
    const artifacts: Artifact[] = [
      makeArtifact({ name: "ancient", workflowRunId: "A", sizeBytes: 50, createdAt: "2026-01-01T00:00:00Z" }),
      makeArtifact({ name: "extra", workflowRunId: "A", sizeBytes: 50, createdAt: "2026-06-20T00:00:00Z" }),
      makeArtifact({ name: "keep", workflowRunId: "A", sizeBytes: 50, createdAt: "2026-06-26T00:00:00Z" }),
    ];
    const policy: RetentionPolicy = {
      maxAgeDays: 30, // removes "ancient"
      keepLatestNPerWorkflow: 1, // of the survivors keep only newest -> removes "extra"
    };

    const plan = planDeletion(artifacts, policy, NOW);

    expect(plan.toDelete.map((a) => a.name).sort()).toEqual(["ancient", "extra"]);
    expect(plan.toRetain.map((a) => a.name)).toEqual(["keep"]);
  });
});

describe("summarize", () => {
  test("reports counts and reclaimed space", () => {
    const plan = {
      toDelete: [
        makeArtifact({ name: "d1", sizeBytes: 300 }),
        makeArtifact({ name: "d2", sizeBytes: 700 }),
      ],
      toRetain: [makeArtifact({ name: "r1", sizeBytes: 500 })],
    };

    const summary = summarize(plan);

    expect(summary.deletedCount).toBe(2);
    expect(summary.retainedCount).toBe(1);
    expect(summary.spaceReclaimedBytes).toBe(1000);
    expect(summary.retainedSizeBytes).toBe(500);
  });
});

describe("parseArtifacts (input validation)", () => {
  test("parses a well-formed artifact array", () => {
    const json = JSON.stringify([
      { name: "x", sizeBytes: 10, createdAt: "2026-06-01T00:00:00Z", workflowRunId: "r1" },
    ]);
    expect(parseArtifacts(json)).toHaveLength(1);
  });

  test("throws a meaningful error on invalid JSON", () => {
    expect(() => parseArtifacts("{not json")).toThrow(/invalid json/i);
  });

  test("throws when the top-level value is not an array", () => {
    expect(() => parseArtifacts(JSON.stringify({ name: "x" }))).toThrow(/must be a json array/i);
  });

  test("throws when an artifact is missing a required field", () => {
    const json = JSON.stringify([{ name: "x", sizeBytes: 10, createdAt: "2026-06-01T00:00:00Z" }]);
    expect(() => parseArtifacts(json)).toThrow(/workflowRunId/);
  });

  test("throws when sizeBytes is negative", () => {
    const json = JSON.stringify([
      { name: "x", sizeBytes: -5, createdAt: "2026-06-01T00:00:00Z", workflowRunId: "r1" },
    ]);
    expect(() => parseArtifacts(json)).toThrow(/sizeBytes/);
  });

  test("throws when createdAt is not a valid date", () => {
    const json = JSON.stringify([
      { name: "x", sizeBytes: 5, createdAt: "not-a-date", workflowRunId: "r1" },
    ]);
    expect(() => parseArtifacts(json)).toThrow(/createdAt/);
  });
});
