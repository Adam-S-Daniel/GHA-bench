// RED step #2: drive out the report builder that turns a whole config into a
// grouped, summarised report ready for rendering.
import { describe, expect, it } from "bun:test";
import { buildReport } from "../src/report.ts";
import type { SecretConfig } from "../src/validator.ts";

const NOW = new Date("2026-06-27T00:00:00Z");

const CONFIG: SecretConfig = {
  secrets: [
    // Expired: rotated long ago.
    { name: "LEGACY_API_KEY", lastRotated: "2025-12-01", rotationPolicyDays: 90, requiredBy: ["billing"] },
    // Warning: due in 10 days, window 14.
    { name: "DB_PASSWORD", lastRotated: "2026-04-08", rotationPolicyDays: 90, requiredBy: ["api", "worker"] },
    // OK: rotated today.
    { name: "SIGNING_KEY", lastRotated: "2026-06-27", rotationPolicyDays: 365, requiredBy: ["auth"] },
  ],
};

describe("buildReport", () => {
  it("groups secrets by urgency and counts them", () => {
    const report = buildReport(CONFIG, { now: NOW, warningWindowDays: 14 });

    expect(report.summary.expired).toBe(1);
    expect(report.summary.warning).toBe(1);
    expect(report.summary.ok).toBe(1);
    expect(report.summary.total).toBe(3);

    expect(report.groups.expired.map((e) => e.secret.name)).toEqual(["LEGACY_API_KEY"]);
    expect(report.groups.warning.map((e) => e.secret.name)).toEqual(["DB_PASSWORD"]);
    expect(report.groups.ok.map((e) => e.secret.name)).toEqual(["SIGNING_KEY"]);
  });

  it("sorts each group by urgency (soonest due first)", () => {
    const config: SecretConfig = {
      secrets: [
        { name: "A", lastRotated: "2026-04-08", rotationPolicyDays: 90, requiredBy: [] }, // due in 10
        { name: "B", lastRotated: "2026-04-01", rotationPolicyDays: 90, requiredBy: [] }, // due in 3
      ],
    };
    const report = buildReport(config, { now: NOW, warningWindowDays: 30 });
    // B (3 days) should come before A (10 days).
    expect(report.groups.warning.map((e) => e.secret.name)).toEqual(["B", "A"]);
  });

  it("reports a non-zero exit intent when any secret is expired", () => {
    const report = buildReport(CONFIG, { now: NOW, warningWindowDays: 14 });
    expect(report.hasExpired).toBe(true);
  });

  it("records the configuration used so the report is self-describing", () => {
    const report = buildReport(CONFIG, { now: NOW, warningWindowDays: 14 });
    expect(report.warningWindowDays).toBe(14);
    expect(report.generatedAt).toBe("2026-06-27T00:00:00.000Z");
  });
});
