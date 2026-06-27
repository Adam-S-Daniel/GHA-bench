// TDD: tests for rendering a rotation report into output formats.
import { describe, expect, test } from "bun:test";
import { validateSecrets } from "../src/validator";
import { renderJson, renderMarkdown, renderReport } from "../src/report";
import type { Secret } from "../src/types";

const NOW = new Date("2026-06-27T00:00:00.000Z");

const SECRETS: Secret[] = [
  {
    name: "ok-secret",
    lastRotated: "2026-06-01T00:00:00.000Z",
    rotationPolicyDays: 90,
    requiredBy: ["api"],
  },
  {
    name: "warn-secret",
    lastRotated: "2026-04-08T00:00:00.000Z",
    rotationPolicyDays: 90,
    requiredBy: ["api", "worker"],
  },
  {
    name: "expired-secret",
    lastRotated: "2026-01-01T00:00:00.000Z",
    rotationPolicyDays: 90,
    requiredBy: ["billing"],
  },
];

function report() {
  return validateSecrets(SECRETS, { now: NOW, warningWindowDays: 14 });
}

describe("renderJson", () => {
  test("produces valid, parseable JSON preserving the report shape", () => {
    const out = renderJson(report());
    const parsed = JSON.parse(out);
    expect(parsed.summary).toEqual({ total: 3, expired: 1, warning: 1, ok: 1 });
    expect(parsed.warningWindowDays).toBe(14);
    expect(parsed.secrets).toHaveLength(3);
    // requiredBy must round-trip as an array.
    const warn = parsed.secrets.find((s: any) => s.name === "warn-secret");
    expect(warn.requiredBy).toEqual(["api", "worker"]);
  });
});

describe("renderMarkdown", () => {
  test("includes a summary line with counts", () => {
    const out = renderMarkdown(report());
    expect(out).toContain("**Expired:** 1");
    expect(out).toContain("**Warning:** 1");
    expect(out).toContain("**OK:** 1");
  });

  test("renders a markdown table with a header and one row per secret", () => {
    const out = renderMarkdown(report());
    expect(out).toContain("| Secret | Urgency | Last Rotated | Policy (days) | Days Until Expiry | Required By |");
    expect(out).toContain("| --- | --- | --- | --- | --- | --- |");
    // Expired secret should render its negative days-until-expiry.
    expect(out).toContain("| expired-secret | expired |");
    expect(out).toContain("| api, worker |");
  });

  test("emits an emoji-free section header for each urgency group", () => {
    const out = renderMarkdown(report());
    expect(out).toContain("## Expired");
    expect(out).toContain("## Warning");
    expect(out).toContain("## OK");
  });
});

describe("renderReport", () => {
  test("dispatches on format name", () => {
    const r = report();
    expect(renderReport(r, "json")).toBe(renderJson(r));
    expect(renderReport(r, "markdown")).toBe(renderMarkdown(r));
  });

  test("throws on an unknown format", () => {
    expect(() => renderReport(report(), "xml" as any)).toThrow(/unknown.*format/i);
  });
});
