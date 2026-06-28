// Unit tests for the dependency license checker library.
//
// Methodology: red/green TDD. Each `describe` block was written as a failing
// test first, then the minimum implementation in `license-checker.ts` was added
// to make it pass, then refactored. The tests below are the accumulated suite.

import { test, expect, describe, mock } from "bun:test";
import {
  parseManifest,
  detectManifestType,
  checkLicense,
  generateReport,
  lookupFromDatabase,
  renderReport,
  runCli,
} from "./license-checker.ts";
import type {
  Dependency,
  LicenseConfig,
  LicenseLookup,
  ComplianceReport,
} from "./license-checker.ts";

describe("parseManifest - package.json", () => {
  test("extracts names and versions from dependencies and devDependencies", () => {
    const content = JSON.stringify({
      name: "my-app",
      version: "1.0.0",
      dependencies: { "left-pad": "^1.3.0", lodash: "4.17.21" },
      devDependencies: { typescript: "~5.4.0" },
    });

    const deps: Dependency[] = parseManifest(content, "package.json");

    expect(deps).toEqual([
      { name: "left-pad", version: "^1.3.0" },
      { name: "lodash", version: "4.17.21" },
      { name: "typescript", version: "~5.4.0" },
    ]);
  });

  test("returns an empty list when there are no dependency sections", () => {
    const deps = parseManifest(JSON.stringify({ name: "x", version: "1.0.0" }), "package.json");
    expect(deps).toEqual([]);
  });

  test("de-duplicates a dependency listed in multiple sections", () => {
    const content = JSON.stringify({
      dependencies: { lodash: "4.17.21" },
      devDependencies: { lodash: "4.0.0" },
    });
    const deps = parseManifest(content, "package.json");
    expect(deps).toEqual([{ name: "lodash", version: "4.17.21" }]);
  });

  test("throws a meaningful error on malformed JSON", () => {
    expect(() => parseManifest("{ not json", "package.json")).toThrow(
      /Failed to parse package\.json/,
    );
  });
});

describe("parseManifest - requirements.txt", () => {
  test("extracts names and version specifiers, ignoring comments and options", () => {
    const content = [
      "# project requirements",
      "requests==2.31.0",
      "flask>=2.0,<3.0",
      "rich   # nice output  (no version pin)",
      "requests[security]==2.31.0  # with extras",
      "",
      "-r other-requirements.txt",
      "--hash=sha256:abc",
    ].join("\n");

    const deps: Dependency[] = parseManifest(content, "requirements.txt");

    expect(deps).toEqual([
      { name: "requests", version: "==2.31.0" },
      { name: "flask", version: ">=2.0,<3.0" },
      { name: "rich", version: "" },
      { name: "requests", version: "==2.31.0" },
    ]);
  });
});

describe("detectManifestType", () => {
  test("detects package.json by filename", () => {
    expect(detectManifestType("package.json")).toBe("package.json");
    expect(detectManifestType("/repo/fixtures/package.json")).toBe("package.json");
  });

  test("detects requirements.txt by filename", () => {
    expect(detectManifestType("requirements.txt")).toBe("requirements.txt");
    expect(detectManifestType("/repo/requirements-dev.txt")).toBe("requirements.txt");
  });

  test("throws for an unrecognized manifest filename", () => {
    expect(() => detectManifestType("Gemfile")).toThrow(/Unsupported manifest/);
  });
});

describe("checkLicense", () => {
  const config: LicenseConfig = {
    allow: ["MIT", "Apache-2.0", "BSD-3-Clause"],
    deny: ["GPL-3.0", "AGPL-3.0"],
  };

  test("returns 'approved' for an allow-listed license", () => {
    expect(checkLicense("MIT", config)).toBe("approved");
  });

  test("returns 'denied' for a deny-listed license", () => {
    expect(checkLicense("GPL-3.0", config)).toBe("denied");
  });

  test("returns 'unknown' for a license on neither list", () => {
    expect(checkLicense("WTFPL", config)).toBe("unknown");
  });

  test("returns 'unknown' when the license is null or empty", () => {
    expect(checkLicense(null, config)).toBe("unknown");
    expect(checkLicense("", config)).toBe("unknown");
  });

  test("matches licenses case-insensitively", () => {
    expect(checkLicense("mit", config)).toBe("approved");
    expect(checkLicense("gpl-3.0", config)).toBe("denied");
  });

  test("deny-list takes precedence over allow-list", () => {
    const conflicting: LicenseConfig = { allow: ["MIT"], deny: ["MIT"] };
    expect(checkLicense("MIT", conflicting)).toBe("denied");
  });
});

