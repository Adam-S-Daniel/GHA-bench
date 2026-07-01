import { describe, expect, test } from "bun:test";
import { formatReport } from "./report";
import type { ComplianceReport } from "./types";

describe("formatReport", () => {
  test("renders a human-readable table with a status symbol per row and a summary line", () => {
    const report: ComplianceReport = {
      entries: [
        { name: "lodash", version: "4.17.21", license: "MIT", status: "approved" },
        { name: "badlib", version: "1.0.0", license: "GPL-3.0", status: "denied" },
        { name: "mystery", version: "0.0.1", license: null, status: "unknown" },
      ],
      summary: { total: 3, approved: 1, denied: 1, unknown: 1 },
    };

    const text = formatReport(report);

    expect(text).toContain("lodash@4.17.21");
    expect(text).toContain("MIT");
    expect(text).toContain("APPROVED");
    expect(text).toContain("badlib@1.0.0");
    expect(text).toContain("DENIED");
    expect(text).toContain("mystery@0.0.1");
    expect(text).toContain("UNKNOWN");
    expect(text).toContain("Total: 3");
    expect(text).toContain("Approved: 1");
    expect(text).toContain("Denied: 1");
    expect(text).toContain("Unknown: 1");
  });
});
