/**
 * Unit tests for the dependency-license-checker core library.
 *
 * These tests drive the design via red/green TDD. Cycle 1 (this commit) covers
 * manifest parsing: turning a package.json / requirements.txt into a normalized
 * list of `{ name, version }` dependencies.
 */
import { describe, expect, mock, test } from "bun:test";
import {
  parsePackageJson,
  parseRequirementsTxt,
  parseManifest,
  classifyLicense,
  buildReport,
  createLookupFromMap,
  loadPolicy,
  formatReportText,
  formatReportJson,
  formatReportKv,
  type Dependency,
  type LicensePolicy,
  type LicenseLookup,
} from "../src/lib";

describe("parsePackageJson", () => {
  test("extracts and merges dependencies + devDependencies, normalizing version ranges", () => {
    const content = JSON.stringify({
      name: "demo",
      version: "1.0.0",
      dependencies: { express: "^4.18.2", "left-pad": "~1.3.0" },
      devDependencies: { typescript: ">=5.0.0" },
    });

    const deps: Dependency[] = parsePackageJson(content);

    // Sorted by name for deterministic reports; range operators stripped.
    expect(deps).toEqual([
      { name: "express", version: "4.18.2" },
      { name: "left-pad", version: "1.3.0" },
      { name: "typescript", version: "5.0.0" },
    ]);
  });

  test("includes peerDependencies and optionalDependencies", () => {
    const content = JSON.stringify({
      peerDependencies: { react: "18.2.0" },
      optionalDependencies: { fsevents: "*" },
    });

    const deps = parsePackageJson(content);

    expect(deps).toEqual([
      { name: "fsevents", version: "*" },
      { name: "react", version: "18.2.0" },
    ]);
  });

  test("returns an empty array when there are no dependency sections", () => {
    expect(parsePackageJson(JSON.stringify({ name: "x" }))).toEqual([]);
  });

  test("throws a meaningful error on malformed JSON", () => {
    expect(() => parsePackageJson("{ not json ")).toThrow(/invalid package\.json/i);
  });
});

describe("parseRequirementsTxt", () => {
  test("parses pinned, ranged, and unversioned requirements", () => {
    const content = [
      "# a comment",
      "",
      "requests==2.31.0",
      "flask>=2.0,<3.0",
      "numpy~=1.26.0",
      "rich",
      "  django == 4.2  ",
    ].join("\n");

    const deps = parseRequirementsTxt(content);

    expect(deps).toEqual([
      { name: "django", version: "4.2" },
      { name: "flask", version: "2.0" },
      { name: "numpy", version: "1.26.0" },
      { name: "requests", version: "2.31.0" },
      { name: "rich", version: "*" },
    ]);
  });

  test("ignores comments, blank lines, and pip option lines", () => {
    const content = ["-r base.txt", "--index-url https://x", "# nope", ""].join("\n");
    expect(parseRequirementsTxt(content)).toEqual([]);
  });

  test("strips extras like requests[security]", () => {
    expect(parseRequirementsTxt("requests[security]==2.31.0")).toEqual([
      { name: "requests", version: "2.31.0" },
    ]);
  });
});

describe("parseManifest", () => {
  test("dispatches to the package.json parser by filename", () => {
    const content = JSON.stringify({ dependencies: { a: "1.0.0" } });
    expect(parseManifest(content, "package.json")).toEqual([{ name: "a", version: "1.0.0" }]);
  });

  test("treats any .json manifest as npm package.json format", () => {
    const content = JSON.stringify({ dependencies: { a: "1.0.0" } });
    expect(parseManifest(content, "fixtures/ci/manifest.json")).toEqual([
      { name: "a", version: "1.0.0" },
    ]);
  });

  test("dispatches to the requirements parser by filename", () => {
    expect(parseManifest("a==1.0.0", "requirements.txt")).toEqual([
      { name: "a", version: "1.0.0" },
    ]);
  });

  test("throws for unsupported manifest types", () => {
    expect(() => parseManifest("x", "Gemfile")).toThrow(/unsupported manifest/i);
  });
});

// ---------------------------------------------------------------------------
// Cycle 2: license classification, report building (mocked lookup), formatting.
// ---------------------------------------------------------------------------

const POLICY: LicensePolicy = {
  allow: ["MIT", "Apache-2.0", "BSD-3-Clause"],
  deny: ["GPL-3.0", "AGPL-3.0"],
};

describe("classifyLicense", () => {
  test("approves licenses on the allow-list (case-insensitive)", () => {
    expect(classifyLicense("MIT", POLICY)).toBe("approved");
    expect(classifyLicense("mit", POLICY)).toBe("approved");
  });

  test("denies licenses on the deny-list", () => {
    expect(classifyLicense("GPL-3.0", POLICY)).toBe("denied");
  });

  test("treats deny-list as higher priority than allow-list", () => {
    const conflicting: LicensePolicy = { allow: ["MIT"], deny: ["MIT"] };
    expect(classifyLicense("MIT", conflicting)).toBe("denied");
  });

  test("reports unknown for licenses on neither list", () => {
    expect(classifyLicense("WTFPL", POLICY)).toBe("unknown");
  });

  test("reports unknown for a missing/null license", () => {
    expect(classifyLicense(null, POLICY)).toBe("unknown");
    expect(classifyLicense("", POLICY)).toBe("unknown");
  });
});

