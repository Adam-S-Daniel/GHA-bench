// RED: drive out a deterministic, machine-parseable rendering of the result.
import { describe, expect, test } from "bun:test";
import { renderResult } from "./render.ts";
import { assignLabels, type LabelRule } from "./label-assigner.ts";

const RULES: LabelRule[] = [
  { pattern: "docs/**", label: "documentation", priority: 10 },
  { pattern: "src/api/**", label: "api", priority: 30 },
];

describe("renderResult", () => {
  test("emits a stable LABELS= line and a count", () => {
    const result = assignLabels(["src/api/x.ts", "docs/y.md"], RULES);
    const out = renderResult(result, 2);
    expect(out).toContain("Changed files: 2");
    expect(out).toContain("LABELS=api,documentation");
    expect(out).toContain("LABEL_COUNT=2");
  });

  test("renders an explicit empty marker when nothing matched", () => {
    const result = assignLabels(["nope.bin"], RULES);
    const out = renderResult(result, 1);
    expect(out).toContain("LABELS=");
    expect(out).toContain("LABEL_COUNT=0");
    expect(out).toContain("UNMATCHED=nope.bin");
  });
});
