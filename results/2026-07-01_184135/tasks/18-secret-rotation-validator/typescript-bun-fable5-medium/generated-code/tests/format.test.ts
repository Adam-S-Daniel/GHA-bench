// RED/GREEN cycle 3: output formatting.
//
// Two formats are supported:
//   - markdown: a human-readable report with one table per urgency bucket
//   - json:     a machine-readable report with per-secret notification messages
// Both group notifications by urgency (expired, warning, ok).
import { describe, expect, test } from "bun:test";
import { buildReport } from "../src/validator";
import { buildNotification, formatJson, formatMarkdown } from "../src/format";
import type { Secret } from "../src/types";

const NOW = new Date("2026-07-01T00:00:00Z");

const SECRETS: Secret[] = [
  { name: "api-key", lastRotated: "2026-06-01", rotationPolicyDays: 90, requiredBy: ["api"] },
  { name: "db-password", lastRotated: "2026-03-01", rotationPolicyDays: 90, requiredBy: ["api", "worker"] },
  { name: "tls-cert", lastRotated: "2026-04-09", rotationPolicyDays: 90, requiredBy: ["gateway"] },
];

const report = () => buildReport(SECRETS, NOW, 14);

describe("buildNotification", () => {
  test("expired secret gets an urgent, actionable message", () => {
    const status = report().expired[0]!;
    expect(buildNotification(status)).toBe(
      'Secret "db-password" EXPIRED 32 days ago on 2026-05-30 — rotate immediately! Required by: api, worker.',
    );
  });

  test("warning secret says when it expires", () => {
    const status = report().warning[0]!;
    expect(buildNotification(status)).toBe(
      'Secret "tls-cert" expires in 7 days on 2026-07-08 — schedule a rotation. Required by: gateway.',
    );
  });

  test("ok secret reports next due date", () => {
    const status = report().ok[0]!;
    expect(buildNotification(status)).toBe(
      'Secret "api-key" is healthy; next rotation due 2026-08-30 (60 days). Required by: api.',
    );
  });
});

describe("formatMarkdown", () => {
  test("renders header, summary line, and per-bucket tables", () => {
    const md = formatMarkdown(report());
    expect(md).toContain("# Secret Rotation Report");
    expect(md).toContain(
      "Generated for **2026-07-01** (warning window: 14 days)",
    );
    expect(md).toContain("**Summary:** 1 expired, 1 warning, 1 ok");
    expect(md).toContain("## 🔴 Expired (1)");
    expect(md).toContain("## 🟡 Warning (1)");
    expect(md).toContain("## 🟢 Ok (1)");
    // Exact table row for the expired secret
    expect(md).toContain(
      "| db-password | 2026-03-01 | 90 | 2026-05-30 | -32 | api, worker |",
    );
  });

  test("renders an empty bucket as _None_", () => {
    const empty = buildReport([], NOW, 14);
    const md = formatMarkdown(empty);
    expect(md).toContain("## 🔴 Expired (0)");
    expect(md).toContain("_None_");
  });
});

describe("formatJson", () => {
  test("emits valid JSON with counts and grouped notifications", () => {
    const parsed = JSON.parse(formatJson(report()));
    expect(parsed.generatedFor).toBe("2026-07-01");
    expect(parsed.warningWindowDays).toBe(14);
    expect(parsed.summary).toEqual({ expired: 1, warning: 1, ok: 1 });
    expect(parsed.notifications.expired[0]).toEqual({
      name: "db-password",
      lastRotated: "2026-03-01",
      rotationPolicyDays: 90,
      expiresOn: "2026-05-30",
      daysUntilExpiry: -32,
      requiredBy: ["api", "worker"],
      message:
        'Secret "db-password" EXPIRED 32 days ago on 2026-05-30 — rotate immediately! Required by: api, worker.',
    });
    expect(parsed.notifications.warning.map((n: { name: string }) => n.name)).toEqual(["tls-cert"]);
    expect(parsed.notifications.ok.map((n: { name: string }) => n.name)).toEqual(["api-key"]);
  });
});
