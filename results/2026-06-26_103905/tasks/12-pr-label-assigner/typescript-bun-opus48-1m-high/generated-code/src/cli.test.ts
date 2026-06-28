import { describe, expect, test } from "bun:test";
import { mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

// The CLI is what the GitHub Actions workflow invokes. We test it by spawning
// a real `bun run src/cli.ts` subprocess against temp fixture files, asserting
// on its exit code and parseable stdout.
const CLI = join(import.meta.dir, "cli.ts");

async function runCli(
  args: string[],
  stdin?: string,
): Promise<{ code: number; stdout: string; stderr: string }> {
  const proc = Bun.spawn(["bun", "run", CLI, ...args], {
    stdin: stdin === undefined ? "ignore" : new TextEncoder().encode(stdin),
    stdout: "pipe",
    stderr: "pipe",
  });
  const [stdout, stderr] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
  ]);
  const code = await proc.exited;
  return { code, stdout, stderr };
}

const CONFIG = JSON.stringify({
  rules: [
    { pattern: "docs/**", label: "documentation", priority: 1 },
    { pattern: "src/api/**", label: "api", priority: 10 },
    { pattern: "*.test.*", label: "tests", priority: 5 },
    { pattern: "**/*.ts", label: "code", priority: 0 },
  ],
});

describe("cli", () => {
  test("emits a machine-parseable LABELS line and exits 0", async () => {
    const dir = await mkdtemp(join(tmpdir(), "lblcli-"));
    const cfg = join(dir, "config.json");
    const files = join(dir, "files.txt");
    await writeFile(cfg, CONFIG);
    await writeFile(files, "src/api/users.test.ts\ndocs/intro.md\n");

    const { code, stdout } = await runCli(["--config", cfg, "--files", files]);
    expect(code).toBe(0);
    // Ordering: api(10) > tests(5) > documentation(1) > code(0)
    expect(stdout).toContain("LABELS=api,tests,documentation,code");
  });

  test("emits LABELS= (empty) when nothing matches and still exits 0", async () => {
    const dir = await mkdtemp(join(tmpdir(), "lblcli-"));
    const cfg = join(dir, "config.json");
    const files = join(dir, "files.txt");
    await writeFile(cfg, JSON.stringify({ rules: [{ pattern: "docs/**", label: "documentation" }] }));
    await writeFile(files, "Makefile\n");

    const { code, stdout } = await runCli(["--config", cfg, "--files", files]);
    expect(code).toBe(0);
    expect(stdout).toContain("LABELS=\n");
  });

  test("reads the changed-file list from stdin when --files is omitted", async () => {
    const dir = await mkdtemp(join(tmpdir(), "lblcli-"));
    const cfg = join(dir, "config.json");
    await writeFile(cfg, CONFIG);

    const { code, stdout } = await runCli(
      ["--config", cfg],
      "docs/a.md\nsrc/api/b.ts\n",
    );
    expect(code).toBe(0);
    expect(stdout).toContain("LABELS=api,documentation,code");
  });

  test("exits non-zero with a clear error when the config file is missing", async () => {
    const { code, stderr } = await runCli(["--config", "/no/such/config.json"]);
    expect(code).not.toBe(0);
    expect(stderr).toMatch(/config/i);
  });
});
