import { describe, expect, test } from "bun:test";
import { classifyLicense } from "../src/classify";
import type { LicenseConfig } from "../src/types";

// RED: fails until src/classify.ts exports classifyLicense.
const config: LicenseConfig = {
  allowlist: ["MIT", "Apache-2.0", "BSD-3-Clause"],
  denylist: ["GPL-3.0", "AGPL-3.0"],
};

describe("classifyLicense", () => {
  test("returns approved for a license on the allowlist", () => {
    expect(classifyLicense("MIT", config)).toBe("approved");
  });

  test("returns denied for a license on the denylist", () => {
    expect(classifyLicense("GPL-3.0", config)).toBe("denied");
  });

  test("returns unknown for a license on neither list", () => {
    expect(classifyLicense("WTFPL", config)).toBe("unknown");
  });

  test("returns unknown for a null license", () => {
    expect(classifyLicense(null, config)).toBe("unknown");
  });

  test("matches license identifiers case-insensitively", () => {
    expect(classifyLicense("mit", config)).toBe("approved");
    expect(classifyLicense("gpl-3.0", config)).toBe("denied");
  });

  test("denylist takes precedence when a license appears on both lists", () => {
    const conflicting: LicenseConfig = {
      allowlist: ["MIT", "GPL-3.0"],
      denylist: ["GPL-3.0"],
    };
    expect(classifyLicense("GPL-3.0", conflicting)).toBe("denied");
  });
});
