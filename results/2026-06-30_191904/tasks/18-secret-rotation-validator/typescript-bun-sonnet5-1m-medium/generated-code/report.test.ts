import { describe, expect, test } from "bun:test";
import { formatReport } from "./report.ts";
import type { RotationReport } from "./types.ts";

const SAMPLE_REPORT: RotationReport = {
  generatedAt: "2026-07-01T00:00:00.000Z",
  warningWindowDays: 14,
  expired: [
    {
      name: "db-password",
      requiredBy: ["api-service"],
      lastRotated: "2026-01-01",
      rotationPolicyDays: 90,
      daysSinceRotation: 181,
      daysUntilExpiry: -91,
      urgency: "expired",
    },
  ],
  warning: [
    {
      name: "api-key",
      requiredBy: ["billing-service"],
      lastRotated: "2026-04-12",
      rotationPolicyDays: 90,
      daysSinceRotation: 80,
      daysUntilExpiry: 10,
      urgency: "warning",
    },
  ],
  ok: [
    {
      name: "tls-cert",
      requiredBy: ["edge-proxy"],
      lastRotated: "2026-06-21",
      rotationPolicyDays: 90,
      daysSinceRotation: 10,
      daysUntilExpiry: 80,
      urgency: "ok",
    },
  ],
};

describe("formatReport JSON output", () => {
  test("serializes the report as pretty-printed JSON matching the input shape", () => {
    const output = formatReport(SAMPLE_REPORT, "json");
    const parsed = JSON.parse(output);

    expect(parsed).toEqual(SAMPLE_REPORT);
  });
});

describe("formatReport markdown output", () => {
  test("renders a markdown table with a row per secret and urgency emoji headers", () => {
    const output = formatReport(SAMPLE_REPORT, "markdown");

    expect(output).toContain("# Secret Rotation Report");
    expect(output).toContain("## Expired (1)");
    expect(output).toContain("## Warning (1)");
    expect(output).toContain("## OK (1)");
    expect(output).toContain("| db-password | -91 |");
    expect(output).toContain("| api-key | 10 |");
    expect(output).toContain("| tls-cert | 80 |");
    expect(output).toContain("api-service");
  });

  test("omits a bucket's table when it has no secrets", () => {
    const emptyOkReport: RotationReport = { ...SAMPLE_REPORT, ok: [] };

    const output = formatReport(emptyOkReport, "markdown");

    expect(output).toContain("## OK (0)");
    expect(output).not.toContain("| tls-cert |");
  });
});

describe("formatReport error handling", () => {
  test("throws a clear error for an unsupported format", () => {
    // @ts-expect-error intentionally invalid format to test the runtime guard
    expect(() => formatReport(SAMPLE_REPORT, "xml")).toThrow(/Unsupported output format/);
  });
});
