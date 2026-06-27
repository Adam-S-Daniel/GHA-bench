// Unit tests for the output formatters (markdown table + JSON).

import { describe, expect, test } from "bun:test";
import { generateReport, parseConfig } from "../src/validator.ts";
import { formatJson, formatMarkdown, formatReport } from "../src/report.ts";

const NOW = "2026-06-27";

const report = generateReport(
  parseConfig({
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
  }),
  NOW,
);

describe("formatJson", () => {
  test("round-trips the report structure as pretty JSON", () => {
    const json = formatJson(report);
    const parsed = JSON.parse(json);

    expect(parsed.summary).toEqual({
      expired: 1,
      warning: 1,
      ok: 1,
      total: 3,
    });
    expect(parsed.generatedAt).toBe(NOW);
    expect(parsed.groups.expired[0].name).toBe("DATABASE_PASSWORD");
    expect(parsed.groups.expired[0].daysUntilExpiry).toBeLessThan(0);
  });
});

describe("formatMarkdown", () => {
  const md = formatMarkdown(report);

  test("includes a title and the generation date", () => {
    expect(md).toContain("# Secret Rotation Report");
    expect(md).toContain("2026-06-27");
  });

  test("renders a summary line with the per-urgency counts", () => {
    expect(md).toContain("Expired: 1");
    expect(md).toContain("Warning: 1");
    expect(md).toContain("OK: 1");
  });

  test("renders a section header and table row per urgency group", () => {
    expect(md).toContain("## Expired (1)");
    expect(md).toContain("## Warning (1)");
    expect(md).toContain("## OK (1)");
    // Table header columns.
    expect(md).toContain("| Secret | Last Rotated |");
    // A specific secret row with its services joined.
    expect(md).toContain("| DATABASE_PASSWORD |");
    expect(md).toContain("api, worker");
  });

  test("shows a friendly placeholder for an empty group", () => {
    const empty = generateReport(parseConfig({ secrets: [] }), NOW);
    const out = formatMarkdown(empty);
    expect(out).toContain("_None_");
  });
});

describe("formatReport dispatcher", () => {
  test("selects markdown by default", () => {
    expect(formatReport(report, "markdown")).toContain(
      "# Secret Rotation Report",
    );
  });

  test("selects JSON when requested", () => {
    expect(() => JSON.parse(formatReport(report, "json"))).not.toThrow();
  });

  test("throws on an unknown format", () => {
    // @ts-expect-error deliberately passing an invalid format at runtime
    expect(() => formatReport(report, "xml")).toThrow(/format/i);
  });
});
