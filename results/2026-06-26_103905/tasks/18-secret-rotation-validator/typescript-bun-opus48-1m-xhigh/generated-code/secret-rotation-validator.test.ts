/**
 * Unit tests for the Secret Rotation Validator core library.
 *
 * Built with red/green TDD: each `describe` block below was written as a
 * failing test first, then satisfied with the minimum implementation in
 * `secret-rotation-validator.ts`, then refactored.
 *
 * Run with: `bun test`
 */
import { describe, it, expect } from "bun:test";
import {
  classifySecret,
  generateReport,
  parseConfig,
  renderJson,
  renderMarkdown,
  renderGithubOutput,
  renderNotifications,
  formatReport,
  resolveExitCode,
  parseArgs,
  resolveOptions,
  runCli,
} from "./secret-rotation-validator.ts";
import type { SecretConfig, ValidatorConfig } from "./secret-rotation-validator.ts";

// A reusable fixture factory keeps each test focused on the one field it varies.
function makeSecret(overrides: Partial<SecretConfig> = {}): SecretConfig {
  return {
    name: "example-secret",
    lastRotated: "2026-01-01",
    rotationPolicyDays: 90,
    requiredBy: ["service-a"],
    ...overrides,
  };
}

describe("classifySecret", () => {
  // The rotation deadline (expiryDate) is lastRotated + rotationPolicyDays.
  // daysUntilExpiry = whole days between `now` and that deadline.
  it("computes the expiry date and days-until-expiry", () => {
    const result = classifySecret(
      makeSecret({ lastRotated: "2026-01-01", rotationPolicyDays: 90 }),
      { now: "2026-02-01", warningWindowDays: 14 },
    );
    expect(result.expiryDate).toBe("2026-04-01"); // Jan 1 + 90 days
    expect(result.daysUntilExpiry).toBe(59); // Feb 1 -> Apr 1
  });

  it("marks an overdue secret as expired", () => {
    const result = classifySecret(
      makeSecret({ lastRotated: "2026-01-01", rotationPolicyDays: 30 }),
      { now: "2026-03-01", warningWindowDays: 14 },
    );
    expect(result.status).toBe("expired");
    expect(result.daysUntilExpiry).toBeLessThan(0);
  });

  it("treats a secret due exactly today (0 days left) as expired", () => {
    const result = classifySecret(
      makeSecret({ lastRotated: "2026-01-01", rotationPolicyDays: 31 }),
      { now: "2026-02-01", warningWindowDays: 14 },
    );
    expect(result.daysUntilExpiry).toBe(0);
    expect(result.status).toBe("expired");
  });

  it("marks a secret inside the warning window as warning", () => {
    const result = classifySecret(
      makeSecret({ lastRotated: "2026-01-01", rotationPolicyDays: 40 }),
      { now: "2026-02-01", warningWindowDays: 14 }, // 9 days left
    );
    expect(result.daysUntilExpiry).toBe(9);
    expect(result.status).toBe("warning");
  });

  it("marks a secret beyond the warning window as ok", () => {
    const result = classifySecret(
      makeSecret({ lastRotated: "2026-01-01", rotationPolicyDays: 90 }),
      { now: "2026-02-01", warningWindowDays: 14 }, // 59 days left
    );
    expect(result.status).toBe("ok");
  });

  // Boundary: exactly at the warning window edge is still a warning; one day
  // beyond it is ok.
  it("is inclusive at the warning-window boundary", () => {
    const atEdge = classifySecret(
      makeSecret({ lastRotated: "2026-01-01", rotationPolicyDays: 45 }),
      { now: "2026-02-01", warningWindowDays: 14 }, // 14 days left
    );
    expect(atEdge.daysUntilExpiry).toBe(14);
    expect(atEdge.status).toBe("warning");

    const justBeyond = classifySecret(
      makeSecret({ lastRotated: "2026-01-01", rotationPolicyDays: 46 }),
      { now: "2026-02-01", warningWindowDays: 14 }, // 15 days left
    );
    expect(justBeyond.daysUntilExpiry).toBe(15);
    expect(justBeyond.status).toBe("ok");
  });

  it("carries through name, requiredBy and policy metadata", () => {
    const result = classifySecret(
      makeSecret({ name: "db-password", requiredBy: ["api", "worker"] }),
      { now: "2026-02-01", warningWindowDays: 14 },
    );
    expect(result.name).toBe("db-password");
    expect(result.requiredBy).toEqual(["api", "worker"]);
    expect(result.rotationPolicyDays).toBe(90);
  });
});

