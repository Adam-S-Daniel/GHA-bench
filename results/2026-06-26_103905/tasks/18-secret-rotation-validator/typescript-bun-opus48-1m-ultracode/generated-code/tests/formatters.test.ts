/**
 * Cycle 3 (red/green TDD): output formatters.
 *
 * Three formats are supported:
 *   - "json"     -> machine-readable, full report (pretty-printed)
 *   - "markdown" -> human-readable, urgency-grouped tables (job summary friendly)
 *   - "github"   -> key=value lines for `$GITHUB_OUTPUT` (step outputs)
 */
import { describe, expect, test } from "bun:test";
import { toJSON, toMarkdown, toGitHubOutput, formatReport } from "../src/formatters";
import { buildReport, parseDate } from "../src/validator";
import type { SecretConfig } from "../src/types";

const NOW = parseDate("2026-06-28");
const SECRETS: SecretConfig[] = [
  { name: "AWS_ACCESS_KEY", lastRotated: "2026-01-01", rotationPolicyDays: 90, requiredBy: ["api", "worker"] },
  { name: "DB_PASSWORD", lastRotated: "2026-05-01", rotationPolicyDays: 60, requiredBy: ["api"] },
  { name: "STRIPE_API_KEY", lastRotated: "2026-06-01", rotationPolicyDays: 90, requiredBy: ["billing"] },
  { name: "JWT_SIGNING_KEY", lastRotated: "2026-06-20", rotationPolicyDays: 30, requiredBy: ["auth"] },
];
const REPORT = buildReport(SECRETS, NOW, 14);

describe("toJSON", () => {
  test("round-trips to the exact report object", () => {
    expect(JSON.parse(toJSON(REPORT))).toEqual(REPORT);
  });

  test("is pretty-printed (multi-line, 2-space indent)", () => {
    const out = toJSON(REPORT);
    expect(out).toContain("\n");
    expect(out).toContain('  "summary": {');
  });
});

describe("toGitHubOutput", () => {
  test("emits exactly the four summary counters as key=value lines", () => {
    expect(toGitHubOutput(REPORT)).toBe("total=4\nexpired=1\nwarning=1\nok=2");
  });
});

describe("toMarkdown", () => {
  const md = toMarkdown(REPORT);

  test("has a title and the reference date + warning window", () => {
    expect(md).toContain("# Secret Rotation Report");
    expect(md).toContain("2026-06-28");
    expect(md).toContain("14");
  });

  test("renders one section per urgency with counts", () => {
    expect(md).toContain("## Expired (1)");
    expect(md).toContain("## Warning (1)");
    expect(md).toContain("## OK (2)");
  });

  test("shows the expired secret with its overdue day count and services", () => {
    // Signed days-left column: an expired secret is negative.
    expect(md).toMatch(/AWS_ACCESS_KEY .*\| 2026-04-01 \| -88 \| 90 \| api, worker/);
  });

  test("shows the warning secret row", () => {
    expect(md).toMatch(/DB_PASSWORD .*\| 2026-06-30 \| 2 \| 60 \| api/);
  });

  test("renders an em dash for a secret with no required-by services", () => {
    const r = buildReport(
      [{ name: "ORPHAN", lastRotated: "2026-06-01", rotationPolicyDays: 365, requiredBy: [] }],
      NOW,
      14,
    );
    expect(toMarkdown(r)).toMatch(/ORPHAN .*\| —/);
  });

  test("an empty urgency group renders a placeholder instead of an empty table", () => {
    const r = buildReport(
      [{ name: "FRESH", lastRotated: "2026-06-25", rotationPolicyDays: 365, requiredBy: ["x"] }],
      NOW,
      14,
    );
    const out = toMarkdown(r);
    expect(out).toContain("## Expired (0)");
    expect(out).toMatch(/## Expired \(0\)\n\n_None\._/);
  });
});

describe("formatReport dispatch", () => {
  test("routes to the requested format", () => {
    expect(formatReport(REPORT, "json")).toBe(toJSON(REPORT));
    expect(formatReport(REPORT, "markdown")).toBe(toMarkdown(REPORT));
    expect(formatReport(REPORT, "github")).toBe(toGitHubOutput(REPORT));
  });
});
