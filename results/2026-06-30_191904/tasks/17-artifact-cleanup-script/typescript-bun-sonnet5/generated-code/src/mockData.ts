// Mock artifact data standing in for a real GitHub Actions API response
// (e.g. `GET /repos/{owner}/{repo}/actions/artifacts`). Ages are expressed
// as offsets in days from a caller-supplied reference date so each fixture
// is fully deterministic regardless of when it's generated.
//
// Multiple named fixtures let the CI workflow (and its `act`-driven test
// harness) exercise different scenarios — e.g. a workload with nothing to
// delete versus one that trips every retention policy — by swapping the
// MOCK_DATA_FIXTURE env var rather than the code.
import type { Artifact } from "./types";

const MS_PER_DAY = 24 * 60 * 60 * 1000;

interface ArtifactSeed {
  id: string;
  name: string;
  sizeInBytes: number;
  ageInDays: number;
  workflowId: string;
  workflowRunId: string;
}

const FIXTURES: Record<string, ArtifactSeed[]> = {
  // A realistic, varied workload: spans multiple workflows and ages so that
  // max-age, keep-latest-N, and max-total-size are all exercised at once.
  baseline: [
    { id: "ci-build-105", name: "build-output", sizeInBytes: 52_428_800, ageInDays: 1, workflowId: "ci.yml", workflowRunId: "run-105" },
    { id: "ci-build-104", name: "build-output", sizeInBytes: 51_200_000, ageInDays: 3, workflowId: "ci.yml", workflowRunId: "run-104" },
    { id: "ci-build-103", name: "build-output", sizeInBytes: 50_331_648, ageInDays: 6, workflowId: "ci.yml", workflowRunId: "run-103" },
    { id: "ci-build-102", name: "build-output", sizeInBytes: 49_500_000, ageInDays: 10, workflowId: "ci.yml", workflowRunId: "run-102" },
    { id: "ci-build-101", name: "build-output", sizeInBytes: 48_000_000, ageInDays: 45, workflowId: "ci.yml", workflowRunId: "run-101" },
    { id: "ci-coverage-105", name: "coverage-report", sizeInBytes: 2_097_152, ageInDays: 1, workflowId: "ci.yml", workflowRunId: "run-105" },
    { id: "ci-coverage-104", name: "coverage-report", sizeInBytes: 2_097_152, ageInDays: 3, workflowId: "ci.yml", workflowRunId: "run-104" },
    { id: "nightly-logs-40", name: "nightly-logs", sizeInBytes: 10_485_760, ageInDays: 2, workflowId: "nightly.yml", workflowRunId: "run-40" },
    { id: "nightly-logs-39", name: "nightly-logs", sizeInBytes: 10_485_760, ageInDays: 35, workflowId: "nightly.yml", workflowRunId: "run-39" },
    { id: "nightly-logs-38", name: "nightly-logs", sizeInBytes: 10_485_760, ageInDays: 95, workflowId: "nightly.yml", workflowRunId: "run-38" },
    { id: "release-artifact-12", name: "release-bundle", sizeInBytes: 104_857_600, ageInDays: 15, workflowId: "release.yml", workflowRunId: "run-12" },
    { id: "release-artifact-11", name: "release-bundle", sizeInBytes: 100_663_296, ageInDays: 120, workflowId: "release.yml", workflowRunId: "run-11" },
  ],
  // A small, fresh, well-under-budget workload: every artifact is inside
  // the default retention policy, so the cleanup plan deletes nothing.
  "empty-workload": [
    { id: "ci-build-9", name: "build-output", sizeInBytes: 1_048_576, ageInDays: 1, workflowId: "ci.yml", workflowRunId: "run-9" },
    { id: "ci-build-8", name: "build-output", sizeInBytes: 1_048_576, ageInDays: 2, workflowId: "ci.yml", workflowRunId: "run-8" },
    { id: "docs-build-3", name: "docs-site", sizeInBytes: 524_288, ageInDays: 1, workflowId: "docs.yml", workflowRunId: "run-3" },
  ],
};

/** Returns a deterministic set of mock artifacts anchored to `now`. */
export function generateMockArtifacts(now: Date, fixtureName: string = "baseline"): Artifact[] {
  const seeds = FIXTURES[fixtureName];
  if (!seeds) {
    throw new Error(`Unknown mock data fixture: "${fixtureName}"`);
  }

  return seeds.map((seed) => ({
    id: seed.id,
    name: seed.name,
    sizeInBytes: seed.sizeInBytes,
    createdAt: new Date(now.getTime() - seed.ageInDays * MS_PER_DAY),
    workflowId: seed.workflowId,
    workflowRunId: seed.workflowRunId,
  }));
}