describe("generateReport", () => {
  const config: LicenseConfig = {
    allow: ["MIT", "Apache-2.0"],
    deny: ["GPL-3.0"],
  };

  const deps: Dependency[] = [
    { name: "left-pad", version: "1.3.0" },
    { name: "evil-gpl", version: "2.0.0" },
    { name: "mystery-lib", version: "0.1.0" },
  ];

  test("uses the injected (mock) lookup and classifies every dependency", () => {
    // The license lookup is fully mocked so tests never touch the network.
    const lookup: LicenseLookup = mock((dep: Dependency): string | null => {
      const db: Record<string, string> = {
        "left-pad": "MIT",
        "evil-gpl": "GPL-3.0",
        // mystery-lib intentionally absent -> null -> unknown
      };
      return db[dep.name] ?? null;
    });

    const report: ComplianceReport = generateReport(deps, lookup, config);

    expect(lookup).toHaveBeenCalledTimes(3);
    expect(report.entries).toEqual([
      { name: "left-pad", version: "1.3.0", license: "MIT", status: "approved" },
      { name: "evil-gpl", version: "2.0.0", license: "GPL-3.0", status: "denied" },
      { name: "mystery-lib", version: "0.1.0", license: null, status: "unknown" },
    ]);
    expect(report.summary).toEqual({ total: 3, approved: 1, denied: 1, unknown: 1 });
    expect(report.compliant).toBe(false);
  });

  test("is compliant when there are no denied dependencies", () => {
    const lookup: LicenseLookup = () => "MIT";
    const report = generateReport(
      [{ name: "a", version: "1.0.0" }],
      lookup,
      config,
    );
    expect(report.summary).toEqual({ total: 1, approved: 1, denied: 0, unknown: 0 });
    expect(report.compliant).toBe(true);
  });
});

describe("lookupFromDatabase (mock-database lookup factory)", () => {
  const db = {
    "left-pad": "MIT",
    "left-pad@1.3.0": "MIT-0", // version-specific entry wins
    lodash: "MIT",
  };

  test("prefers a name@version entry over a name-only entry", () => {
    const lookup = lookupFromDatabase(db);
    expect(lookup({ name: "left-pad", version: "1.3.0" })).toBe("MIT-0");
  });

  test("falls back to a name-only entry", () => {
    const lookup = lookupFromDatabase(db);
    expect(lookup({ name: "lodash", version: "4.17.21" })).toBe("MIT");
  });

  test("returns null when the dependency is unknown to the database", () => {
    const lookup = lookupFromDatabase(db);
    expect(lookup({ name: "ghost", version: "9.9.9" })).toBeNull();
  });
});

describe("renderReport", () => {
  const report: ComplianceReport = {
    entries: [
      { name: "left-pad", version: "1.3.0", license: "MIT", status: "approved" },
      { name: "evil-gpl", version: "2.0.0", license: "GPL-3.0", status: "denied" },
      { name: "mystery-lib", version: "0.1.0", license: null, status: "unknown" },
    ],
    summary: { total: 3, approved: 1, denied: 1, unknown: 1 },
    compliant: false,
  };

  test("text format contains greppable per-dependency and summary lines", () => {
    const text = renderReport(report, "text");
    expect(text).toContain("[APPROVED] left-pad@1.3.0 (MIT)");
    expect(text).toContain("[DENIED] evil-gpl@2.0.0 (GPL-3.0)");
    expect(text).toContain("[UNKNOWN] mystery-lib@0.1.0 (no license found)");
    expect(text).toContain("SUMMARY total=3 approved=1 denied=1 unknown=1");
    expect(text).toContain("RESULT NON-COMPLIANT");
  });

  test("json format round-trips to the report object", () => {
    const json = renderReport(report, "json");
    expect(JSON.parse(json)).toEqual(report);
  });
});

