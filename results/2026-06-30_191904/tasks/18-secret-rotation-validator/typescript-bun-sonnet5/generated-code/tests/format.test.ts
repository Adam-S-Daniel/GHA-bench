// Red/green TDD step 5: render a RotationReport as markdown or JSON.
import { describe, expect, test } from "bun:test";
import { formatJson, formatMarkdown } from "../src/format.ts";
import { generateReport } from "../src/report.ts";
import type { SecretsConfig } from "../src/types.ts";

const NOW: Date = new Date("2026-07-01T00:00:00.000Z");

const config: SecretsConfig = {
  warningWindowDays: 14,
  secrets: [
    { name: "tls-cert", lastRotated: "2026-06-01", rotationPolicyDays: 90, requiredBy: ["web"] },
    { name: "api-key", lastRotated: "2026-04-12", rotationPolicyDays: 90, requiredBy: ["api"] },
    {
      name: "db-password",
      lastRotated: "2026-03-23",
      rotationPolicyDays: 90,
      requiredBy: ["db", "backup"],
    },
  ],
};

describe("formatMarkdown", () => {
  const markdown: string = formatMarkdown(generateReport(config, NOW));

  test("includes a top-level heading and summary line", () => {
    expect(markdown).toContain("# Secret Rotation Report");
    expect(markdown).toContain("Warning window: 14 days");
    expect(markdown).toContain("Total secrets: 3");
  });

  test("has a section per urgency bucket with counts", () => {
    expect(markdown).toContain("## Expired (1)");
    expect(markdown).toContain("## Warning (1)");
    expect(markdown).toContain("## OK (1)");
  });

  test("renders each secret as a markdown table row with its computed fields", () => {
    expect(markdown).toContain("| db-password | 2026-03-23 | 90 | -10 | db, backup |");
    expect(markdown).toContain("| api-key | 2026-04-12 | 90 | 10 | api |");
    expect(markdown).toContain("| tls-cert | 2026-06-01 | 90 | 60 | web |");
  });

  test("renders '_None_' for an empty bucket instead of an empty table", () => {
    const emptyReport = generateReport({ warningWindowDays: 14, secrets: [] }, NOW);
    const md = formatMarkdown(emptyReport);
    expect(md).toContain("## Expired (0)\n\n_None_");
    expect(md).toContain("## Warning (0)\n\n_None_");
    expect(md).toContain("## OK (0)\n\n_None_");
  });
});

describe("formatJson", () => {
  test("round-trips the report through JSON.parse with all fields intact", () => {
    const report = generateReport(config, NOW);
    const parsed = JSON.parse(formatJson(report));
    expect(parsed).toEqual(JSON.parse(JSON.stringify(report)));
  });

  test("is grouped by urgency under expired/warning/ok keys", () => {
    const report = generateReport(config, NOW);
    const parsed = JSON.parse(formatJson(report));
    expect(parsed.expired).toHaveLength(1);
    expect(parsed.warning).toHaveLength(1);
    expect(parsed.ok).toHaveLength(1);
    expect(parsed.expired[0].name).toBe("db-password");
  });
});
