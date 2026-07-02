// RED/GREEN cycle 1: license classification against allow/deny lists.
// Rules under test:
//   - license on the deny-list  -> "denied"  (deny always wins over allow)
//   - license on the allow-list -> "approved"
//   - anything else (including a missing license) -> "unknown"
import { describe, expect, test } from "bun:test";
import { checkLicense } from "../src/check";
import type { LicenseConfig } from "../src/types";

const config: LicenseConfig = {
  allow: ["MIT", "Apache-2.0", "BSD-3-Clause", "ISC"],
  deny: ["GPL-3.0-only", "AGPL-3.0-only"],
};

describe("checkLicense", () => {
  test("returns 'approved' for an allow-listed license", () => {
    expect(checkLicense("MIT", config)).toBe("approved");
  });

  test("returns 'denied' for a deny-listed license", () => {
    expect(checkLicense("GPL-3.0-only", config)).toBe("denied");
  });

  test("returns 'unknown' for a license on neither list", () => {
    expect(checkLicense("WTFPL", config)).toBe("unknown");
  });

  test("returns 'unknown' when the license could not be resolved", () => {
    expect(checkLicense(undefined, config)).toBe("unknown");
  });

  test("deny-list wins when a license appears on both lists", () => {
    const both: LicenseConfig = { allow: ["MIT"], deny: ["MIT"] };
    expect(checkLicense("MIT", both)).toBe("denied");
  });
});
