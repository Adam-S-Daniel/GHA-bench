// TDD: tests for CLI argument parsing and the run() orchestrator.
// run() is pure-ish: it takes argv + a file reader and returns
// { stdout, exitCode } so we can assert without touching the real FS.
import { describe, expect, test } from "bun:test";
import { parseArgs, run } from "../src/cli";

const FIXTURE = JSON.stringify([
  { name: "ok-secret", lastRotated: "2026-06-01", rotationPolicyDays: 90, requiredBy: ["api"] },
  { name: "warn-secret", lastRotated: "2026-04-08", rotationPolicyDays: 90, requiredBy: ["api"] },
  { name: "expired-secret", lastRotated: "2026-01-01", rotationPolicyDays: 90, requiredBy: ["billing"] },
]);

// Stub reader keyed on path.
function reader(map: Record<string, string>) {
  return (path: string) => {
    if (!(path in map)) throw new Error(`ENOENT: ${path}`);
    return map[path]!;
  };
}

describe("parseArgs", () => {
  test("parses all known flags", () => {
    const opts = parseArgs([
      "--input", "secrets.json",
      "--warning", "30",
      "--format", "json",
      "--now", "2026-06-27",
      "--fail-on-expired",
    ]);
    expect(opts.input).toBe("secrets.json");
    expect(opts.warningWindowDays).toBe(30);
    expect(opts.format).toBe("json");
    expect(opts.now).toBe("2026-06-27");
    expect(opts.failOnExpired).toBe(true);
  });

  test("applies sensible defaults", () => {
    const opts = parseArgs(["--input", "s.json"]);
    expect(opts.format).toBe("markdown");
    expect(opts.warningWindowDays).toBe(14);
    expect(opts.failOnExpired).toBe(false);
  });

  test("rejects an unknown format", () => {
    expect(() => parseArgs(["--input", "s.json", "--format", "yaml"])).toThrow(/format/i);
  });

  test("rejects a non-numeric warning window", () => {
    expect(() => parseArgs(["--input", "s.json", "--warning", "abc"])).toThrow(/warning/i);
  });
});

describe("run", () => {
  test("emits markdown by default and exits 0", () => {
    const res = run(
      ["--input", "secrets.json", "--now", "2026-06-27"],
      reader({ "secrets.json": FIXTURE }),
    );
    expect(res.exitCode).toBe(0);
    expect(res.stdout).toContain("# Secret Rotation Report");
    expect(res.stdout).toContain("**Expired:** 1");
  });

  test("emits JSON when requested with exact summary counts", () => {
    const res = run(
      ["--input", "secrets.json", "--format", "json", "--now", "2026-06-27"],
      reader({ "secrets.json": FIXTURE }),
    );
    expect(res.exitCode).toBe(0);
    const parsed = JSON.parse(res.stdout);
    expect(parsed.summary).toEqual({ total: 3, expired: 1, warning: 1, ok: 1 });
  });

  test("exits non-zero with --fail-on-expired when expired secrets exist", () => {
    const res = run(
      ["--input", "secrets.json", "--now", "2026-06-27", "--fail-on-expired"],
      reader({ "secrets.json": FIXTURE }),
    );
    expect(res.exitCode).toBe(1);
  });

  test("exits 0 with --fail-on-expired when nothing is expired", () => {
    const fresh = JSON.stringify([
      { name: "fresh", lastRotated: "2026-06-25", rotationPolicyDays: 90, requiredBy: [] },
    ]);
    const res = run(
      ["--input", "fresh.json", "--now", "2026-06-27", "--fail-on-expired"],
      reader({ "fresh.json": fresh }),
    );
    expect(res.exitCode).toBe(0);
  });

  test("returns exit code 2 with an error message on a missing input file", () => {
    const res = run(["--input", "missing.json"], reader({}));
    expect(res.exitCode).toBe(2);
    expect(res.stderr).toMatch(/missing\.json|ENOENT/);
  });

  test("returns exit code 2 on invalid config", () => {
    const res = run(
      ["--input", "bad.json", "--now", "2026-06-27"],
      reader({ "bad.json": "{not json" }),
    );
    expect(res.exitCode).toBe(2);
    expect(res.stderr).toMatch(/parse/i);
  });
});
