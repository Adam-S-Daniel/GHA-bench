import { describe, expect, test } from "bun:test";
import { mkdtempSync, writeFileSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { parseFileList } from "../src/cli.ts";

// ---------------------------------------------------------------------------
// The CLI reads a "changed files" fixture that may be supplied either as a JSON
// array or as a newline-separated list. parseFileList normalizes both.
// ---------------------------------------------------------------------------
describe("parseFileList", () => {
  test("parses a JSON array of paths", () => {
    expect(parseFileList('["docs/a.md", "src/api/x.ts"]')).toEqual([
      "docs/a.md",
      "src/api/x.ts",
    ]);
  });

  test("parses a newline-separated list, ignoring blanks and # comments", () => {
    const raw = "# changed files\ndocs/a.md\n\n  src/api/x.ts  \n# trailing\n";
    expect(parseFileList(raw)).toEqual(["docs/a.md", "src/api/x.ts"]);
  });

  test("returns an empty array for empty content", () => {
    expect(parseFileList("   \n  ")).toEqual([]);
  });

  test("throws on a JSON value that is not an array of strings", () => {
    expect(() => parseFileList("[1, 2, 3]")).toThrow(/string/i);
  });
});

// ---------------------------------------------------------------------------
// End-to-end CLI behavior, exercised the way the workflow does: spawn the real
// `bun run src/cli.ts` process with fixture files and assert on stdout / exit.
// ---------------------------------------------------------------------------
const CLI = new URL("../src/cli.ts", import.meta.url).pathname;

function makeFixtures(config: unknown, files: unknown): { dir: string; cfg: string; lst: string } {
  const dir = mkdtempSync(join(tmpdir(), "pr-label-cli-"));
  const cfg = join(dir, "labeler.config.json");
  const lst = join(dir, "changed-files.json");
  writeFileSync(cfg, JSON.stringify(config));
  writeFileSync(lst, JSON.stringify(files));
  return { dir, cfg, lst };
}

const CONFIG = {
  rules: [
    { label: "documentation", patterns: ["docs/**", "*.md"], priority: 1 },
    { label: "api", patterns: ["src/api/**"], priority: 10 },
    { label: "tests", patterns: ["*.test.*"], priority: 5 },
  ],
};

describe("cli end-to-end", () => {
  test("prints the machine-readable label line in priority order", async () => {
    const { cfg, lst } = makeFixtures(CONFIG, [
      "docs/intro.md",
      "src/api/users.ts",
      "src/api/users.test.ts",
    ]);
    const proc = Bun.spawn(["bun", "run", CLI, "--config", cfg, "--files", lst]);
    const stdout = await new Response(proc.stdout).text();
    const exitCode = await proc.exited;

    expect(exitCode).toBe(0);
    // api(10), tests(5), documentation(1)
    expect(stdout).toContain("__PR_LABELS__=api,tests,documentation");
  });

  test("emits an empty label line when nothing matches", async () => {
    const { cfg, lst } = makeFixtures(CONFIG, ["LICENSE", "src/web/app.ts"]);
    const proc = Bun.spawn(["bun", "run", CLI, "--config", cfg, "--files", lst]);
    const stdout = await new Response(proc.stdout).text();
    expect(await proc.exited).toBe(0);
    expect(stdout).toContain("__PR_LABELS__=\n");
  });

  test("--format json emits the structured result", async () => {
    const { cfg, lst } = makeFixtures(CONFIG, ["src/api/users.ts"]);
    const proc = Bun.spawn([
      "bun", "run", CLI, "--config", cfg, "--files", lst, "--format", "json",
    ]);
    const stdout = await new Response(proc.stdout).text();
    expect(await proc.exited).toBe(0);
    // The JSON object appears after the machine line; extract and parse it.
    const jsonStart = stdout.indexOf("{");
    const parsed = JSON.parse(stdout.slice(jsonStart));
    expect(parsed.labels).toEqual(["api"]);
    expect(parsed.matches.api).toEqual(["src/api/users.ts"]);
  });

  test("writes labels to GITHUB_OUTPUT when the env var is set", async () => {
    const { dir, cfg, lst } = makeFixtures(CONFIG, ["docs/x.md"]);
    const outFile = join(dir, "gh_output");
    writeFileSync(outFile, "");
    const proc = Bun.spawn(["bun", "run", CLI, "--config", cfg, "--files", lst], {
      env: { ...process.env, GITHUB_OUTPUT: outFile },
    });
    await proc.exited;
    const written = readFileSync(outFile, "utf8");
    expect(written).toContain("labels=documentation");
    expect(written).toContain("count=1");
  });

  test("exits non-zero with a friendly message when the config is missing", async () => {
    const { lst } = makeFixtures(CONFIG, ["docs/x.md"]);
    const proc = Bun.spawn(
      ["bun", "run", CLI, "--config", "/no/such/config.json", "--files", lst],
      { stderr: "pipe" },
    );
    const stderr = await new Response(proc.stderr).text();
    const exitCode = await proc.exited;
    expect(exitCode).toBe(1);
    expect(stderr).toMatch(/Error:.*config/i);
  });

  test("exits non-zero with a friendly message on invalid config JSON", async () => {
    const dir = mkdtempSync(join(tmpdir(), "pr-label-cli-"));
    const cfg = join(dir, "bad.json");
    const lst = join(dir, "files.json");
    writeFileSync(cfg, "{ this is not json ");
    writeFileSync(lst, JSON.stringify(["docs/x.md"]));
    const proc = Bun.spawn(["bun", "run", CLI, "--config", cfg, "--files", lst], {
      stderr: "pipe",
    });
    const stderr = await new Response(proc.stderr).text();
    expect(await proc.exited).toBe(1);
    expect(stderr).toMatch(/Error:/);
  });
});
