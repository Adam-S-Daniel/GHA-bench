/**
 * Cycle 4 (red/green TDD): CLI argument parsing + the `main()` orchestration.
 *
 * `main()` takes an injected I/O object (file reader, stdout/stderr sinks, and a
 * clock) so the entire CLI flow — arg parsing, file read, validation, format
 * selection, and exit-code policy — can be exercised deterministically without
 * spawning a process or touching the real filesystem/clock.
 */
import { describe, expect, test } from "bun:test";
import { parseArgs, main, type CliIO } from "../src/cli";
import { parseDate } from "../src/validator";

const MIXED_CONFIG = JSON.stringify({
  secrets: [
    { name: "AWS_ACCESS_KEY", lastRotated: "2026-01-01", rotationPolicyDays: 90, requiredBy: ["api", "worker"] },
    { name: "DB_PASSWORD", lastRotated: "2026-05-01", rotationPolicyDays: 60, requiredBy: ["api"] },
    { name: "STRIPE_API_KEY", lastRotated: "2026-06-01", rotationPolicyDays: 90, requiredBy: ["billing"] },
    { name: "JWT_SIGNING_KEY", lastRotated: "2026-06-20", rotationPolicyDays: 30, requiredBy: ["auth"] },
  ],
});

const ALL_OK_CONFIG = JSON.stringify({
  secrets: [{ name: "FRESH", lastRotated: "2026-06-25", rotationPolicyDays: 365, requiredBy: ["x"] }],
});

/** Build an in-memory I/O harness that records stdout/stderr. */
function fakeIO(files: Record<string, string>, nowDate = parseDate("2026-06-28")) {
  let out = "";
  let err = "";
  const io: CliIO = {
    readFile: async (p: string): Promise<string> => {
      if (!(p in files)) throw new Error(`Config file "${p}" not found.`);
      return files[p]!;
    },
    stdout: (s: string): void => {
      out += s;
    },
    stderr: (s: string): void => {
      err += s;
    },
    now: (): Date => nowDate,
  };
  return { io, out: () => out, err: () => err };
}

describe("parseArgs", () => {
  test("applies sensible defaults", () => {
    const o = parseArgs(["--config", "c.json"]);
    expect(o.config).toBe("c.json");
    expect(o.warningDays).toBe(14);
    expect(o.format).toBe("markdown");
    expect(o.failOn).toBe("none");
    expect(o.help).toBe(false);
  });

  test("supports both --key value and --key=value forms", () => {
    const o = parseArgs(["--config=c.json", "--warning-days=30", "--format=json"]);
    expect(o.config).toBe("c.json");
    expect(o.warningDays).toBe(30);
    expect(o.format).toBe("json");
  });

  test("rejects unknown flags", () => {
    expect(() => parseArgs(["--bogus"])).toThrow(/Unknown argument: --bogus/);
  });

  test("rejects a flag with a missing value", () => {
    expect(() => parseArgs(["--config"])).toThrow(/Missing value for --config/);
  });

  test("rejects an invalid format", () => {
    expect(() => parseArgs(["--format", "xml"])).toThrow(/--format must be one of/);
  });

  test("rejects an invalid fail-on level", () => {
    expect(() => parseArgs(["--fail-on", "loud"])).toThrow(/--fail-on must be one of/);
  });
});

describe("main()", () => {
  test("--help prints usage and exits 0", async () => {
    const h = fakeIO({});
    const code = await main(["--help"], h.io);
    expect(code).toBe(0);
    expect(h.out()).toContain("Usage:");
  });

  test("missing --config is a usage error (exit 2)", async () => {
    const h = fakeIO({});
    const code = await main([], h.io);
    expect(code).toBe(2);
    expect(h.err()).toMatch(/--config .* is required/);
  });

  test("github format emits exact counters and exits 0", async () => {
    const h = fakeIO({ "secrets.json": MIXED_CONFIG });
    const code = await main(["--config", "secrets.json", "--format", "github"], h.io);
    expect(code).toBe(0);
    expect(h.out()).toBe("total=4\nexpired=1\nwarning=1\nok=2\n");
  });

  test("json format produces a parseable report with the right summary", async () => {
    const h = fakeIO({ "secrets.json": MIXED_CONFIG });
    const code = await main(["--config", "secrets.json", "--format", "json"], h.io);
    expect(code).toBe(0);
    const report = JSON.parse(h.out());
    expect(report.summary).toEqual({ total: 4, expired: 1, warning: 1, ok: 2 });
    expect(report.generatedAt).toBe("2026-06-28");
  });

  test("a missing config file is a graceful error (exit 2)", async () => {
    const h = fakeIO({});
    const code = await main(["--config", "nope.json"], h.io);
    expect(code).toBe(2);
    expect(h.err()).toMatch(/not found/);
  });

  test("invalid JSON is reported clearly (exit 2)", async () => {
    const h = fakeIO({ "bad.json": "{not json" });
    const code = await main(["--config", "bad.json"], h.io);
    expect(code).toBe(2);
    expect(h.err()).toMatch(/not valid JSON/);
  });

  test("a validation error surfaces the offending secret (exit 2)", async () => {
    const h = fakeIO({ "bad.json": JSON.stringify({ secrets: [{ name: "X", lastRotated: "soon", rotationPolicyDays: 1 }] }) });
    const code = await main(["--config", "bad.json"], h.io);
    expect(code).toBe(2);
    expect(h.err()).toMatch(/secret "X".*Invalid date "soon"/);
  });

  test("--fail-on expired returns 1 when an expired secret exists", async () => {
    const h = fakeIO({ "secrets.json": MIXED_CONFIG });
    const code = await main(["--config", "secrets.json", "--format", "github", "--fail-on", "expired"], h.io);
    expect(code).toBe(1);
  });

  test("--fail-on expired returns 0 when nothing is expired", async () => {
    const h = fakeIO({ "ok.json": ALL_OK_CONFIG });
    const code = await main(["--config", "ok.json", "--format", "github", "--fail-on", "expired"], h.io);
    expect(code).toBe(0);
    expect(h.out()).toBe("total=1\nexpired=0\nwarning=0\nok=1\n");
  });

  test("--now overrides the clock for deterministic evaluation", async () => {
    const h = fakeIO({ "secrets.json": MIXED_CONFIG });
    // Far-future reference date: every secret is now overdue.
    const code = await main(["--config", "secrets.json", "--format", "github", "--now", "2027-01-01"], h.io);
    expect(code).toBe(0);
    expect(h.out()).toBe("total=4\nexpired=4\nwarning=0\nok=0\n");
  });
});
