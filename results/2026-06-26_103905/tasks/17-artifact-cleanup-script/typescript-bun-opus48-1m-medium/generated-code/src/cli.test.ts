import { describe, expect, test } from "bun:test";
import { parseArgs, renderReport } from "./cli.ts";

const FIXTURE = JSON.stringify([
  { name: "old", sizeBytes: 100, createdAt: "2026-06-01T00:00:00Z", workflowRunId: "A" },
  { name: "fresh", sizeBytes: 200, createdAt: "2026-06-26T00:00:00Z", workflowRunId: "A" },
]);

describe("parseArgs", () => {
  test("parses policy flags, --dry-run and --now", () => {
    const opts = parseArgs([
      "--input", "f.json",
      "--max-age-days", "7",
      "--max-total-size-bytes", "1000",
      "--keep-latest-n", "3",
      "--dry-run",
      "--now", "2026-06-27T00:00:00Z",
    ]);
    expect(opts.input).toBe("f.json");
    expect(opts.policy.maxAgeDays).toBe(7);
    expect(opts.policy.maxTotalSizeBytes).toBe(1000);
    expect(opts.policy.keepLatestNPerWorkflow).toBe(3);
    expect(opts.dryRun).toBe(true);
    expect(opts.now.toISOString()).toBe("2026-06-27T00:00:00.000Z");
  });

  test("throws when --input is missing", () => {
    expect(() => parseArgs(["--max-age-days", "7"])).toThrow(/--input/);
  });

  test("throws on unknown argument", () => {
    expect(() => parseArgs(["--input", "f", "--bogus"])).toThrow(/Unknown argument/);
  });
});

describe("renderReport", () => {
  test("emits a SUMMARY line with exact computed values (dry-run)", () => {
    const opts = parseArgs(["--input", "f.json", "--max-age-days", "7", "--dry-run", "--now", "2026-06-27T00:00:00Z"]);
    const report = renderReport(opts, FIXTURE);

    expect(report).toContain("MODE=dry-run");
    expect(report).toContain("DELETE name=old");
    expect(report).toContain("RETAIN name=fresh");
    expect(report).toContain("SUMMARY deleted=1 retained=1 reclaimedBytes=100 retainedBytes=200");
    expect(report).toContain("dry-run: no artifacts were actually deleted");
  });

  test("execute mode prints a RESULT line", () => {
    const opts = parseArgs(["--input", "f.json", "--max-age-days", "7", "--now", "2026-06-27T00:00:00Z"]);
    const report = renderReport(opts, FIXTURE);
    expect(report).toContain("MODE=execute");
    expect(report).toContain("RESULT deleted 1 artifact(s), reclaimed 100 bytes.");
  });
});