describe("buildReport (with a mocked license lookup)", () => {
  const deps: Dependency[] = [
    { name: "express", version: "4.18.2" },
    { name: "gpl-pkg", version: "1.0.0" },
    { name: "mystery", version: "2.0.0" },
  ];

  test("classifies every dependency and summarizes the result", () => {
    // The license lookup is fully mocked — no network, deterministic.
    const lookup = mock<LicenseLookup>((dep: Dependency) => {
      const table: Record<string, string | null> = {
        express: "MIT",
        "gpl-pkg": "GPL-3.0",
        mystery: null,
      };
      return table[dep.name] ?? null;
    });

    const report = buildReport(deps, lookup, POLICY);

    expect(lookup).toHaveBeenCalledTimes(3);
    expect(report.entries).toEqual([
      { name: "express", version: "4.18.2", license: "MIT", status: "approved" },
      { name: "gpl-pkg", version: "1.0.0", license: "GPL-3.0", status: "denied" },
      { name: "mystery", version: "2.0.0", license: null, status: "unknown" },
    ]);
    expect(report.summary).toEqual({ total: 3, approved: 1, denied: 1, unknown: 1 });
    expect(report.compliant).toBe(false);
  });

  test("is compliant when nothing is denied", () => {
    const lookup: LicenseLookup = () => "MIT";
    const report = buildReport(deps, lookup, POLICY);
    expect(report.summary.denied).toBe(0);
    expect(report.compliant).toBe(true);
  });
});

describe("createLookupFromMap (file-backed mock used by CI)", () => {
  const lookup = createLookupFromMap({
    "express@4.18.2": "MIT",
    "gpl-pkg": "GPL-3.0",
  });

  test("matches by exact name@version first", () => {
    expect(lookup({ name: "express", version: "4.18.2" })).toBe("MIT");
  });

  test("falls back to a name-only match", () => {
    expect(lookup({ name: "gpl-pkg", version: "9.9.9" })).toBe("GPL-3.0");
  });

  test("returns null when the package is absent", () => {
    expect(lookup({ name: "nope", version: "1.0.0" })).toBeNull();
  });
});

describe("loadPolicy", () => {
  test("parses allow and deny lists", () => {
    expect(loadPolicy(JSON.stringify({ allow: ["MIT"], deny: ["GPL-3.0"] }))).toEqual({
      allow: ["MIT"],
      deny: ["GPL-3.0"],
    });
  });

  test("defaults missing lists to empty arrays", () => {
    expect(loadPolicy(JSON.stringify({ allow: ["MIT"] }))).toEqual({ allow: ["MIT"], deny: [] });
  });

  test("throws on malformed config JSON", () => {
    expect(() => loadPolicy("{bad")).toThrow(/invalid.*config/i);
  });

  test("throws when allow/deny are not arrays", () => {
    expect(() => loadPolicy(JSON.stringify({ allow: "MIT" }))).toThrow(/must be an array/i);
  });
});

describe("formatReportText", () => {
  const lookup: LicenseLookup = (dep) =>
    ({ express: "MIT", "gpl-pkg": "GPL-3.0", mystery: null }[dep.name] ?? null);
  const report = buildReport(
    [
      { name: "express", version: "4.18.2" },
      { name: "gpl-pkg", version: "1.0.0" },
      { name: "mystery", version: "2.0.0" },
    ],
    lookup,
    POLICY,
  );
  const text = formatReportText(report);

  test("renders one greppable line per dependency", () => {
    expect(text).toContain("- express@4.18.2 [approved] license=MIT");
    expect(text).toContain("- gpl-pkg@1.0.0 [denied] license=GPL-3.0");
    expect(text).toContain("- mystery@2.0.0 [unknown] license=UNKNOWN");
  });

  test("renders an exact summary and compliance line", () => {
    expect(text).toContain("SUMMARY total=3 approved=1 denied=1 unknown=1");
    expect(text).toContain("COMPLIANT=false");
  });
});

describe("formatReportJson", () => {
  test("round-trips the report through JSON", () => {
    const report = buildReport([{ name: "a", version: "1.0.0" }], () => "MIT", POLICY);
    expect(JSON.parse(formatReportJson(report))).toEqual(report);
  });
});

describe("formatReportKv", () => {
  test("emits GITHUB_OUTPUT-compatible key=value lines", () => {
    const lookup: LicenseLookup = (dep) =>
      ({ express: "MIT", "gpl-pkg": "GPL-3.0", mystery: null }[dep.name] ?? null);
    const report = buildReport(
      [
        { name: "express", version: "4.18.2" },
        { name: "gpl-pkg", version: "1.0.0" },
        { name: "mystery", version: "2.0.0" },
      ],
      lookup,
      POLICY,
    );
    expect(formatReportKv(report)).toBe(
      ["total=3", "approved=1", "denied=1", "unknown=1", "compliant=false"].join("\n"),
    );
  });
});
