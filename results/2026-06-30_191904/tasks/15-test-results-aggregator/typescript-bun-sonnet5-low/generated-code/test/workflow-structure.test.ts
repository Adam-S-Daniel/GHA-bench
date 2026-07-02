import { describe, it, expect } from "bun:test";
import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import * as yaml from "js-yaml";

const execFileAsync = promisify(execFile);
const WORKFLOW_PATH = ".github/workflows/test-results-aggregator.yml";

describe("GitHub Actions workflow structure", () => {
  it("is valid YAML with expected triggers and jobs", async () => {
    const contents = await readFile(WORKFLOW_PATH, "utf-8");
    const parsed = yaml.load(contents) as any;

    // YAML parses the bare `on:` key as boolean `true` under js-yaml's default schema.
    const triggers = parsed.on ?? parsed[true];
    expect(triggers).toHaveProperty("push");
    expect(triggers).toHaveProperty("pull_request");
    expect(triggers).toHaveProperty("workflow_dispatch");
    expect(triggers).toHaveProperty("schedule");

    expect(parsed.jobs).toHaveProperty("unit-tests");
    expect(parsed.jobs).toHaveProperty("aggregate-results");
    expect(parsed.jobs["aggregate-results"].needs).toBe("unit-tests");
    expect(parsed.permissions.contents).toBe("read");
  });

  it("references script files that exist on disk", () => {
    expect(existsSync("src/index.ts")).toBe(true);
    expect(existsSync("src/junit-parser.ts")).toBe(true);
    expect(existsSync("src/json-parser.ts")).toBe(true);
    expect(existsSync("src/aggregator.ts")).toBe(true);
    expect(existsSync("src/markdown-report.ts")).toBe(true);
  });

  it("passes actionlint validation", async () => {
    const result = await execFileAsync("actionlint", [WORKFLOW_PATH]);
    expect(result.stdout).toBe("");
  });
});