describe("generateReport", () => {
  // A mixed fixture: one of each urgency, deliberately out of urgency order so
  // we can prove the report sorts/groups them.
  const mixed: SecretConfig[] = [
    { name: "ok-secret", lastRotated: "2026-01-01", rotationPolicyDays: 90, requiredBy: ["web"] },
    { name: "expired-secret", lastRotated: "2026-01-01", rotationPolicyDays: 30, requiredBy: ["db"] },
    { name: "warning-secret", lastRotated: "2026-01-01", rotationPolicyDays: 40, requiredBy: ["api"] },
  ];

  it("groups secrets by urgency and tallies a summary", () => {
    const report = generateReport(mixed, { now: "2026-02-01", warningWindowDays: 14 });

    expect(report.summary).toEqual({ total: 3, expired: 1, warning: 1, ok: 1 });
    expect(report.groups.expired.map((s) => s.name)).toEqual(["expired-secret"]);
    expect(report.groups.warning.map((s) => s.name)).toEqual(["warning-secret"]);
    expect(report.groups.ok.map((s) => s.name)).toEqual(["ok-secret"]);
  });

  it("echoes the evaluation context (now + warning window)", () => {
    const report = generateReport(mixed, { now: "2026-02-01", warningWindowDays: 14 });
    expect(report.now).toBe("2026-02-01");
    expect(report.warningWindowDays).toBe(14);
  });

  it("within a group, sorts by soonest deadline first (most urgent first)", () => {
    const secrets: SecretConfig[] = [
      { name: "expires-later", lastRotated: "2026-01-01", rotationPolicyDays: 20, requiredBy: [] },
      { name: "expires-sooner", lastRotated: "2026-01-01", rotationPolicyDays: 10, requiredBy: [] },
    ];
    const report = generateReport(secrets, { now: "2026-03-01", warningWindowDays: 14 });
    // Both expired; the one overdue the longest (most negative days) comes first.
    expect(report.groups.expired.map((s) => s.name)).toEqual([
      "expires-sooner",
      "expires-later",
    ]);
  });

  it("handles an empty secret list", () => {
    const report = generateReport([], { now: "2026-02-01", warningWindowDays: 14 });
    expect(report.summary).toEqual({ total: 0, expired: 0, warning: 0, ok: 0 });
    expect(report.groups.expired).toEqual([]);
  });
});

describe("parseConfig", () => {
  // The config file may carry its own `now` / `warningWindowDays` defaults so a
  // fixture is fully self-describing (used by the CI workflow for determinism).
  it("parses a well-formed config object", () => {
    const raw: unknown = {
      now: "2026-02-01",
      warningWindowDays: 7,
      secrets: [
        { name: "a", lastRotated: "2026-01-01", rotationPolicyDays: 30, requiredBy: ["svc"] },
      ],
    };
    const cfg: ValidatorConfig = parseConfig(raw);
    expect(cfg.warningWindowDays).toBe(7);
    expect(cfg.now).toBe("2026-02-01");
    expect(cfg.secrets).toHaveLength(1);
    expect(cfg.secrets[0]!.name).toBe("a");
  });

  it("accepts a bare array of secrets as shorthand", () => {
    const raw: unknown = [
      { name: "a", lastRotated: "2026-01-01", rotationPolicyDays: 30, requiredBy: [] },
    ];
    const cfg = parseConfig(raw);
    expect(cfg.secrets).toHaveLength(1);
    expect(cfg.now).toBeUndefined();
  });

  it("defaults requiredBy to an empty array when omitted", () => {
    const cfg = parseConfig({
      secrets: [{ name: "a", lastRotated: "2026-01-01", rotationPolicyDays: 30 }],
    });
    expect(cfg.secrets[0]!.requiredBy).toEqual([]);
  });

  it("rejects a config that is not an object or array", () => {
    expect(() => parseConfig("nope")).toThrow(/must be a JSON object or array/i);
  });

  it("rejects a missing/empty secret name", () => {
    expect(() =>
      parseConfig({ secrets: [{ name: "", lastRotated: "2026-01-01", rotationPolicyDays: 30 }] }),
    ).toThrow(/name/i);
  });

  it("rejects a non-positive rotation policy", () => {
    expect(() =>
      parseConfig({
        secrets: [{ name: "a", lastRotated: "2026-01-01", rotationPolicyDays: 0 }],
      }),
    ).toThrow(/rotationPolicyDays/i);
  });

  it("rejects an invalid lastRotated date", () => {
    expect(() =>
      parseConfig({
        secrets: [{ name: "a", lastRotated: "2026-13-99", rotationPolicyDays: 30 }],
      }),
    ).toThrow(/lastRotated/i);
  });
});

