/**
 * End-to-end acceptance tests: every behavioral case is executed *through the
 * GitHub Actions workflow* via `act push --rm` in a Docker container — never by
 * calling the script directly. Each case asserts on EXACT expected values
 * derived from the fixture data (not just "some output appeared").
 *
 * The two `act` invocations run once at module load (synchronous spawnSync), so
 * the assertions below are fast and the expensive container runs happen exactly
 * once per case. All output is appended to act-result.txt (the required
 * deliverable artifact), clearly delimited per case.
 *
 * Determinism: the workflow pins ROTATION_NOW=2026-06-28, so each fixture maps
 * to a single known-good report regardless of when CI runs.
 */
import { describe, expect, test } from "bun:test";
import { existsSync, readFileSync } from "node:fs";
import {
  runActCase,
  resetResult,
  countJobSucceeded,
  ACT_RESULT_PATH,
  type ActRun,
} from "./act-harness";

// --- Fixtures under test ----------------------------------------------------

// Mixed: one expired, one warning, two ok (evaluated as of 2026-06-28).
const MIXED_FIXTURE = JSON.stringify(
  {
    secrets: [
      { name: "AWS_ACCESS_KEY", lastRotated: "2026-01-01", rotationPolicyDays: 90, requiredBy: ["api", "worker"] },
      { name: "DB_PASSWORD", lastRotated: "2026-05-01", rotationPolicyDays: 60, requiredBy: ["api"] },
      { name: "STRIPE_API_KEY", lastRotated: "2026-06-01", rotationPolicyDays: 90, requiredBy: ["billing"] },
      { name: "JWT_SIGNING_KEY", lastRotated: "2026-06-20", rotationPolicyDays: 30, requiredBy: ["auth"] },
    ],
  },
  null,
  2,
);

// All-ok: every secret was rotated recently relative to its policy.
const ALL_OK_FIXTURE = JSON.stringify(
  {
    secrets: [
      { name: "GITHUB_TOKEN", lastRotated: "2026-06-15", rotationPolicyDays: 90, requiredBy: ["ci"] },
      { name: "SLACK_WEBHOOK", lastRotated: "2026-06-20", rotationPolicyDays: 180, requiredBy: ["notifications"] },
    ],
  },
  null,
  2,
);

// --- Run both cases once, up front ------------------------------------------

resetResult(); // fresh act-result.txt for this suite
const mixed: ActRun = runActCase("mixed-urgencies (push)", MIXED_FIXTURE);
const allOk: ActRun = runActCase("all-ok (push)", ALL_OK_FIXTURE);

// --- Assertions: mixed fixture ----------------------------------------------

describe("workflow via act — mixed urgencies fixture", () => {
  test("act exits 0", () => {
    expect(mixed.exitCode).toBe(0);
  });

  test("both jobs (validate + report) succeed, none fail", () => {
    expect(countJobSucceeded(mixed.output)).toBe(2);
    expect(mixed.output).not.toContain("Job failed");
  });

  test("JSON report has the exact summary counters", () => {
    expect(mixed.output).toContain('"total": 4');
    expect(mixed.output).toContain('"expired": 1');
    expect(mixed.output).toContain('"warning": 1');
    expect(mixed.output).toContain('"ok": 2');
    expect(mixed.output).toContain('"generatedAt": "2026-06-28"');
    expect(mixed.output).toContain('"warningWindowDays": 14');
  });

  test("the expired secret is reported with exact computed fields", () => {
    expect(mixed.output).toContain('"name": "AWS_ACCESS_KEY"');
    expect(mixed.output).toContain('"expiryDate": "2026-04-01"');
    expect(mixed.output).toContain('"daysSinceRotation": 178');
    expect(mixed.output).toContain('"daysUntilExpiry": -88');
    expect(mixed.output).toContain('"urgency": "expired"');
  });

  test("the warning secret is reported with exact computed fields", () => {
    expect(mixed.output).toContain('"name": "DB_PASSWORD"');
    expect(mixed.output).toContain('"expiryDate": "2026-06-30"');
    expect(mixed.output).toContain('"daysUntilExpiry": 2');
    expect(mixed.output).toContain('"urgency": "warning"');
  });

  test("the markdown job-summary table row is rendered", () => {
    expect(mixed.output).toContain(
      "| AWS_ACCESS_KEY | 2026-01-01 | 2026-04-01 | -88 | 90 | api, worker |",
    );
  });

  test("the dependent report job emits the exact verdict line", () => {
    expect(mixed.output).toContain("ROTATION_VERDICT total=4 expired=1 warning=1 ok=2");
  });

  test("an expired-secret warning annotation is surfaced", () => {
    expect(mixed.output).toContain("secret(s) are expired and must be rotated");
  });
});

// --- Assertions: all-ok fixture ---------------------------------------------

describe("workflow via act — all-ok fixture", () => {
  test("act exits 0", () => {
    expect(allOk.exitCode).toBe(0);
  });

  test("both jobs succeed", () => {
    expect(countJobSucceeded(allOk.output)).toBe(2);
    expect(allOk.output).not.toContain("Job failed");
  });

  test("summary shows nothing expired or warning", () => {
    expect(allOk.output).toContain('"total": 2');
    expect(allOk.output).toContain('"expired": 0');
    expect(allOk.output).toContain('"warning": 0');
    expect(allOk.output).toContain('"ok": 2');
  });

  test("both healthy secrets appear in the report", () => {
    expect(allOk.output).toContain('"name": "GITHUB_TOKEN"');
    expect(allOk.output).toContain('"name": "SLACK_WEBHOOK"');
  });

  test("the verdict line reflects all-ok counts", () => {
    expect(allOk.output).toContain("ROTATION_VERDICT total=2 expired=0 warning=0 ok=2");
  });
});

// --- The deliverable artifact ------------------------------------------------

describe("act-result.txt artifact", () => {
  test("exists and records both cases with exit code 0", () => {
    expect(existsSync(ACT_RESULT_PATH)).toBe(true);
    const contents = readFileSync(ACT_RESULT_PATH, "utf8");
    expect(contents).toContain("TEST CASE: mixed-urgencies (push)");
    expect(contents).toContain("TEST CASE: all-ok (push)");
    // Both runs recorded a clean exit.
    expect((contents.match(/act exit code: 0/g) ?? []).length).toBe(2);
  });
});
