import { afterAll, describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { runCli } from "../src/cli.ts";

// Each CLI run gets its own temp dir holding fixture files.
const dirs: string[] = [];
function fixtureDir(files: Record<string, string>): string {
  const dir = mkdtempSync(join(tmpdir(), "dlc-"));
  dirs.push(dir);
  for (const [name, content] of Object.entries(files)) {
    writeFileSync(join(dir, name), content);
  }
  return dir;
}

afterAll(() => {
  for (const d of dirs) rmSync(d, { recursive: true, force: true });
});

const config = JSON.stringify({
  allow: ["MIT", "Apache-2.0"],
  deny: ["GPL-3.0"],
});

describe("runCli", () => {
  test("exits 0 and reports COMPLIANT when all licenses are approved", () => {
    const dir = fixtureDir({
      "package.json": JSON.stringify({ dependencies: { lodash: "4.17.21" } }),
      "config.json": config,
      "db.json": JSON.stringify({ lodash: "MIT" }),
    });

    const out: string[] = [];
    const code = runCli(
      [
        "--manifest", join(dir, "package.json"),
        "--config", join(dir, "config.json"),
        "--db", join(dir, "db.json"),
      ],
      (line) => out.push(line),
    );

    const text = out.join("\n");
    expect(code).toBe(0);
    expect(text).toContain("lodash@4.17.21");
    expect(text).toContain("APPROVED");
    expect(text).toContain("COMPLIANT");
    expect(text).not.toContain("NOT COMPLIANT");
  });

  test("exits 1 and reports NOT COMPLIANT when a license is denied", () => {
    const dir = fixtureDir({
      "package.json": JSON.stringify({ dependencies: { "evil-lib": "1.0.0" } }),
      "config.json": config,
      "db.json": JSON.stringify({ "evil-lib": "GPL-3.0" }),
    });

    const out: string[] = [];
    const code = runCli(
      [
        "--manifest", join(dir, "package.json"),
        "--config", join(dir, "config.json"),
        "--db", join(dir, "db.json"),
        "--format", "json",
      ],
      (line) => out.push(line),
    );

    expect(code).toBe(1);
    const report = JSON.parse(out.join("\n"));
    expect(report.summary.denied).toBe(1);
    expect(report.summary.compliant).toBe(false);
  });

  test("throws a meaningful error when the manifest file is missing", () => {
    const dir = fixtureDir({ "config.json": config, "db.json": "{}" });
    expect(() =>
      runCli(
        [
          "--manifest", join(dir, "does-not-exist.json"),
          "--config", join(dir, "config.json"),
          "--db", join(dir, "db.json"),
        ],
        () => {},
      ),
    ).toThrow(/Cannot read manifest/);
  });

  test("throws when a required argument is missing", () => {
    expect(() => runCli(["--config", "x"], () => {})).toThrow(
      /Missing required argument: --manifest/,
    );
  });
});
