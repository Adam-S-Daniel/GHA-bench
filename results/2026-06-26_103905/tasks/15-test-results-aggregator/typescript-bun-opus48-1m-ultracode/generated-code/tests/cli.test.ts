/**
 * Tests for the CLI layer: argument parsing, input-file discovery (including
 * directory expansion), the machine-readable summary line, and end-to-end
 * behaviour invoked as a subprocess (the same way the GitHub Actions workflow
 * invokes it).
 */
import { afterAll, describe, expect, test } from "bun:test";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { aggregate } from "../src/aggregate";
import {
  collectInputFiles,
  formatSummaryLine,
  loadRuns,
  parseArgs,
} from "../src/cli";

const cleanups: string[] = [];
afterAll(async () => {
  await Promise.all(cleanups.map((d) => rm(d, { recursive: true, force: true })));
});

async function makeTempDir(): Promise<string> {
  const dir = await mkdtemp(join(tmpdir(), "agg-cli-"));
  cleanups.push(dir);
  return dir;
}

describe("parseArgs", () => {
  test("collects positional paths and recognises flags", () => {
    const opts = parseArgs(["fixtures/sample", "--fail-on-failure", "--json"]);
    expect(opts.paths).toEqual(["fixtures/sample"]);
    expect(opts.failOnFailure).toBe(true);
    expect(opts.json).toBe(true);
    expect(opts.help).toBe(false);
  });

  test("defaults flags to false and detects --help", () => {
    const opts = parseArgs(["--help"]);
    expect(opts.help).toBe(true);
    expect(opts.failOnFailure).toBe(false);
    expect(opts.paths).toEqual([]);
  });

  test("rejects unknown flags", () => {
    expect(() => parseArgs(["--bogus"])).toThrow(/--bogus/);
  });
});

describe("collectInputFiles", () => {
  test("expands a directory to its .json and .xml files, sorted, ignoring others", async () => {
    const dir = await makeTempDir();
    await writeFile(join(dir, "b.json"), "{}");
    await writeFile(join(dir, "a.xml"), "<x/>");
    await writeFile(join(dir, "notes.txt"), "ignore me");
    await writeFile(join(dir, "README.md"), "ignore me");

    const files = await collectInputFiles([dir]);
    expect(files).toEqual([join(dir, "a.xml"), join(dir, "b.json")]);
  });

  test("passes explicit file paths through unchanged", async () => {
    const dir = await makeTempDir();
    const f = join(dir, "one.json");
    await writeFile(f, "{}");
    expect(await collectInputFiles([f])).toEqual([f]);
  });

  test("throws a clear error for a path that does not exist", async () => {
    await expect(collectInputFiles(["/no/such/path-xyz"]).then(() => "ok")).rejects.toThrow(
      /no\/such\/path-xyz/,
    );
  });
});

describe("loadRuns", () => {
  test("reads and parses each file by extension", async () => {
    const dir = await makeTempDir();
    const j = join(dir, "r.json");
    const x = join(dir, "r.xml");
    await writeFile(j, JSON.stringify({ tests: [{ name: "a", status: "passed" }] }));
    await writeFile(x, '<testsuite name="S"><testcase name="b" classname="S"/></testsuite>');

    const runs = await loadRuns([j, x]);
    expect(runs).toHaveLength(2);
    expect(runs[0]?.cases[0]?.name).toBe("a");
    expect(runs[1]?.cases[0]?.name).toBe("b");
  });
});

describe("formatSummaryLine", () => {
  test("emits a stable machine-readable key=value line", () => {
    const result = aggregate([
      {
        source: "x.json",
        name: "x",
        cases: [
          { suite: "S", name: "a", status: "passed", durationSeconds: 0.5 },
          { suite: "S", name: "b", status: "failed", durationSeconds: 0.25 },
        ],
      },
    ]);
    expect(formatSummaryLine(result)).toBe(
      "AGGREGATE status=FAILED passed=1 failed=1 skipped=0 total=2 duration=0.750s flaky=0 runs=1",
    );
  });
});

