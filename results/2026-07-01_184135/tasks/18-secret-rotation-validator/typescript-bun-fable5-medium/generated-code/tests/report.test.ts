// RED/GREEN cycle 2: building the full rotation report.
//
// buildReport groups classified secrets into urgency buckets and sorts each
// bucket by most-urgent-first (fewest days until expiry), so the report reads
// top-down in priority order.
import { describe, expect, test } from "bun:test";
import { buildReport } from "../src/validator";
import type { Secret } from "../src/types";

const NOW = new Date("2026-07-01T00:00:00Z");

// Fixture spanning all three urgency buckets relative to NOW (2026-07-01):
const SECRETS: Secret[] = [
  // expires 2026-08-30 -> ok (60 days out)
  { name: "api-key", lastRotated: "2026-06-01", rotationPolicyDays: 90, requiredBy: ["api"] },
  // expired 2026-05-30 -> expired (32 days overdue)
  { name: "db-password", lastRotated: "2026-03-01", rotationPolicyDays: 90, requiredBy: ["api", "worker"] },
  // expires 2026-07-08 -> warning (7 days out, window 14)
  { name: "tls-cert", lastRotated: "2026-04-09", rotationPolicyDays: 90, requiredBy: ["gateway"] },
  // expired 2026-06-21 -> expired (10 days overdue), less urgent than db-password
  { name: "oauth-secret", lastRotated: "2026-05-22", rotationPolicyDays: 30, requiredBy: ["auth"] },
];

describe("buildReport", () => {
  test("groups secrets into expired/warning/ok buckets", () => {
    const report = buildReport(SECRETS, NOW, 14);
    expect(report.expired.map((s) => s.secret.name)).toEqual([
      "db-password",
      "oauth-secret",
    ]);
    expect(report.warning.map((s) => s.secret.name)).toEqual(["tls-cert"]);
    expect(report.ok.map((s) => s.secret.name)).toEqual(["api-key"]);
  });

  test("records the report date and warning window", () => {
    const report = buildReport(SECRETS, NOW, 14);
    expect(report.generatedFor).toBe("2026-07-01");
    expect(report.warningWindowDays).toBe(14);
  });

  test("sorts each bucket most-urgent-first", () => {
    const report = buildReport(SECRETS, NOW, 14);
    // db-password is 32 days overdue, oauth-secret only 10
    expect(report.expired[0]!.daysUntilExpiry).toBe(-32);
    expect(report.expired[1]!.daysUntilExpiry).toBe(-10);
  });

  test("handles an empty secret list", () => {
    const report = buildReport([], NOW, 14);
    expect(report.expired).toEqual([]);
    expect(report.warning).toEqual([]);
    expect(report.ok).toEqual([]);
  });

  test("rejects duplicate secret names with a clear message", () => {
    const dupes = [SECRETS[0]!, { ...SECRETS[0]! }];
    expect(() => buildReport(dupes, NOW, 14)).toThrow(
      'Duplicate secret name in configuration: "api-key"',
    );
  });

  test("rejects a negative warning window", () => {
    expect(() => buildReport(SECRETS, NOW, -1)).toThrow(
      "warningWindowDays must be a non-negative integer, got: -1",
    );
  });
});
