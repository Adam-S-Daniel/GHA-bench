import { afterAll, describe, expect, test } from "bun:test";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { runCli } from "../src/cli.ts";

// Create an isolated temp dir holding fixture-like files, so the CLI's
// real file-reading path is exercised (no mocking of the filesystem).
function makeFixtureDir(): string {
  const dir = mkdtempSync(join(tmpdir(), "tra-"));
  writeFileSync(
    join(dir, "run1.xml"),
    `<testsuite name="S">
       <testcase name="flaky" classname="S" time="1"/>
       <testcase name="stable" classname="S" time="0.5"/>
     </testsuite>`,
  );
  writeFileSync(
    join(dir, "run2.json"),
    JSON.stringify({
      tests: [
        { name: "flaky", suite: "S", status: "failed", duration: 1, message: "boom" },
        { name: "stable", suite: "S", status: "passed", duration: 0.5 },
      ],
    }),
  );
  return dir;
}

const dirs: string[] = [];
afterAll(() => dirs.forEach((d) => rmSync(d, { recursive: true, force: true })));

describe("runCli", () => {
  test("aggregates real files and returns markdown + a nonzero exit when tests failed", async () => {
    const dir = makeFixtureDir();
    dirs.push(dir);
    const { markdown, exitCode, aggregation } = await runCli([
      join(dir, "run1.xml"),
      join(dir, "run2.json"),
    ]);

    expect(aggregation.totals.total).toBe(4);
    expect(aggregation.totals.failed).toBe(1);
    expect(aggregation.flaky).toHaveLength(1);
    expect(aggregation.flaky[0].name).toBe("flaky");
    expect(markdown).toContain("# Test Results Summary");
    // one test failed -> nonzero exit so CI can fail the job
    expect(exitCode).toBe(1);
  });

  test("returns exit code 0 when everything passed", async () => {
    const dir = mkdtempSync(join(tmpdir(), "tra-"));
    dirs.push(dir);
    writeFileSync(
      join(dir, "ok.json"),
      JSON.stringify({ tests: [{ name: "t", suite: "S", status: "passed", duration: 1 }] }),
    );
    const { exitCode } = await runCli([join(dir, "ok.json")]);
    expect(exitCode).toBe(0);
  });

  test("writes the summary to the file named by an env GITHUB_STEP_SUMMARY", async () => {
    const dir = mkdtempSync(join(tmpdir(), "tra-"));
    dirs.push(dir);
    writeFileSync(
      join(dir, "ok.json"),
      JSON.stringify({ tests: [{ name: "t", status: "passed", duration: 1 }] }),
    );
    const summaryPath = join(dir, "summary.md");
    await runCli([join(dir, "ok.json")], { summaryFile: summaryPath });
    const written = await Bun.file(summaryPath).text();
    expect(written).toContain("# Test Results Summary");
  });

  test("throws a meaningful error when given no input files", async () => {
    await expect(runCli([])).rejects.toThrow(/no input files/i);
  });

  test("throws a meaningful error when a file does not exist", async () => {
    await expect(runCli(["/nonexistent/path/results.xml"])).rejects.toThrow(/could not read/i);
  });
});