describe("CLI subprocess (end-to-end)", () => {
  const cli = join(import.meta.dir, "..", "src", "cli.ts");

  // This test builds its OWN fixture data in a temp dir rather than relying on
  // the repo's fixtures/sample. That keeps it independent of the act harness,
  // which swaps fixtures/sample for different scenarios per test case.
  test("aggregates a mixed matrix, detects flaky tests, and writes the summary", async () => {
    const dir = await makeTempDir();
    const fixtures = join(dir, "fixtures");
    await writeFile(
      join(fixtures + "-a.json"),
      JSON.stringify({
        name: "leg-a",
        tests: [
          { suite: "S", name: "t1", status: "passed", duration: 0.5 },
          { suite: "S", name: "t2", status: "failed", duration: 0.25 },
        ],
      }),
    );
    await writeFile(
      join(fixtures + "-b.xml"),
      '<testsuite name="leg-b">' +
        '<testcase name="t1" classname="S" time="0.1"/>' +
        '<testcase name="t2" classname="S" time="0.2"/>' +
        "</testsuite>",
    );

    const summaryPath = join(dir, "summary.md");
    const outputPath = join(dir, "output.txt");

    const proc = Bun.spawn(
      ["bun", "run", cli, fixtures + "-a.json", fixtures + "-b.xml"],
      {
        env: {
          ...process.env,
          GITHUB_STEP_SUMMARY: summaryPath,
          GITHUB_OUTPUT: outputPath,
        },
        stdout: "pipe",
        stderr: "pipe",
      },
    );
    const stdout = await new Response(proc.stdout).text();
    const exitCode = await proc.exited;

    // Reporter mode: exits 0 even though the matrix has a failure.
    expect(exitCode).toBe(0);
    // t1 passes in both legs; t2 fails in a, passes in b => 1 flaky test.
    // 3 passed, 1 failed, 0 skipped, 4 total, 1.050s.
    expect(stdout).toContain(
      "AGGREGATE status=FAILED passed=3 failed=1 skipped=0 total=4 duration=1.050s flaky=1 runs=2",
    );
    expect(stdout).toContain("S::t2");

    // The job summary file was written with the markdown report.
    const summary = await Bun.file(summaryPath).text();
    expect(summary).toContain("## Test Results Summary");
    expect(summary).toContain("| Total | 4 |");

    // GitHub outputs were emitted for downstream steps.
    const outputs = await Bun.file(outputPath).text();
    expect(outputs).toContain("failed=1");
    expect(outputs).toContain("flaky=1");
  });

  test("exits non-zero with --fail-on-failure when there are failures", async () => {
    // Self-contained: write a failing result file to a temp dir so this test
    // does not depend on the repo's fixtures/sample (which the act harness
    // swaps for all-passing data in its "all-green" scenario).
    const dir = await makeTempDir();
    const file = join(dir, "failing.json");
    await writeFile(
      file,
      JSON.stringify({ tests: [{ name: "boom", status: "failed", duration: 0.1 }] }),
    );
    const proc = Bun.spawn(["bun", "run", cli, file, "--fail-on-failure"], {
      env: { ...process.env, GITHUB_STEP_SUMMARY: "", GITHUB_OUTPUT: "" },
      stdout: "pipe",
      stderr: "pipe",
    });
    await new Response(proc.stdout).text();
    expect(await proc.exited).toBe(1);
  });

  test("errors with a non-zero exit when no result files are found", async () => {
    const dir = await makeTempDir();
    const proc = Bun.spawn(["bun", "run", cli, dir], {
      env: { ...process.env, GITHUB_STEP_SUMMARY: "", GITHUB_OUTPUT: "" },
      stdout: "pipe",
      stderr: "pipe",
    });
    const stderr = await new Response(proc.stderr).text();
    expect(await proc.exited).toBe(2);
    expect(stderr).toContain("no");
  });
});