describe("runCli", () => {
  // An in-memory virtual filesystem so CLI tests do not touch disk or network.
  const files: Record<string, string> = {
    "fixtures/package.json": JSON.stringify({
      dependencies: { "left-pad": "1.3.0", "evil-gpl": "2.0.0" },
      devDependencies: { "mystery-lib": "0.1.0" },
    }),
    "fixtures/config.json": JSON.stringify({
      allow: ["MIT", "Apache-2.0"],
      deny: ["GPL-3.0"],
    }),
    "fixtures/licenses.json": JSON.stringify({
      "left-pad": "MIT",
      "evil-gpl": "GPL-3.0",
    }),
  };
  const written: Record<string, string> = {};
  const io = {
    readText: async (path: string): Promise<string> => {
      if (!(path in files)) throw new Error(`ENOENT: ${path}`);
      return files[path] as string;
    },
    writeText: async (path: string, data: string): Promise<void> => {
      written[path] = data;
    },
  };

  test("produces a text report and exits 0 (non-strict, even with violations)", async () => {
    const res = await runCli(
      [
        "--manifest",
        "fixtures/package.json",
        "--config",
        "fixtures/config.json",
        "--licenses",
        "fixtures/licenses.json",
        "--format",
        "text",
      ],
      io,
    );

    expect(res.code).toBe(0);
    expect(res.stdout).toContain("[APPROVED] left-pad@1.3.0 (MIT)");
    expect(res.stdout).toContain("[DENIED] evil-gpl@2.0.0 (GPL-3.0)");
    expect(res.stdout).toContain("[UNKNOWN] mystery-lib@0.1.0 (no license found)");
    expect(res.stdout).toContain("SUMMARY total=3 approved=1 denied=1 unknown=1");
    expect(res.stdout).toContain("RESULT NON-COMPLIANT");
  });

  test("exits 1 in --strict mode when a dependency is denied", async () => {
    const res = await runCli(
      [
        "--manifest=fixtures/package.json",
        "--config=fixtures/config.json",
        "--licenses=fixtures/licenses.json",
        "--strict",
      ],
      io,
    );
    expect(res.code).toBe(1);
    expect(res.stderr).toContain("non-compliant");
  });

  test("emits JSON and writes it to --output", async () => {
    const res = await runCli(
      [
        "--manifest",
        "fixtures/package.json",
        "--config",
        "fixtures/config.json",
        "--licenses",
        "fixtures/licenses.json",
        "--format",
        "json",
        "--output",
        "report.json",
      ],
      io,
    );
    expect(res.code).toBe(0);
    const parsed = JSON.parse(written["report.json"] as string);
    expect(parsed.summary).toEqual({ total: 3, approved: 1, denied: 1, unknown: 1 });
  });

  test("exits 2 with a meaningful message when a required arg is missing", async () => {
    const res = await runCli(["--config", "fixtures/config.json"], io);
    expect(res.code).toBe(2);
    expect(res.stderr).toMatch(/--manifest/);
  });

  test("auto-detects and checks a requirements.txt manifest", async () => {
    const reqFiles: Record<string, string> = {
      "requirements.txt": "flask==2.3.0\nrequests==2.31.0\nshady-pkg==0.0.1\n",
      "fixtures/config.json": files["fixtures/config.json"] as string,
      "fixtures/licenses.json": JSON.stringify({
        flask: "MIT",
        requests: "Apache-2.0",
        "shady-pkg": "GPL-3.0",
      }),
    };
    const res = await runCli(
      [
        "--manifest",
        "requirements.txt",
        "--config",
        "fixtures/config.json",
        "--licenses",
        "fixtures/licenses.json",
      ],
      {
        readText: async (p: string) => {
          if (!(p in reqFiles)) throw new Error(`ENOENT: ${p}`);
          return reqFiles[p] as string;
        },
      },
    );
    expect(res.code).toBe(0);
    // requirements.txt version specifiers are kept verbatim, so the
    // "name@version" render shows the pip operator (e.g. flask@==2.3.0).
    expect(res.stdout).toContain("[APPROVED] flask@==2.3.0 (MIT)");
    expect(res.stdout).toContain("[APPROVED] requests@==2.31.0 (Apache-2.0)");
    expect(res.stdout).toContain("[DENIED] shady-pkg@==0.0.1 (GPL-3.0)");
    expect(res.stdout).toContain("SUMMARY total=3 approved=2 denied=1 unknown=0");
  });

  test("exits 2 with a meaningful message when a file cannot be read", async () => {
    const res = await runCli(
      [
        "--manifest",
        "fixtures/does-not-exist.json",
        "--config",
        "fixtures/config.json",
        "--licenses",
        "fixtures/licenses.json",
      ],
      io,
    );
    expect(res.code).toBe(2);
    expect(res.stderr).toMatch(/ENOENT|read/i);
  });
});
