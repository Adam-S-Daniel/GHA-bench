// Exercises runBump against the mock commit-log fixtures in fixtures/,
// copied into a scratch temp dir first so the run never mutates the
// checked-in fixture files (the same fixtures also back the GitHub Actions
// pipeline test cases run via `act` — see tests/meta/workflow-act.test.ts).
import { describe, expect, test } from "bun:test";
import { cp, mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { runBump } from "../../src/bump.ts";

const FIXTURES_DIR = join(import.meta.dir, "..", "..", "fixtures");

async function runFixture(name: string) {
  const dir = await mkdtemp(join(tmpdir(), `svb-fixture-${name}-`));
  try {
    await cp(join(FIXTURES_DIR, name, "package.json"), join(dir, "package.json"));
    await cp(join(FIXTURES_DIR, name, "commits.log"), join(dir, "commits.log"));
    return await runBump({
      versionFilePath: join(dir, "package.json"),
      commitsLogPath: join(dir, "commits.log"),
      changelogPath: join(dir, "CHANGELOG.md"),
      date: "2026-01-08",
    });
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}

describe("mock commit-log fixtures", () => {
  test("patch-fix-only: a lone fix commit bumps the patch version", async () => {
    const result = await runFixture("patch-fix-only");
    expect(result.previousVersion).toBe("2.3.1");
    expect(result.bumpType).toBe("patch");
    expect(result.newVersion).toBe("2.3.2");
  });

  test("minor-feature: a feat commit outranks an accompanying fix, bumping minor", async () => {
    const result = await runFixture("minor-feature");
    expect(result.previousVersion).toBe("1.1.0");
    expect(result.bumpType).toBe("minor");
    expect(result.newVersion).toBe("1.2.0");
  });

  test("major-breaking: a breaking-change commit outranks feat/fix, bumping major", async () => {
    const result = await runFixture("major-breaking");
    expect(result.previousVersion).toBe("1.1.0");
    expect(result.bumpType).toBe("major");
    expect(result.newVersion).toBe("2.0.0");
  });

  test("no-conventional-commits: chore/docs-only commits leave the version unchanged", async () => {
    const result = await runFixture("no-conventional-commits");
    expect(result.previousVersion).toBe("0.9.5");
    expect(result.bumpType).toBe("none");
    expect(result.newVersion).toBe("0.9.5");
  });
});
