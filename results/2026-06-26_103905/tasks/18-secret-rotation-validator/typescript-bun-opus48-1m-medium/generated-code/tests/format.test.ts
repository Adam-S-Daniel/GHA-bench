// RED step #3: drive out the renderers (markdown table + JSON).
import { describe, expect, it } from "bun:test";
import { buildReport } from "../src/report.ts";
import { renderJson, renderMarkdown } from "../src/format.ts";
import type { SecretConfig } from "../src/validator.ts";

const NOW = new Date("2026-06-27T00:00:00Z");

const CONFIG: SecretConfig = {
  secrets: [
    { name: "LEGACY_API_KEY", lastRotated: "2025-12-01", rotationPolicyDays: 90, requiredBy: ["billing"] },
    { name: "DB_PASSWORD", lastRotated: "2026-04-08", rotationPolicyDays: 90, requiredBy: ["api", "worker"] },
    { name: "SIGNING_KEY", lastRotated: "2026-06-27", rotationPolicyDays: 365, requiredBy: ["auth"] },
  ],
};

describe("renderMarkdown", () => {
  const report = buildReport(CONFIG, { now: NOW, warningWindowDays: 14 });
  const md = renderMarkdown(report);

  it("includes a title and a summary line with counts", () => {
    expect(md).toContain("# Secret Rotation Report");
    expect(md).toContain("**Expired:** 1");
    expect(md).toContain("**Warning:** 1");
    expect(md).toContain("**OK:** 1");
  });

  it("renders a markdown table with a header row and one row per secret", () => {
    expect(md).toContain("| Secret | Status | Days Until Due | Last Rotated | Policy (days) | Required By |");
    expect(md).toContain("| --- | --- | --- | --- | --- | --- |");
    // Expired secret row, with overdue days shown as a negative number.
    expect(md).toContain("| LEGACY_API_KEY | expired |");
    // Warning secret with its two services joined.
    expect(md).toContain("| DB_PASSWORD | warning | 10 | 2026-04-08 | 90 | api, worker |");
    // OK secret.
    expect(md).toContain("| SIGNING_KEY | ok | 365 | 2026-06-27 | 365 | auth |");
  });

  it("orders rows by severity: expired before warning before ok", () => {
    const expiredIdx = md.indexOf("LEGACY_API_KEY");
    const warningIdx = md.indexOf("DB_PASSWORD");
    const okIdx = md.indexOf("SIGNING_KEY");
    expect(expiredIdx).toBeLessThan(warningIdx);
    expect(warningIdx).toBeLessThan(okIdx);
  });
});

describe("renderJson", () => {
  const report = buildReport(CONFIG, { now: NOW, warningWindowDays: 14 });
  const json = renderJson(report);
  const parsed = JSON.parse(json);

  it("emits valid, machine-readable JSON with summary and grouped notifications", () => {
    expect(parsed.summary).toEqual({ expired: 1, warning: 1, ok: 1, total: 3 });
    expect(parsed.warningWindowDays).toBe(14);
    expect(parsed.generatedAt).toBe("2026-06-27T00:00:00.000Z");
    expect(parsed.hasExpired).toBe(true);

    // Notifications are grouped by urgency.
    expect(parsed.notifications.expired[0].name).toBe("LEGACY_API_KEY");
    expect(parsed.notifications.warning[0].name).toBe("DB_PASSWORD");
    expect(parsed.notifications.warning[0].daysUntilDue).toBe(10);
    expect(parsed.notifications.warning[0].requiredBy).toEqual(["api", "worker"]);
    expect(parsed.notifications.ok[0].name).toBe("SIGNING_KEY");
  });
});
