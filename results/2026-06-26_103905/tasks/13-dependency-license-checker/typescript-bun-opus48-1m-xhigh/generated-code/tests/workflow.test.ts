/**
 * Workflow tests.
 *
 * Two layers:
 *   1. "workflow structure" — fast, static checks on the YAML (triggers, jobs,
 *      script references, actionlint).
 *   2. "act pipeline" — every functional scenario is executed END-TO-END through
 *      the real GitHub Actions workflow via `act` in Docker. For each case we
 *      build a temp git repo, drop in that case's fixture data, run
 *      `act push --rm`, append the output to act-result.txt, and assert on the
 *      EXACT expected values.
 *
 * Run only the fast checks with:  bun test tests/workflow.test.ts -t "workflow structure"
 */
import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { parse } from "yaml";
import {
  cpSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
  appendFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const PROJECT_ROOT = process.cwd();
const WORKFLOW_PATH = join(PROJECT_ROOT, ".github/workflows/dependency-license-checker.yml");
const ACT_RESULT_PATH = join(PROJECT_ROOT, "act-result.txt");
const ACT_IMAGE = "act-ubuntu-pwsh:latest";

// ---------------------------------------------------------------------------
// Layer 1: static structure checks
// ---------------------------------------------------------------------------

describe("workflow structure", () => {
  const yamlText = readFileSync(WORKFLOW_PATH, "utf8");
  const parsed = parse(yamlText) as Record<string, unknown>;
  // YAML 1.2 keeps "on" as a string key, but guard against the 1.1 boolean form.
  const triggers = (parsed["on"] ?? (parsed as Record<string, unknown>)["true"]) as Record<
    string,
    unknown
  >;
  const jobs = parsed["jobs"] as Record<string, Record<string, unknown>>;

  test("declares the expected trigger events", () => {
    expect(triggers).toBeDefined();
    expect(Object.keys(triggers)).toEqual(
      expect.arrayContaining(["push", "pull_request", "schedule", "workflow_dispatch"]),
    );
  });

  test("declares least-privilege permissions", () => {
    expect(parsed["permissions"]).toEqual({ contents: "read" });
  });

  test("defines the license-check and compliance-gate jobs", () => {
    expect(Object.keys(jobs)).toEqual(
      expect.arrayContaining(["license-check", "compliance-gate"]),
    );
  });

  test("compliance-gate depends on license-check (job dependency)", () => {
    expect(jobs["compliance-gate"]!["needs"]).toBe("license-check");
  });

  test("checks out the repository with actions/checkout@v4", () => {
    const steps = jobs["license-check"]!["steps"] as Array<Record<string, unknown>>;
    const uses = steps.map((s) => s["uses"]).filter(Boolean);
    expect(uses).toContain("actions/checkout@v4");
  });

  test("references the checker script (src/app.ts)", () => {
    expect(yamlText).toContain("src/app.ts");
  });

  test("references files that actually exist on disk", () => {
    for (const rel of [
      "src/app.ts",
      "src/lib.ts",
      "fixtures/ci/manifest.json",
      "fixtures/ci/policy.json",
      "fixtures/ci/licenses.json",
    ]) {
      expect(existsSync(join(PROJECT_ROOT, rel))).toBe(true);
    }
  });

  test("passes actionlint cleanly (exit code 0)", () => {
    const proc = Bun.spawnSync(["actionlint", WORKFLOW_PATH], { cwd: PROJECT_ROOT });
    if (proc.exitCode !== 0) {
      console.error(proc.stdout.toString(), proc.stderr.toString());
    }
    expect(proc.exitCode).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// Layer 2: end-to-end execution through `act`
// ---------------------------------------------------------------------------

/** Shared org policy + mocked license database used by all act cases. */
const POLICY_JSON = JSON.stringify(
  { allow: ["MIT", "Apache-2.0", "BSD-3-Clause", "ISC"], deny: ["GPL-3.0", "GPL-2.0", "AGPL-3.0"] },
  null,
  2,
);
const LICENSES_JSON = JSON.stringify(
  {
    express: "MIT",
    lodash: "MIT",
    chalk: "MIT",
    "copyleft-lib": "GPL-3.0",
    "left-pad": "WTFPL",
  },
  null,
  2,
);

interface ActCase {
  name: string;
  /** package.json content written to fixtures/ci/manifest.json. */
  manifest: string;
  /** Exact per-dependency report lines expected in the act output. */
  expectedLines: string[];
  /** Exact text-report SUMMARY line. */
  expectedSummary: string;
  /** Exact COMPLIANT line. */
  expectedCompliant: string;
  /** Exact "Compliance summary:" line echoed by the gate job (validates outputs). */
  expectedGateSummary: string;
  /** Exact gate decision line. */
  expectedGateDecision: string;
}

const CASES: ActCase[] = [
  {
    name: "compliant",
    manifest: JSON.stringify(
      {
        name: "acme-web",
        version: "2.0.0",
        dependencies: { express: "^4.18.2", lodash: "~4.17.21" },
        devDependencies: { chalk: "5.3.0" },
      },
      null,
      2,
    ),
    expectedLines: [
      "- chalk@5.3.0 [approved] license=MIT",
      "- express@4.18.2 [approved] license=MIT",
      "- lodash@4.17.21 [approved] license=MIT",
    ],
    expectedSummary: "SUMMARY total=3 approved=3 denied=0 unknown=0",
    expectedCompliant: "COMPLIANT=true",
    expectedGateSummary: "Compliance summary: total=3 approved=3 denied=0 unknown=0 compliant=true",
    expectedGateDecision: "GATE: PASS - no denied licenses detected.",
  },
  {
    name: "violations",
    manifest: JSON.stringify(
      {
        name: "acme-api",
        version: "1.0.0",
        dependencies: {
          express: "^4.18.2",
          "copyleft-lib": "1.0.0",
          "left-pad": "1.3.0",
          "mystery-pkg": "2.0.0",
        },
      },
      null,
      2,
    ),
    expectedLines: [
      "- copyleft-lib@1.0.0 [denied] license=GPL-3.0",
      "- express@4.18.2 [approved] license=MIT",
      "- left-pad@1.3.0 [unknown] license=WTFPL",
      "- mystery-pkg@2.0.0 [unknown] license=UNKNOWN",
    ],
    expectedSummary: "SUMMARY total=4 approved=1 denied=1 unknown=2",
    expectedCompliant: "COMPLIANT=false",
    expectedGateSummary: "Compliance summary: total=4 approved=1 denied=1 unknown=2 compliant=false",
    expectedGateDecision:
      "GATE: REVIEW - denied licenses present (reported, not blocking in report mode).",
  },
];

/** Remove ANSI color codes so substring assertions are reliable. */
function stripAnsi(s: string): string {
  // eslint-disable-next-line no-control-regex
  return s.replace(/\x1b\[[0-9;]*m/g, "");
}

/** Build an isolated git repo containing the project + this case's fixtures. */
function setupCaseRepo(c: ActCase): string {
  const repo = mkdtempSync(join(tmpdir(), `dlc-${c.name}-`));

  // Copy the pieces of the project the workflow needs.
  cpSync(join(PROJECT_ROOT, "src"), join(repo, "src"), { recursive: true });
  cpSync(join(PROJECT_ROOT, ".github"), join(repo, ".github"), { recursive: true });
  for (const f of ["package.json", "tsconfig.json"]) {
    cpSync(join(PROJECT_ROOT, f), join(repo, f));
  }

  // Drop in this case's fixture data at the paths the workflow reads.
  const fixturesDir = join(repo, "fixtures", "ci");
  mkdirSync(fixturesDir, { recursive: true });
  writeFileSync(join(fixturesDir, "manifest.json"), c.manifest);
  writeFileSync(join(fixturesDir, "policy.json"), POLICY_JSON);
  writeFileSync(join(fixturesDir, "licenses.json"), LICENSES_JSON);

  // Initialize a git repo and commit (act needs a HEAD commit for the push event).
  const git = (args: string[]) => {
    const p = Bun.spawnSync(["git", ...args], { cwd: repo });
    if (p.exitCode !== 0) {
      throw new Error(`git ${args.join(" ")} failed: ${p.stderr.toString()}`);
    }
  };
  git(["init", "-b", "main"]);
  git(["add", "-A"]);
  git(["-c", "user.email=ci@example.com", "-c", "user.name=CI", "commit", "-m", `case ${c.name}`]);

  return repo;
}

describe("act pipeline (end-to-end through GitHub Actions)", () => {
  // Start each full run with a fresh artifact file.
  beforeAll(() => {
    writeFileSync(ACT_RESULT_PATH, `# act-result.txt — generated ${"by bun test"}\n`);
  });

  const createdRepos: string[] = [];
  afterAll(() => {
    for (const r of createdRepos) {
      try {
        rmSync(r, { recursive: true, force: true });
      } catch {
        /* best-effort cleanup */
      }
    }
  });

  for (const c of CASES) {
    test(
      `case "${c.name}" runs through act and produces the expected report`,
      () => {
        const repo = setupCaseRepo(c);
        createdRepos.push(repo);

        // Execute the workflow exactly as CI would: a push event in Docker.
        const proc = Bun.spawnSync(
          ["act", "push", "--rm", "--pull=false", "-P", `ubuntu-latest=${ACT_IMAGE}`],
          { cwd: repo, env: process.env },
        );
        const output = stripAnsi(`${proc.stdout.toString()}\n${proc.stderr.toString()}`);

        // Persist the full output as the required artifact, clearly delimited.
        appendFileSync(
          ACT_RESULT_PATH,
          [
            "",
            "================================================================",
            `CASE: ${c.name}`,
            `ACT EXIT CODE: ${proc.exitCode}`,
            "----------------------------------------------------------------",
            output,
            "================================================================",
            "",
          ].join("\n"),
        );

        // 1. act must succeed.
        expect(proc.exitCode).toBe(0);

        // 2. Both jobs must report success.
        const jobSucceeded = output.match(/Job succeeded/g) ?? [];
        expect(jobSucceeded.length).toBeGreaterThanOrEqual(2);

        // 3. Exact per-dependency report lines.
        for (const line of c.expectedLines) {
          expect(output).toContain(line);
        }

        // 4. Exact summary + compliance lines from the text report.
        expect(output).toContain(c.expectedSummary);
        expect(output).toContain(c.expectedCompliant);

        // 5. Exact gate output — validates job outputs flowed across the
        //    job dependency with the right values.
        expect(output).toContain(c.expectedGateSummary);
        expect(output).toContain(c.expectedGateDecision);
      },
      300_000, // up to 5 minutes per case (container startup + run)
    );
  }

  test("act-result.txt artifact exists and contains every case", () => {
    expect(existsSync(ACT_RESULT_PATH)).toBe(true);
    const contents = readFileSync(ACT_RESULT_PATH, "utf8");
    for (const c of CASES) {
      expect(contents).toContain(`CASE: ${c.name}`);
    }
  });
});
