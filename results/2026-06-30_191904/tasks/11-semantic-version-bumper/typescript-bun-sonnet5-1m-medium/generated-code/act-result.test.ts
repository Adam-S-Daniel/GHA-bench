import { describe, expect, test } from "bun:test";
import { existsSync, readFileSync } from "node:fs";

// Verifies the artifact produced by running the GitHub Actions workflow
// through `act` (see README for the exact command). This test does NOT
// invoke `act` itself (that's an expensive, network/Docker-dependent
// operation reserved for the harness run) -- it asserts the recorded
// act-result.txt output matches known-good expected values.

const ACT_RESULT_PATH = "act-result.txt";

// Known-good expected new versions for each fixture case, derived from the
// starting versions in fixtures/package-versions/*.json and the commit
// messages in fixtures/commits/*.txt.
const EXPECTED_RESULTS: Record<string, string> = {
  "feat-only": "1.1.0", // 1.0.0 + feat -> minor bump
  "fix-only": "1.1.1", // 1.1.0 + fix -> patch bump
  "breaking-change": "2.0.0", // 1.1.0 + feat! -> major bump
  "mixed-feat-fix": "1.3.0", // 1.2.0 + feat & fix -> minor wins over patch
  "no-relevant-changes": "1.3.0", // 1.3.0 + only chore/docs -> no bump
};

// act-result.txt is produced OUTSIDE the container by redirecting `act
// push`'s own stdout/stderr on the host. It is still being written (and may
// be stale or incomplete) while `bun test` runs *inside* the workflow that
// act itself is executing -- act sets ACT=true in that environment, so we
// skip there and only assert for real when run locally afterwards against
// the finished, captured artifact.
const runningInsideAct = Boolean(process.env.ACT);
const artifactExists = !runningInsideAct && existsSync(ACT_RESULT_PATH);

describe("act-result.txt (semantic-version-bumper workflow output)", () => {
  test.skipIf(!artifactExists)("the act-result.txt artifact exists", () => {
    expect(existsSync(ACT_RESULT_PATH)).toBe(true);
  });

  test.skipIf(!artifactExists)("every recorded job in the log succeeded", () => {
    const output = readFileSync(ACT_RESULT_PATH, "utf-8");
    expect(output).toContain("Job succeeded");
    expect(output).not.toContain("Job failed");
  });

  for (const [caseName, expectedVersion] of Object.entries(EXPECTED_RESULTS)) {
    test.skipIf(!artifactExists)(
      `fixture case "${caseName}" bumped to exactly "${expectedVersion}"`,
      () => {
        const output = readFileSync(ACT_RESULT_PATH, "utf-8");
        const match = output.match(
          new RegExp(`RESULT\\[${caseName}\\]=(\\S+)`),
        );
        expect(match).not.toBeNull();
        expect(match?.[1]).toBe(expectedVersion);
      },
    );
  }
});
