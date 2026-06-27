// Tests for CLI argument parsing and the end-to-end run() over an in-memory
// config (no filesystem / process needed). The full process-level behaviour is
// validated through `act` in workflow.test.ts.

import { describe, expect, test } from "bun:test";
import { parseArgs, runReport } from "../src/cli.ts";

describe("parseArgs", () => {
  test("applies sensible defaults", () => {
    const opts = parseArgs([]);
    expect(opts.config).toBe("secrets.json");
    expect(opts.format).toBe("markdown");
    expect(opts.warningWindow).toBeUndefined();
    expect(opts.failOn).toBe("none");
    expect(opts.help).toBe(false);
  });

  test("parses all supported flags (--flag value form)", () => {
    const opts = parseArgs([
      "--config",
      "fixtures/a.json",
      "--format",
      "json",
      "--warning-window",
      "30",
      "--now",
      "2026-06-27",
      "--fail-on",
      "expired",
      "--output",
      "out.md",
    ]);
    expect(opts.config).toBe("fixtures/a.json");
    expect(opts.format).toBe("json");
    expect(opts.warningWindow).toBe(30);
    expect(opts.now).toBe("2026-06-27");
    expect(opts.failOn).toBe("expired");
    expect(opts.output).toBe("out.md");
  });

  test("supports --flag=value form", () => {
    const opts = parseArgs(["--format=json", "--warning-window=7"]);
    expect(opts.format).toBe("json");
    expect(opts.warningWindow).toBe(7);
  });

  test("sets help on -h/--help", () => {
    expect(parseArgs(["--help"]).help).toBe(true);
    expect(parseArgs(["-h"]).help).toBe(true);
  });

  test("rejects an invalid --format value", () => {
    expect(() => parseArgs(["--format", "xml"])).toThrow(/format/i);
  });

  test("rejects a non-numeric --warning-window", () => {
    expect(() => parseArgs(["--warning-window", "soon"])).toThrow(
      /warning-window/i,
    );
  });

  test("rejects an unknown flag", () => {
    expect(() => parseArgs(["--frobnicate"])).toThrow(/unknown/i);
  });
});

describe("runReport", () => {
  const config = {
    warningWindowDays: 14,
    secrets: [
      {
        name: "DATABASE_PASSWORD",
        lastRotated: "2026-01-01",
        rotationPolicyDays: 90,
        requiredBy: ["api"],
      },
      {
        name: "TLS_CERT",
        lastRotated: "2026-06-01",
        rotationPolicyDays: 365,
        requiredBy: ["web"],
      },
    ],
  };

  test("produces the rendered output and an exitCode of 0 by default", () => {
    const { output, exitCode, report } = runReport(config, {
      config: "secrets.json",
      format: "json",
      now: "2026-06-27",
      failOn: "none",
      help: false,
    });
    expect(exitCode).toBe(0);
    expect(report.summary.expired).toBe(1);
    expect(JSON.parse(output).summary.expired).toBe(1);
  });

  test("returns exitCode 1 when --fail-on expired and an expired secret exists", () => {
    const { exitCode } = runReport(config, {
      config: "secrets.json",
      format: "markdown",
      now: "2026-06-27",
      failOn: "expired",
      help: false,
    });
    expect(exitCode).toBe(1);
  });

  test("returns exitCode 0 for --fail-on expired when nothing is expired", () => {
    const okOnly = { secrets: [config.secrets[1]] };
    const { exitCode } = runReport(okOnly, {
      config: "secrets.json",
      format: "markdown",
      now: "2026-06-27",
      failOn: "expired",
      help: false,
    });
    expect(exitCode).toBe(0);
  });

  test("--warning-window overrides the config window", () => {
    const { report } = runReport(config, {
      config: "secrets.json",
      format: "json",
      now: "2026-06-27",
      warningWindow: 400, // huge window -> TLS_CERT becomes a warning
      failOn: "none",
      help: false,
    });
    expect(report.warningWindowDays).toBe(400);
    expect(report.summary.warning).toBe(1);
  });
});
