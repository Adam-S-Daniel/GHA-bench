import { describe, expect, test } from "bun:test";
import {
  applyKeepLatestNPolicy,
  applyMaxAgePolicy,
  applyMaxTotalSizePolicy,
} from "../src/retention";
import { makeArtifact } from "./helpers";

describe("applyMaxAgePolicy", () => {
  test("marks artifacts older than maxAgeInDays for deletion", () => {
    const now = new Date("2026-07-01T00:00:00Z");
    const old = makeArtifact({
      id: "old",
      createdAt: new Date("2026-06-01T00:00:00Z"), // 30 days old
    });
    const recent = makeArtifact({
      id: "recent",
      createdAt: new Date("2026-06-29T00:00:00Z"), // 2 days old
    });

    const result = applyMaxAgePolicy([old, recent], 7, now);

    expect(result.retained.map((a) => a.id)).toEqual(["recent"]);
    expect(result.deleted.map((a) => a.id)).toEqual(["old"]);
  });

  test("retains everything when maxAgeInDays is undefined", () => {
    const now = new Date("2026-07-01T00:00:00Z");
    const artifact = makeArtifact({ id: "a" });

    const result = applyMaxAgePolicy([artifact], undefined, now);

    expect(result.retained.map((a) => a.id)).toEqual(["a"]);
    expect(result.deleted).toEqual([]);
  });
});

describe("applyKeepLatestNPolicy", () => {
  test("keeps only the N most recent artifacts per workflowId", () => {
    const artifacts = [
      makeArtifact({ id: "ci-1", workflowId: "ci.yml", createdAt: new Date("2026-06-01T00:00:00Z") }),
      makeArtifact({ id: "ci-2", workflowId: "ci.yml", createdAt: new Date("2026-06-03T00:00:00Z") }),
      makeArtifact({ id: "ci-3", workflowId: "ci.yml", createdAt: new Date("2026-06-05T00:00:00Z") }),
      makeArtifact({ id: "release-1", workflowId: "release.yml", createdAt: new Date("2026-06-02T00:00:00Z") }),
    ];

    const result = applyKeepLatestNPolicy(artifacts, 2);

    // ci.yml keeps the 2 newest (ci-3, ci-2); ci-1 is deleted.
    // release.yml has only 1 artifact, so it's kept outright.
    expect(result.retained.map((a) => a.id).sort()).toEqual(["ci-2", "ci-3", "release-1"]);
    expect(result.deleted.map((a) => a.id)).toEqual(["ci-1"]);
  });

  test("retains everything when keepLatestN is undefined", () => {
    const artifacts = [makeArtifact({ id: "a" }), makeArtifact({ id: "b" })];

    const result = applyKeepLatestNPolicy(artifacts, undefined);

    expect(result.retained.map((a) => a.id).sort()).toEqual(["a", "b"]);
    expect(result.deleted).toEqual([]);
  });

  test("deletes all artifacts in a workflow when keepLatestN is 0", () => {
    const artifacts = [
      makeArtifact({ id: "a", workflowId: "ci.yml" }),
      makeArtifact({ id: "b", workflowId: "ci.yml" }),
    ];

    const result = applyKeepLatestNPolicy(artifacts, 0);

    expect(result.retained).toEqual([]);
    expect(result.deleted.map((a) => a.id).sort()).toEqual(["a", "b"]);
  });
});

describe("applyMaxTotalSizePolicy", () => {
  test("deletes oldest artifacts first until total size is within budget", () => {
    const artifacts = [
      makeArtifact({ id: "newest", sizeInBytes: 100, createdAt: new Date("2026-06-05T00:00:00Z") }),
      makeArtifact({ id: "middle", sizeInBytes: 100, createdAt: new Date("2026-06-03T00:00:00Z") }),
      makeArtifact({ id: "oldest", sizeInBytes: 100, createdAt: new Date("2026-06-01T00:00:00Z") }),
    ];

    // Budget only fits 2 of the 3 artifacts; the oldest must go first.
    const result = applyMaxTotalSizePolicy(artifacts, 200);

    expect(result.retained.map((a) => a.id).sort()).toEqual(["middle", "newest"]);
    expect(result.deleted.map((a) => a.id)).toEqual(["oldest"]);
  });

  test("retains everything when maxTotalSizeInBytes is undefined", () => {
    const artifacts = [makeArtifact({ id: "a", sizeInBytes: 1_000_000 })];

    const result = applyMaxTotalSizePolicy(artifacts, undefined);

    expect(result.retained.map((a) => a.id)).toEqual(["a"]);
    expect(result.deleted).toEqual([]);
  });

  test("retains everything when already within budget", () => {
    const artifacts = [
      makeArtifact({ id: "a", sizeInBytes: 50 }),
      makeArtifact({ id: "b", sizeInBytes: 50 }),
    ];

    const result = applyMaxTotalSizePolicy(artifacts, 1000);

    expect(result.retained.map((a) => a.id).sort()).toEqual(["a", "b"]);
    expect(result.deleted).toEqual([]);
  });
});