// Shared fixture for the rendering tests: deterministic and covers all buckets.
const renderFixture: SecretConfig[] = [
  { name: "db-password", lastRotated: "2026-01-01", rotationPolicyDays: 30, requiredBy: ["api", "worker"] },
  { name: "tls-cert", lastRotated: "2026-01-01", rotationPolicyDays: 40, requiredBy: ["gateway"] },
  { name: "oauth-client-secret", lastRotated: "2026-01-01", rotationPolicyDays: 365, requiredBy: ["sso"] },
];
const renderReport = generateReport(renderFixture, { now: "2026-02-01", warningWindowDays: 14 });

describe("renderJson", () => {
  it("emits valid JSON that round-trips to the report shape", () => {
    const json = renderJson(renderReport);
    const parsed = JSON.parse(json);
    expect(parsed.summary).toEqual({ total: 3, expired: 1, warning: 1, ok: 1 });
    expect(parsed.now).toBe("2026-02-01");
    expect(parsed.warningWindowDays).toBe(14);
    expect(parsed.groups.expired[0].name).toBe("db-password");
    expect(parsed.groups.expired[0].daysUntilExpiry).toBeLessThan(0);
    expect(parsed.groups.warning[0].name).toBe("tls-cert");
    expect(parsed.groups.ok[0].name).toBe("oauth-client-secret");
  });
});

describe("renderMarkdown", () => {
  const md = renderMarkdown(renderReport);

  it("includes a summary line with the counts", () => {
    expect(md).toContain("**Total:** 3");
    expect(md).toContain("**Expired:** 1");
    expect(md).toContain("**Warning:** 1");
    expect(md).toContain("**OK:** 1");
  });

  it("renders a table with a header row and the expected columns", () => {
    expect(md).toContain("| Secret | Status | Last Rotated | Policy (days) | Expiry | Days Left | Required By |");
    expect(md).toMatch(/\|\s*---/); // a markdown separator row
  });

  it("renders one row per secret with its status and dependents", () => {
    expect(md).toContain("| db-password | expired |");
    expect(md).toContain("| tls-cert | warning |");
    expect(md).toContain("| oauth-client-secret | ok |");
    expect(md).toContain("api, worker"); // requiredBy joined
  });

  it("orders rows by urgency (expired before warning before ok)", () => {
    const iExpired = md.indexOf("db-password");
    const iWarning = md.indexOf("tls-cert");
    const iOk = md.indexOf("oauth-client-secret");
    expect(iExpired).toBeLessThan(iWarning);
    expect(iWarning).toBeLessThan(iOk);
  });
});

describe("renderGithubOutput", () => {
  it("emits key=value lines suitable for $GITHUB_OUTPUT", () => {
    const out = renderGithubOutput(renderReport);
    expect(out).toContain("total=3");
    expect(out).toContain("expired_count=1");
    expect(out).toContain("warning_count=1");
    expect(out).toContain("ok_count=1");
    expect(out).toContain("expired_names=db-password");
    expect(out).toContain("warning_names=tls-cert");
    expect(out).toContain("ok_names=oauth-client-secret");
  });

  it("uses an empty value when a bucket has no secrets", () => {
    const report = generateReport([], { now: "2026-02-01", warningWindowDays: 14 });
    const out = renderGithubOutput(report);
    expect(out).toContain("expired_names=\n");
    expect(out).toContain("total=0");
  });
});

describe("renderNotifications", () => {
  const text = renderNotifications(renderReport);

  it("groups notifications by urgency with counts", () => {
    expect(text).toContain("EXPIRED (1)");
    expect(text).toContain("WARNING (1)");
    expect(text).toContain("OK (1)");
  });

  it("names the affected secrets and their dependent services", () => {
    expect(text).toContain("db-password");
    expect(text).toContain("api, worker");
  });
});

