// TDD step 5 (RED): the CLI wrapper that the GitHub Actions workflow invokes.
import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

let dir: string;
const CLI = join(import.meta.dir, "..", "src", "cli.ts");

beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), "svb-cli-"));
});
afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
});

async function run(args: string[]): Promise<{ code: number; stdout: string; stderr: string }> {
  const proc = Bun.spawn(["bun", "run", CLI, ...args], { stdout: "pipe", stderr: "pipe" });
  const stdout = await new Response(proc.stdout).text();
  const stderr = await new Response(proc.stderr).text();
  const code = await proc.exited;
  return { code, stdout, stderr };
}

describe("cli", () => {
  test("prints the bumped version with stable KEY=VALUE lines", async () => {
    const versionFile = join(dir, "package.json");
    const commitsFile = join(dir, "commits.txt");
    const changelogFile = join(dir, "CHANGELOG.md");
    writeFileSync(versionFile, JSON.stringify({ name: "demo", version: "1.1.0" }, null, 2));
    writeFileSync(commitsFile, "feat: add pagination\nfix: bug\n");

    const { code, stdout } = await run([
      "--version-file", versionFile,
      "--commits-file", commitsFile,
      "--changelog", changelogFile,
      "--date", "2026-06-26",
    ]);

    expect(code).toBe(0);
    expect(stdout).toContain("PREVIOUS_VERSION=1.1.0");
    expect(stdout).toContain("NEW_VERSION=1.2.0");
    expect(stdout).toContain("BUMP=minor");
    expect(JSON.parse(readFileSync(versionFile, "utf8")).version).toBe("1.2.0");
  });

  test("exits non-zero with a clear error when the version file is missing", async () => {
    const { code, stderr } = await run([
      "--version-file", join(dir, "missing.json"),
      "--commits-file", join(dir, "c.txt"),
      "--changelog", join(dir, "CHANGELOG.md"),
    ]);
    expect(code).not.toBe(0);
    expect(stderr.toLowerCase()).toContain("not found");
  });

  test("reports BUMP=none when no release is warranted", async () => {
    const versionFile = join(dir, "VERSION");
    const commitsFile = join(dir, "commits.txt");
    writeFileSync(versionFile, "2.0.0\n");
    writeFileSync(commitsFile, "chore: nothing\n");
    const { code, stdout } = await run([
      "--version-file", versionFile,
      "--commits-file", commitsFile,
      "--changelog", join(dir, "CHANGELOG.md"),
    ]);
    expect(code).toBe(0);
    expect(stdout).toContain("NEW_VERSION=2.0.0");
    expect(stdout).toContain("BUMP=none");
  });
});
