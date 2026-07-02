// TDD cycle 4b (RED): the CLI end-to-end, run as a real subprocess against a
// temp directory seeded with a version file and a mock commit-log fixture.
import { describe, expect, test } from "bun:test";
import { mkdtempSync, readFileSync, writeFileSync, copyFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const CLI = new URL("../src/cli.ts", import.meta.url).pathname;
const FIXTURES = new URL("../fixtures/", import.meta.url).pathname;

interface CliRun {
  exitCode: number;
  stdout: string;
  stderr: string;
}

/** Seed a temp dir with a version file + fixture log, then run the CLI in it. */
async function runCli(fixture: string, versionJson: object): Promise<CliRun & { dir: string }> {
  const dir = mkdtempSync(join(tmpdir(), "svb-cli-"));
  writeFileSync(join(dir, "package.json"), JSON.stringify(versionJson, null, 2) + "\n");
  copyFileSync(join(FIXTURES, fixture), join(dir, "commits.txt"));

  const proc = Bun.spawn(
    ["bun", "run", CLI, "--version-file", "package.json", "--commits", "commits.txt", "--changelog", "CHANGELOG.md", "--date", "2026-07-01"],
    { cwd: dir, stdout: "pipe", stderr: "pipe" },
  );
  const [stdout, stderr, exitCode] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
    proc.exited,
  ]);
  return { dir, exitCode, stdout, stderr };
}

const pkg = { name: "demo", version: "1.2.3" };

describe("cli", () => {
  test("feat commits: bumps minor, updates file, writes changelog, prints version", async () => {
    const r = await runCli("commits-feat.txt", pkg);
    expect(r.exitCode).toBe(0);
    expect(r.stdout.trim().split("\n").pop()).toBe("1.3.0");
    expect(JSON.parse(readFileSync(join(r.dir, "package.json"), "utf8")).version).toBe("1.3.0");
    const changelog = readFileSync(join(r.dir, "CHANGELOG.md"), "utf8");
    expect(changelog).toContain("## 1.3.0 (2026-07-01)");
    expect(changelog).toContain("- **auth**: add OAuth2 login flow");
  });

  test("fix commits: bumps patch", async () => {
    const r = await runCli("commits-fix.txt", pkg);
    expect(r.exitCode).toBe(0);
    expect(r.stdout.trim().split("\n").pop()).toBe("1.2.4");
  });

  test("breaking commits: bumps major", async () => {
    const r = await runCli("commits-breaking.txt", pkg);
    expect(r.exitCode).toBe(0);
    expect(r.stdout.trim().split("\n").pop()).toBe("2.0.0");
  });

  test("no releasable commits: exits 0, keeps version, reports 'no bump'", async () => {
    const r = await runCli("commits-none.txt", pkg);
    expect(r.exitCode).toBe(0);
    expect(r.stdout).toContain("no version bump");
    expect(JSON.parse(readFileSync(join(r.dir, "package.json"), "utf8")).version).toBe("1.2.3");
  });

  test("invalid current version: exits 1 with a meaningful error", async () => {
    const r = await runCli("commits-feat.txt", { name: "demo", version: "banana" });
    expect(r.exitCode).toBe(1);
    expect(r.stderr).toContain('Invalid semantic version: "banana"');
  });
});
