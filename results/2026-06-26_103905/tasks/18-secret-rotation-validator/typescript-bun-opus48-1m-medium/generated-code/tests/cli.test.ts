// RED step #5: drive out the CLI orchestration. runCli is pure-ish: it takes
// argv plus an injectable `now` and a file reader, and returns a result object
// (stdout/stderr/exitCode) instead of touching process directly.
import { describe, expect, it } from "bun:test";
import { runCli } from "../src/cli.ts";

const NOW = new Date("2026-06-27T00:00:00Z");

const FIXTURE = JSON.stringify({
  secrets: [
    { name: "LEGACY_API_KEY", lastRotated: "2025-12-01", rotationPolicyDays: 90, requiredBy: ["billing"] },
    { name: "DB_PASSWORD", lastRotated: "2026-04-08", rotationPolicyDays: 90, requiredBy: ["api"] },
    { name: "SIGNING_KEY", lastRotated: "2026-06-27", rotationPolicyDays: 365, requiredBy: ["auth"] },
  ],
});

// A fake file reader so the CLI never hits the real filesystem in unit tests.
function reader(contents: Record<string, string>) {
  return (path: string): string => {
    const found = contents[path];
    if (found === undefined) throw new Error(`ENOENT: ${path}`);
    return found;
  };
}

describe("runCli", () => {
  it("defaults to markdown output and exits non-zero when secrets are expired", () => {
    const result = runCli(["--config", "secrets.json"], {
      now: NOW,
      readFile: reader({ "secrets.json": FIXTURE }),
    });
    expect(result.stdout).toContain("# Secret Rotation Report");
    expect(result.stdout).toContain("| LEGACY_API_KEY | expired |");
    // Expired secret present -> non-zero exit so CI fails.
    expect(result.exitCode).toBe(1);
  });

  it("emits JSON when --format json is given", () => {
    const result = runCli(["--config", "secrets.json", "--format", "json"], {
      now: NOW,
      readFile: reader({ "secrets.json": FIXTURE }),
    });
    const parsed = JSON.parse(result.stdout);
    expect(parsed.summary.total).toBe(3);
    expect(parsed.notifications.expired[0].name).toBe("LEGACY_API_KEY");
  });

  it("honours a custom --warning-window", () => {
    // With a 200-day window, DB_PASSWORD (due in 10) AND SIGNING_KEY... actually
    // SIGNING_KEY is due in 365 so still ok; DB_PASSWORD stays warning.
    const result = runCli(
      ["--config", "secrets.json", "--format", "json", "--warning-window", "5"],
      { now: NOW, readFile: reader({ "secrets.json": FIXTURE }) },
    );
    const parsed = JSON.parse(result.stdout);
    // With a 5-day window, DB_PASSWORD (due in 10) is no longer a warning -> ok.
    expect(parsed.summary.warning).toBe(0);
    expect(parsed.summary.ok).toBe(2);
  });

  it("exits 0 when nothing is expired", () => {
    const allOk = JSON.stringify({
      secrets: [{ name: "OK", lastRotated: "2026-06-27", rotationPolicyDays: 365, requiredBy: [] }],
    });
    const result = runCli(["--config", "ok.json"], {
      now: NOW,
      readFile: reader({ "ok.json": allOk }),
    });
    expect(result.exitCode).toBe(0);
  });

  it("returns a friendly error (exit 2) when the config file is missing", () => {
    const result = runCli(["--config", "missing.json"], {
      now: NOW,
      readFile: reader({}),
    });
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("missing.json");
  });

  it("returns a usage error (exit 2) for an unknown format", () => {
    const result = runCli(["--config", "secrets.json", "--format", "xml"], {
      now: NOW,
      readFile: reader({ "secrets.json": FIXTURE }),
    });
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("Unknown format");
  });

  it("pins the reference clock with --now for deterministic CI output", () => {
    // --now overrides deps.now, so output is reproducible regardless of wall clock.
    const result = runCli(
      ["--config", "secrets.json", "--format", "json", "--now", "2026-06-27"],
      { now: new Date("2000-01-01T00:00:00Z"), readFile: reader({ "secrets.json": FIXTURE }) },
    );
    const parsed = JSON.parse(result.stdout);
    expect(parsed.generatedAt).toBe("2026-06-27T00:00:00.000Z");
    expect(parsed.summary.expired).toBe(1);
  });

  it("rejects an invalid --now value (exit 2)", () => {
    const result = runCli(["--config", "secrets.json", "--now", "nope"], {
      now: NOW,
      readFile: reader({ "secrets.json": FIXTURE }),
    });
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("--now");
  });

  it("prints help with --help and exits 0", () => {
    const result = runCli(["--help"], { now: NOW, readFile: reader({}) });
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toContain("Usage");
  });
});
