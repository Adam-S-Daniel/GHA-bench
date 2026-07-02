// Shared test fixtures. Not part of the shipped script — used only by bun:test files.
import type { Artifact } from "../src/types";

/** Builds a minimal, valid artifact with sane defaults, overridable per test. */
export function makeArtifact(overrides: Partial<Artifact>): Artifact {
  return {
    id: "artifact-1",
    name: "build-output",
    sizeInBytes: 1024,
    createdAt: new Date("2026-06-01T00:00:00Z"),
    workflowId: "ci.yml",
    workflowRunId: "run-1",
    ...overrides,
  };
}