describe("formatReport (dispatch)", () => {
  it("routes to the requested format", () => {
    expect(formatReport(renderReport, "json")).toBe(renderJson(renderReport));
    expect(formatReport(renderReport, "markdown")).toBe(renderMarkdown(renderReport));
    expect(formatReport(renderReport, "github")).toBe(renderGithubOutput(renderReport));
  });

  it("throws on an unknown format", () => {
    // @ts-expect-error deliberately passing an invalid format at runtime
    expect(() => formatReport(renderReport, "xml")).toThrow(/unknown.*format/i);
  });
});

describe("resolveExitCode (CI gating)", () => {
  it("returns 0 when fail-on is none, regardless of findings", () => {
    expect(resolveExitCode(renderReport, "none")).toBe(0);
  });

  it("returns non-zero on expired when fail-on is expired", () => {
    expect(resolveExitCode(renderReport, "expired")).toBe(1);
  });

  it("returns non-zero on warning when fail-on is warning", () => {
    expect(resolveExitCode(renderReport, "warning")).toBe(1);
  });

  it("returns 0 when fail-on threshold is not met", () => {
    const allOk = generateReport(
      [{ name: "fresh", lastRotated: "2026-01-01", rotationPolicyDays: 365, requiredBy: [] }],
      { now: "2026-02-01", warningWindowDays: 14 },
    );
    expect(resolveExitCode(allOk, "expired")).toBe(0);
    expect(resolveExitCode(allOk, "warning")).toBe(0);
  });
});

describe("parseArgs", () => {
  it("parses long and short flags", () => {
    const args = parseArgs([
      "--config", "c.json",
      "--format", "json",
      "--warning-days", "21",
      "--now", "2026-06-28",
      "--fail-on", "expired",
      "--notify",
    ]);
    expect(args.config).toBe("c.json");
    expect(args.format).toBe("json");
    expect(args.warningWindowDays).toBe(21);
    expect(args.now).toBe("2026-06-28");
    expect(args.failOn).toBe("expired");
    expect(args.notify).toBe(true);
  });

  it("supports -c/-f/-w short aliases and --flag=value syntax", () => {
    const args = parseArgs(["-c", "c.json", "-f", "markdown", "-w", "7", "--fail-on=warning"]);
    expect(args.config).toBe("c.json");
    expect(args.format).toBe("markdown");
    expect(args.warningWindowDays).toBe(7);
    expect(args.failOn).toBe("warning");
  });

  it("flags --help", () => {
    expect(parseArgs(["--help"]).help).toBe(true);
    expect(parseArgs(["-h"]).help).toBe(true);
  });

  it("rejects an invalid format value", () => {
    expect(() => parseArgs(["--format", "xml"])).toThrow(/format/i);
  });

  it("rejects a non-numeric warning-days", () => {
    expect(() => parseArgs(["--warning-days", "soon"])).toThrow(/warning-days/i);
  });

  it("rejects an invalid fail-on value", () => {
    expect(() => parseArgs(["--fail-on", "always"])).toThrow(/fail-on/i);
  });

  it("rejects an unknown flag", () => {
    expect(() => parseArgs(["--bogus"])).toThrow(/unknown/i);
  });

  it("rejects a flag missing its value", () => {
    expect(() => parseArgs(["--config"])).toThrow(/value/i);
  });
});

