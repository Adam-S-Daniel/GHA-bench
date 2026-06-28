/**
 * Tests for the CLI orchestration layer.
 *
 * runCli() parses argv, reads the manifest / policy / database files, builds
 * the report, and returns { output, exitCode } WITHOUT touching process.exit so
 * it stays unit-testable. Exit codes:
 *   0 -> compliant, 1 -> non-compliant, 2 -> usage / IO / parse error.
 *
 * Fixtures live under tests/fixtures/ and are shared with the act harness.
 */
import { describe, expect, it } from "bun:test";
import { join } from "node:path";
import { runCli } from "../src/cli.ts";

const FIX = join(import.meta.dir, "fixtures");

describe("runCli", () => {
  it("reports FAIL and exits 1 when a denied license is present", async () => {
    const { output, exitCode } = await runCli([
      "--manifest",
      join(FIX, "package.json"),
      "--policy",
      join(FIX, "policy.json"),
      "--database",
      join(FIX, "licenses.json"),
    ]);

    expect(output).toContain("left-pad@1.3.0");
    expect(output).toContain("APPROVED");
    expect(output).toContain("evil-pkg@2.0.0");
    expect(output).toContain("DENIED");
    expect(output).toContain("mystery@0.0.1");
    expect(output).toContain("UNKNOWN");
    expect(output).toContain("Summary: 1 approved, 1 denied, 1 unknown (3 total)");
    expect(output).toContain("RESULT: FAIL");
    expect(exitCode).toBe(1);
  });

  it("reports PASS and exits 0 for a fully-approved manifest", async () => {
    const { output, exitCode } = await runCli([
      "--manifest",
      join(FIX, "clean.package.json"),
      "--policy",
      join(FIX, "policy.json"),
      "--database",
      join(FIX, "licenses.json"),
    ]);
    expect(output).toContain("RESULT: PASS");
    expect(exitCode).toBe(0);
  });

  it("supports --format json", async () => {
    const { output, exitCode } = await runCli([
      "--manifest",
      join(FIX, "clean.package.json"),
      "--policy",
      join(FIX, "policy.json"),
      "--database",
      join(FIX, "licenses.json"),
      "--format",
      "json",
    ]);
    const parsed = JSON.parse(output);
    expect(parsed.summary.approved).toBe(1);
    expect(parsed.compliant).toBe(true);
    expect(exitCode).toBe(0);
  });

  it("exits 2 with a meaningful message when a file is missing", async () => {
    const { output, exitCode } = await runCli([
      "--manifest",
      join(FIX, "does-not-exist.json"),
      "--policy",
      join(FIX, "policy.json"),
      "--database",
      join(FIX, "licenses.json"),
    ]);
    expect(exitCode).toBe(2);
    expect(output).toMatch(/Error:.*manifest/i);
  });

  it("exits 2 with usage when a required flag is missing", async () => {
    const { output, exitCode } = await runCli(["--policy", join(FIX, "policy.json")]);
    expect(exitCode).toBe(2);
    expect(output).toMatch(/Usage:/);
  });
});
