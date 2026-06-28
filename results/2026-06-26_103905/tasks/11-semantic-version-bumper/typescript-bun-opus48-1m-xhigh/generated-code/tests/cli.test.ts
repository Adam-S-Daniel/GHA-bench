// RED phase for the command-line interface.
//
// The CLI is kept thin and testable: parseArgs() turns argv into options, and
// runCli() executes a bump and returns structured stdout/stderr/exit-code
// instead of writing to the console directly. It also emits GitHub Actions
// step outputs to $GITHUB_OUTPUT when that env var is set.
import { afterEach, beforeEach, describe, expect, it } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { parseArgs, runCli } from "../src/index.ts";

let dir: string;
beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), "svb-cli-"));
});
afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
});

describe("parseArgs", () => {
  it("parses long flags and applies defaults", () => {
    const opts = parseArgs(
      ["--version-file", "VERSION", "--commits", "commits.txt"],
      "2026-06-27",
    );
    expect(opts.versionFilePath).toBe("VERSION");
    expect(opts.commitsPath).toBe("commits.txt");
    expect(opts.changelogPath).toBe("CHANGELOG.md");
    expect(opts.date).toBe("2026-06-27");
    expect(opts.dryRun).toBe(false);
  });

  it("supports short flags, an explicit date, and --dry-run", () => {
    const opts = parseArgs(
      ["-f", "v.txt", "-c", "c.txt", "--date", "2020-01-01", "--dry-run"],
      "2026-06-27",
    );
    expect(opts.versionFilePath).toBe("v.txt");
    expect(opts.commitsPath).toBe("c.txt");
    expect(opts.date).toBe("2020-01-01");
    expect(opts.dryRun).toBe(true);
  });

  it("flags an unknown option", () => {
    expect(() => parseArgs(["--bogus"], "2026-06-27")).toThrow(/unknown option/i);
  });
});

describe("runCli", () => {
  it("prints machine-readable results and writes GITHUB_OUTPUT", async () => {
    const versionPath = join(dir, "VERSION");
    const commitsPath = join(dir, "commits.txt");
    const changelogPath = join(dir, "CHANGELOG.md");
    const ghOutput = join(dir, "gh_output");
    writeFileSync(versionPath, "1.1.0\n");
    writeFileSync(commitsPath, "feat: shiny new feature");

    const run = await runCli(
      [
        "--version-file", versionPath,
        "--commits", commitsPath,
        "--changelog", changelogPath,
        "--date", "2026-06-27",
      ],
      { GITHUB_OUTPUT: ghOutput },
    );

    expect(run.exitCode).toBe(0);
    const out = run.stdout.join("\n");
    expect(out).toContain("PREVIOUS_VERSION=1.1.0");
    expect(out).toContain("NEW_VERSION=1.2.0");
    expect(out).toContain("BUMP_TYPE=minor");
    expect(out).toContain("CHANGED=true");

    // GitHub Actions step outputs were written in key=value form.
    const gh = readFileSync(ghOutput, "utf8");
    expect(gh).toContain("new-version=1.2.0");
    expect(gh).toContain("bump-type=minor");
    expect(gh).toContain("changed=true");
  });

  it("reports a 'none' bump with exit code 0 and CHANGED=false", async () => {
    const versionPath = join(dir, "VERSION");
    const commitsPath = join(dir, "commits.txt");
    writeFileSync(versionPath, "1.0.0\n");
    writeFileSync(commitsPath, "chore: nothing to release");

    const run = await runCli(
      ["--version-file", versionPath, "--commits", commitsPath, "--date", "2026-06-27"],
      {},
    );
    expect(run.exitCode).toBe(0);
    expect(run.stdout.join("\n")).toContain("NEW_VERSION=1.0.0");
    expect(run.stdout.join("\n")).toContain("CHANGED=false");
  });

  it("exits non-zero with a clear message when required args are missing", async () => {
    const run = await runCli(["--commits", "c.txt"], {});
    expect(run.exitCode).not.toBe(0);
    expect(run.stderr.join("\n")).toMatch(/--version-file/);
  });

  it("exits non-zero with the underlying error when a file is missing", async () => {
    const run = await runCli(
      ["--version-file", join(dir, "nope"), "--commits", join(dir, "nope2"), "--date", "2026-06-27"],
      {},
    );
    expect(run.exitCode).toBe(1);
    expect(run.stderr.join("\n")).toMatch(/not found/i);
  });

  it("prints usage for --help and exits 0", async () => {
    const run = await runCli(["--help"], {});
    expect(run.exitCode).toBe(0);
    expect(run.stdout.join("\n")).toMatch(/usage/i);
  });
});
