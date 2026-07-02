// TDD step 5: CLI orchestration (parser + license lookup + checker + report).
// Exercised against real fixture files on disk since it's the integration
// point between all previously-tested units.
import { describe, expect, test } from "bun:test";
import { runCli } from "../src/cli";

describe("runCli", () => {
  test("produces an exit code of 0 and an approved-only report for clean deps", async () => {
    const result = await runCli({
      manifestPath: "fixtures/package-approved.json",
      policyPath: "fixtures/license-policy.json",
      licenseDbPath: "fixtures/license-db.json",
      format: "text",
    });

    expect(result.exitCode).toBe(0);
    expect(result.report.summary.denied).toBe(0);
    expect(result.output).toContain("APPROVED");
  });

  test("produces a non-zero exit code when a denied license is present", async () => {
    const result = await runCli({
      manifestPath: "fixtures/package-denied.json",
      policyPath: "fixtures/license-policy.json",
      licenseDbPath: "fixtures/license-db.json",
      format: "text",
    });

    expect(result.exitCode).toBe(1);
    expect(result.report.summary.denied).toBeGreaterThan(0);
    expect(result.output).toContain("DENIED");
  });

  test("supports JSON output format", async () => {
    const result = await runCli({
      manifestPath: "fixtures/package-approved.json",
      policyPath: "fixtures/license-policy.json",
      licenseDbPath: "fixtures/license-db.json",
      format: "json",
    });

    expect(() => JSON.parse(result.output)).not.toThrow();
  });

  test("throws a meaningful error when the manifest file is missing", async () => {
    await expect(
      runCli({
        manifestPath: "fixtures/does-not-exist.json",
        policyPath: "fixtures/license-policy.json",
        licenseDbPath: "fixtures/license-db.json",
      })
    ).rejects.toThrow(/manifest/i);
  });
});
