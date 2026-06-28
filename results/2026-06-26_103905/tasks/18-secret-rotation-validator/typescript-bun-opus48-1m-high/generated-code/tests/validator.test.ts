// Unit tests for the core secret-rotation domain logic (TDD).
// These exercise the pure functions in src/validator.ts directly so we get
// fast red/green feedback on classification + date math. The end-to-end
// pipeline behaviour is exercised separately through `act` in workflow.test.ts.

import { describe, expect, test } from "bun:test";
import {
  evaluateSecret,
  generateReport,
  parseConfig,
  type Secret,
} from "../src/validator.ts";

// A deterministic "today" so the maths never depends on the wall clock.
const NOW = "2026-06-27";

describe("evaluateSecret", () => {
  test("classifies a secret past its rotation policy as 'expired'", () => {
    const secret: Secret = {
      name: "DATABASE_PASSWORD",
      lastRotated: "2026-01-01",
      rotationPolicyDays: 90, // expires 2026-04-01, well before NOW
      requiredBy: ["api", "worker"],
    };

    const result = evaluateSecret(secret, NOW, 14);

    expect(result.status).toBe("expired");
    expect(result.expiresOn).toBe("2026-04-01");
    expect(result.daysUntilExpiry).toBeLessThan(0);
  });

  test("classifies a secret inside the warning window as 'warning'", () => {
    const secret: Secret = {
      name: "API_TOKEN",
      lastRotated: "2026-06-01",
      rotationPolicyDays: 30, // expires 2026-07-01 -> 4 days from NOW
      requiredBy: ["gateway"],
    };

    const result = evaluateSecret(secret, NOW, 14);

    expect(result.status).toBe("warning");
    expect(result.expiresOn).toBe("2026-07-01");
    expect(result.daysUntilExpiry).toBe(4);
  });

  test("classifies a secret well outside the window as 'ok'", () => {
    const secret: Secret = {
      name: "TLS_CERT",
      lastRotated: "2026-06-01",
      rotationPolicyDays: 365, // expires 2027-06-01
      requiredBy: ["web"],
    };

    const result = evaluateSecret(secret, NOW, 14);

    expect(result.status).toBe("ok");
    expect(result.daysUntilExpiry).toBe(339);
  });

  test("treats a secret expiring exactly today as 'warning' (boundary)", () => {
    const secret: Secret = {
      name: "TODAY_SECRET",
      lastRotated: "2026-05-28",
      rotationPolicyDays: 30, // expires 2026-06-27 == NOW
      requiredBy: ["cron"],
    };

    const result = evaluateSecret(secret, NOW, 14);

    expect(result.daysUntilExpiry).toBe(0);
    expect(result.status).toBe("warning");
  });

  test("treats the warning-window edge day as 'warning', one past as 'ok'", () => {
    const onEdge: Secret = {
      name: "EDGE",
      lastRotated: "2026-06-13",
      rotationPolicyDays: 28, // expires 2026-07-11 -> 14 days from NOW
      requiredBy: ["svc"],
    };
    const justPast: Secret = {
      name: "PAST_EDGE",
      lastRotated: "2026-06-14",
      rotationPolicyDays: 28, // expires 2026-07-12 -> 15 days from NOW
      requiredBy: ["svc"],
    };

    expect(evaluateSecret(onEdge, NOW, 14).status).toBe("warning");
    expect(evaluateSecret(justPast, NOW, 14).status).toBe("ok");
  });
});

describe("parseConfig", () => {
  test("parses a valid config and applies the default warning window", () => {
    const cfg = parseConfig({
      secrets: [
        {
          name: "A",
          lastRotated: "2026-01-01",
          rotationPolicyDays: 30,
          requiredBy: ["svc"],
        },
      ],
    });

    expect(cfg.secrets).toHaveLength(1);
    expect(cfg.warningWindowDays).toBe(14); // default
  });

  test("respects an explicit warning window in the config", () => {
    const cfg = parseConfig({ secrets: [], warningWindowDays: 30 });
    expect(cfg.warningWindowDays).toBe(30);
  });

  test("throws a meaningful error when 'secrets' is missing", () => {
    expect(() => parseConfig({})).toThrow(/secrets.*array/i);
  });

  test("throws a meaningful error for a malformed secret entry", () => {
    expect(() =>
      parseConfig({ secrets: [{ name: "X", rotationPolicyDays: 30 }] }),
    ).toThrow(/lastRotated/i);
  });

  test("throws on an invalid date string", () => {
    expect(() =>
      parseConfig({
        secrets: [
          {
            name: "X",
            lastRotated: "not-a-date",
            rotationPolicyDays: 30,
            requiredBy: [],
          },
        ],
      }),
    ).toThrow(/date/i);
  });

  test("throws on a non-positive rotation policy", () => {
    expect(() =>
      parseConfig({
        secrets: [
          {
            name: "X",
            lastRotated: "2026-01-01",
            rotationPolicyDays: 0,
            requiredBy: [],
          },
        ],
      }),
    ).toThrow(/rotationPolicyDays/i);
  });
});

describe("generateReport", () => {
  const config = {
    warningWindowDays: 14,
    secrets: [
      {
        name: "DATABASE_PASSWORD",
        lastRotated: "2026-01-01",
        rotationPolicyDays: 90,
        requiredBy: ["api", "worker"],
      },
      {
        name: "API_TOKEN",
        lastRotated: "2026-06-01",
        rotationPolicyDays: 30,
        requiredBy: ["gateway"],
      },
      {
        name: "TLS_CERT",
        lastRotated: "2026-06-01",
        rotationPolicyDays: 365,
        requiredBy: ["web"],
      },
    ],
  };

  test("groups secrets by urgency and computes a summary", () => {
    const report = generateReport(parseConfig(config), NOW);

    expect(report.summary).toEqual({
      expired: 1,
      warning: 1,
      ok: 1,
      total: 3,
    });
    expect(report.groups.expired.map((s) => s.name)).toEqual([
      "DATABASE_PASSWORD",
    ]);
    expect(report.groups.warning.map((s) => s.name)).toEqual(["API_TOKEN"]);
    expect(report.groups.ok.map((s) => s.name)).toEqual(["TLS_CERT"]);
    expect(report.generatedAt).toBe(NOW);
    expect(report.warningWindowDays).toBe(14);
  });

  test("sorts each group by soonest expiry first", () => {
    const cfg = parseConfig({
      warningWindowDays: 7,
      secrets: [
        {
          name: "LATER",
          lastRotated: "2026-06-20",
          rotationPolicyDays: 5, // expires 2026-06-25
          requiredBy: [],
        },
        {
          name: "EARLIER",
          lastRotated: "2026-06-20",
          rotationPolicyDays: 1, // expires 2026-06-21
          requiredBy: [],
        },
      ],
    });

    const report = generateReport(cfg, NOW);
    // Both expired; earliest expiry should come first.
    expect(report.groups.expired.map((s) => s.name)).toEqual([
      "EARLIER",
      "LATER",
    ]);
  });
});