describe("resolveOptions (precedence: CLI > env > config > default)", () => {
  const config: ValidatorConfig = {
    secrets: [],
    now: "2026-01-15",
    warningWindowDays: 5,
  };

  it("falls back to defaults when nothing else is set", () => {
    const opts = resolveOptions({}, { secrets: [] }, {}, "2026-12-31");
    expect(opts.now).toBe("2026-12-31"); // system "today"
    expect(opts.warningWindowDays).toBe(14); // default
    expect(opts.format).toBe("markdown"); // default
    expect(opts.failOn).toBe("none"); // default
  });

  it("uses config values over defaults", () => {
    const opts = resolveOptions({}, config, {}, "2026-12-31");
    expect(opts.now).toBe("2026-01-15");
    expect(opts.warningWindowDays).toBe(5);
  });

  it("uses env over config", () => {
    const opts = resolveOptions(
      {},
      config,
      { SECRET_ROTATION_NOW: "2026-02-02", SECRET_ROTATION_WARNING_DAYS: "9", SECRET_ROTATION_FORMAT: "json" },
      "2026-12-31",
    );
    expect(opts.now).toBe("2026-02-02");
    expect(opts.warningWindowDays).toBe(9);
    expect(opts.format).toBe("json");
  });

  it("uses CLI over everything", () => {
    const opts = resolveOptions(
      { now: "2026-03-03", warningWindowDays: 1, format: "github", failOn: "expired" },
      config,
      { SECRET_ROTATION_NOW: "2026-02-02", SECRET_ROTATION_WARNING_DAYS: "9" },
      "2026-12-31",
    );
    expect(opts.now).toBe("2026-03-03");
    expect(opts.warningWindowDays).toBe(1);
    expect(opts.format).toBe("github");
    expect(opts.failOn).toBe("expired");
  });
});

describe("runCli (end-to-end against fixture files)", () => {
  it("produces a correct JSON report for the mixed fixture", async () => {
    const result = await runCli(
      ["--config", "fixtures/secrets.json", "--format", "json"],
      {},
      "2099-01-01", // ignored: fixture carries its own `now`
    );
    expect(result.exitCode).toBe(0);
    const parsed = JSON.parse(result.stdout);
    expect(parsed.summary).toEqual({ total: 6, expired: 2, warning: 2, ok: 2 });
    expect(parsed.groups.expired.map((s: { name: string }) => s.name)).toEqual([
      "db-password",
      "stripe-api-key",
    ]);
    expect(parsed.groups.warning.map((s: { name: string }) => s.name)).toEqual([
      "tls-cert",
      "jwt-signing-key",
    ]);
  });

  it("produces github-output key=value lines for the mixed fixture", async () => {
    const result = await runCli(["-c", "fixtures/secrets.json", "-f", "github"], {}, "2099-01-01");
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toContain("total=6");
    expect(result.stdout).toContain("expired_count=2");
    expect(result.stdout).toContain("expired_names=db-password,stripe-api-key");
    expect(result.stdout).toContain("warning_names=tls-cert,jwt-signing-key");
  });

  it("reports all-ok fixture as fully ok", async () => {
    const result = await runCli(["-c", "fixtures/all-ok.json", "-f", "json"], {}, "2099-01-01");
    const parsed = JSON.parse(result.stdout);
    expect(parsed.summary).toEqual({ total: 2, expired: 0, warning: 0, ok: 2 });
  });

  it("classifies the boundary fixture exactly", async () => {
    const result = await runCli(["-c", "fixtures/boundary.json", "-f", "json"], {}, "2099-01-01");
    const parsed = JSON.parse(result.stdout);
    expect(parsed.summary).toEqual({ total: 3, expired: 1, warning: 1, ok: 1 });
    expect(parsed.groups.expired[0].name).toBe("due-today");
    expect(parsed.groups.warning[0].name).toBe("edge-warning");
    expect(parsed.groups.ok[0].name).toBe("just-ok");
  });

  it("exits non-zero with --fail-on expired when secrets are expired", async () => {
    const result = await runCli(
      ["-c", "fixtures/secrets.json", "-f", "json", "--fail-on", "expired"],
      {},
      "2099-01-01",
    );
    expect(result.exitCode).toBe(1);
  });

  it("includes notifications on stderr when --notify is set", async () => {
    const result = await runCli(
      ["-c", "fixtures/secrets.json", "-f", "json", "--notify"],
      {},
      "2099-01-01",
    );
    expect(result.stderr).toContain("EXPIRED (2)");
    expect(result.stderr).toContain("db-password");
  });

  it("errors clearly when the config file is missing", async () => {
    const result = await runCli(["-c", "fixtures/does-not-exist.json"], {}, "2099-01-01");
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toMatch(/not found|no such file|cannot|failed to read/i);
  });

  it("errors clearly when no config path is provided", async () => {
    const result = await runCli([], {}, "2099-01-01");
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toMatch(/config/i);
  });

  it("prints usage and exits 0 for --help", async () => {
    const result = await runCli(["--help"], {}, "2099-01-01");
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toMatch(/usage/i);
  });
});
