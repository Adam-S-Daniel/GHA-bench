/**
 * TDD Cycle 4: output formats.
 *
 * The markdown format is the "notification" view: one section per urgency
 * bucket (EXPIRED / WARNING / OK) with a table of affected secrets. The JSON
 * format is the machine-readable view: the full report, pretty-printed.
 * Both are asserted on exact strings so the act pipeline can do the same.
 */
import { describe, expect, test } from "bun:test";
import { formatJson, formatMarkdown, formatReport } from "../src/format";
import { generateReport } from "../src/report";
import type { SecretConfig } from "../src/types";

const SECRETS: SecretConfig[] = [
  {
    name: "db-password",
    lastRotated: "2026-01-01",
    rotationPolicyDays: 90,
    requiredBy: ["auth-service", "billing-api"],
  },
  {
    name: "api-key-stripe",
    lastRotated: "2026-05-01",
    rotationPolicyDays: 70,
    requiredBy: ["billing-api"],
  },
];

const report = generateReport(SECRETS, {
  referenceDate: "2026-07-02",
  warningWindowDays: 14,
});

describe("formatMarkdown", () => {
  const md = formatMarkdown(report);

  test("starts with a title and the evaluation parameters", () => {
    expect(md).toStartWith("# Secret Rotation Report");
    expect(md).toContain(
      "_Reference date: 2026-07-02 · Warning window: 14 days_",
    );
  });

  test("renders one section per urgency with counts", () => {
    expect(md).toContain("## EXPIRED (1)");
    expect(md).toContain("## WARNING (1)");
    expect(md).toContain("## OK (0)");
  });

  test("renders exact table rows for affected secrets", () => {
    expect(md).toContain(
      "| Secret | Last Rotated | Policy (days) | Expires On | Days Until Expiry | Required By |",
    );
    expect(md).toContain(
      "| db-password | 2026-01-01 | 90 | 2026-04-01 | -92 | auth-service, billing-api |",
    );
    expect(md).toContain(
      "| api-key-stripe | 2026-05-01 | 70 | 2026-07-10 | 8 | billing-api |",
    );
  });

  test("renders empty buckets as '_None_' instead of an empty table", () => {
    const okSection = md.split("## OK (0)")[1]!;
    expect(okSection).toContain("_None_");
    expect(okSection).not.toContain("| Secret |");
  });
});

describe("formatJson", () => {
  test("round-trips to the exact report object", () => {
    expect(JSON.parse(formatJson(report))).toEqual(
      JSON.parse(JSON.stringify(report)),
    );
  });

  test("is pretty-printed with a summary block for grep-ability in CI", () => {
    const json = formatJson(report);
    expect(json).toContain(`"expired": 1,`);
    expect(json).toContain(`"warning": 1,`);
    expect(json).toContain(`"ok": 0`);
  });
});

describe("formatReport dispatcher", () => {
  test("selects the format by name", () => {
    expect(formatReport(report, "markdown")).toBe(formatMarkdown(report));
    expect(formatReport(report, "json")).toBe(formatJson(report));
  });

  test("rejects unknown formats with the supported list", () => {
    // @ts-expect-error deliberately wrong on purpose
    expect(() => formatReport(report, "xml")).toThrow(
      /unknown format "xml" \(supported: markdown, json\)/,
    );
  });
});
