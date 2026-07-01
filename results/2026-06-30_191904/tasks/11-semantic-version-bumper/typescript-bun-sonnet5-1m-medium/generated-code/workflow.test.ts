import { describe, expect, test } from "bun:test";
import { existsSync, readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { parse } from "yaml";

// Structural checks on the GitHub Actions workflow itself: this does NOT run
// the workflow (that happens via `act`, see the act test harness), it only
// verifies the YAML is well-formed and wired up correctly, and that
// actionlint accepts it.

const WORKFLOW_PATH = ".github/workflows/semantic-version-bumper.yml";

describe("semantic-version-bumper workflow", () => {
  test("workflow file exists and is valid YAML", () => {
    expect(existsSync(WORKFLOW_PATH)).toBe(true);
    const doc = parse(readFileSync(WORKFLOW_PATH, "utf-8"));
    expect(doc).toBeTruthy();
  });

  test("declares push, pull_request, and workflow_dispatch triggers", () => {
    const doc = parse(readFileSync(WORKFLOW_PATH, "utf-8"));
    // YAML parses bare `on:` as boolean key `true` in some parsers, but the
    // `yaml` package preserves it as the string "on".
    const triggers = doc.on;
    expect(triggers).toHaveProperty("push");
    expect(triggers).toHaveProperty("pull_request");
    expect(triggers).toHaveProperty("workflow_dispatch");
  });

  test("defines a job that checks out the repo, installs Bun, and runs tests", () => {
    const doc = parse(readFileSync(WORKFLOW_PATH, "utf-8"));
    const jobs = doc.jobs;
    expect(jobs).toBeTruthy();

    const steps = Object.values(jobs).flatMap((job: any) => job.steps);
    const usesList = steps.map((s: any) => s.uses).filter(Boolean);
    const runList = steps.map((s: any) => s.run).filter(Boolean);

    expect(usesList).toContain("actions/checkout@v4");
    expect(usesList.some((u: string) => u.startsWith("oven-sh/setup-bun@"))).toBe(
      true,
    );
    expect(runList.some((r: string) => r.includes("bun test"))).toBe(true);
  });

  test("references the real script and fixture files, and they exist on disk", () => {
    const doc = parse(readFileSync(WORKFLOW_PATH, "utf-8"));
    const jobs = doc.jobs;
    const steps = Object.values(jobs).flatMap((job: any) => job.steps);
    const runList: string[] = steps.map((s: any) => s.run).filter(Boolean);
    const combined = runList.join("\n");

    const referencedPaths = [
      ...combined.matchAll(/(src\/index\.ts|fixtures\/[\w./-]+)/g),
    ].map((m) => m[0]);

    expect(referencedPaths.length).toBeGreaterThan(0);
    for (const path of new Set(referencedPaths)) {
      expect(existsSync(path)).toBe(true);
    }
  });

  // actionlint isn't installed in the act container image used to run the
  // fixture-driven bump steps, so this check is skipped there; it still runs
  // (and is required to pass) in the local dev/CI environment.
  const actionlintAvailable = Boolean(Bun.which("actionlint"));
  test.skipIf(!actionlintAvailable)(
    "actionlint accepts the workflow file",
    () => {
      const result = spawnSync("actionlint", [WORKFLOW_PATH], {
        encoding: "utf-8",
      });
      expect(result.status).toBe(0);
    },
  );
});
