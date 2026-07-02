// Mock artifact data standing in for a real GitHub Actions API response.
import type { Artifact } from "./types";

export const mockArtifacts: Artifact[] = [
  {
    id: "1",
    name: "build-output",
    sizeBytes: 50_000_000,
    createdAt: "2026-01-15T00:00:00.000Z",
    workflowRunId: "run-101",
    workflowName: "ci",
  },
  {
    id: "2",
    name: "build-output",
    sizeBytes: 55_000_000,
    createdAt: "2026-03-10T00:00:00.000Z",
    workflowRunId: "run-102",
    workflowName: "ci",
  },
  {
    id: "3",
    name: "build-output",
    sizeBytes: 60_000_000,
    createdAt: "2026-06-25T00:00:00.000Z",
    workflowRunId: "run-103",
    workflowName: "ci",
  },
  {
    id: "4",
    name: "test-report",
    sizeBytes: 5_000_000,
    createdAt: "2026-06-28T00:00:00.000Z",
    workflowRunId: "run-201",
    workflowName: "e2e-tests",
  },
  {
    id: "5",
    name: "coverage-report",
    sizeBytes: 2_000_000,
    createdAt: "2026-06-29T00:00:00.000Z",
    workflowRunId: "run-202",
    workflowName: "e2e-tests",
  },
];
