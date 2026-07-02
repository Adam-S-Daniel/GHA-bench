/**
 * End-to-end pipeline test harness.
 *
 * Every test case runs through the real GitHub Actions workflow via `act`:
 *   1. Copy the project into a temp git repo and swap in the case's fixture
 *      as fixtures/secrets.json (the path the workflow's env points at).
 *   2. Stage the host `bun` and `actionlint` binaries into bin/ so the act
 *      container needs no network access (the workflow prefers bin/bun).
 *   3. Run `act push --rm`, append the full output to act-result.txt.
 *   4. Assert exit code 0, both jobs succeeded, and that the report output
 *      matches EXACT known-good values for that case's input.
 *
 * Run with: bun run scripts/run-act-tests.ts
 */
import {
  chmodSync,
  copyFileSync,
  cpSync,
  mkdirSync,
  mkdtempSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const PROJECT_ROOT = process.cwd();
const RESULT_FILE = join(PROJECT_ROOT, "act-result.txt");

interface JsonReport {
  generatedFor: string;
  warningWindowDays: number;
  summary: { expired: number; warning: number; ok: number };
  notifications: Record<"expired" | "warning" | "ok", { name: string; message: string }[]>;
}

interface TestCase {
  name: string;
  /** Written to fixtures/secrets.json in the temp repo. */
  fixture: object;
  /** Exact substrings that must appear in the markdown report. */
  expectMarkdown: string[];
  /** Exact assertions against the parsed JSON report. */
  expectJson: (report: JsonReport, assert: Assert) => void;
}

type Assert = (condition: boolean, label: string, detail?: string) => void;

// ---------------------------------------------------------------------------
// Test cases. REPORT_DATE in the workflow is pinned to 2026-07-01, so every
// expected value below is a hand-computed known-good result for that date.
// ---------------------------------------------------------------------------
const CASES: TestCase[] = [
  {
    // Mixed urgency: 2 expired (32 and 10 days overdue), 1 warning (7 days
    // out with a 14-day window), 1 ok (60 days out).
    name: "mixed-urgency",
    fixture: {
      secrets: [
        { name: "db-password", lastRotated: "2026-03-01", rotationPolicyDays: 90, requiredBy: ["api", "worker"] },
        { name: "oauth-secret", lastRotated: "2026-05-22", rotationPolicyDays: 30, requiredBy: ["auth"] },
        { name: "tls-cert", lastRotated: "2026-04-09", rotationPolicyDays: 90, requiredBy: ["gateway"] },
        { name: "api-key", lastRotated: "2026-06-01", rotationPolicyDays: 90, requiredBy: ["api"] },
      ],
    },
    expectMarkdown: [
      "**Summary:** 2 expired, 1 warning, 1 ok",
      "## 🔴 Expired (2)",
      "## 🟡 Warning (1)",
      "## 🟢 Ok (1)",
      "| db-password | 2026-03-01 | 90 | 2026-05-30 | -32 | api, worker |",
      "| oauth-secret | 2026-05-22 | 30 | 2026-06-21 | -10 | auth |",
      "| tls-cert | 2026-04-09 | 90 | 2026-07-08 | 7 | gateway |",
      "| api-key | 2026-06-01 | 90 | 2026-08-30 | 60 | api |",
    ],
    expectJson: (report, assert) => {
      assert(report.generatedFor === "2026-07-01", "json generatedFor is 2026-07-01", report.generatedFor);
      assert(report.summary.expired === 2, "json summary.expired === 2", String(report.summary.expired));
      assert(report.summary.warning === 1, "json summary.warning === 1", String(report.summary.warning));
      assert(report.summary.ok === 1, "json summary.ok === 1", String(report.summary.ok));
      const expiredNames = report.notifications.expired.map((n) => n.name).join(",");
      assert(expiredNames === "db-password,oauth-secret", "expired sorted most-overdue-first", expiredNames);
      assert(
        report.notifications.expired[0]!.message ===
          'Secret "db-password" EXPIRED 32 days ago on 2026-05-30 — rotate immediately! Required by: api, worker.',
        "exact expired notification message",
        report.notifications.expired[0]!.message,
      );
      assert(
        report.notifications.warning[0]!.message ===
          'Secret "tls-cert" expires in 7 days on 2026-07-08 — schedule a rotation. Required by: gateway.',
        "exact warning notification message",
        report.notifications.warning[0]!.message,
      );
    },
  },
  {
    // Everything healthy: expired and warning buckets must be empty and
    // render as _None_ in markdown.
    name: "all-ok",
    fixture: {
      secrets: [
        { name: "signing-key", lastRotated: "2026-06-15", rotationPolicyDays: 180, requiredBy: ["ci"] },
        { name: "webhook-token", lastRotated: "2026-06-01", rotationPolicyDays: 90, requiredBy: ["billing"] },
      ],
    },
    expectMarkdown: [
      "**Summary:** 0 expired, 0 warning, 2 ok",
      "## 🔴 Expired (0)",
      "_None_",
      "| webhook-token | 2026-06-01 | 90 | 2026-08-30 | 60 | billing |",
      "| signing-key | 2026-06-15 | 180 | 2026-12-12 | 164 | ci |",
    ],
    expectJson: (report, assert) => {
      assert(report.summary.expired === 0, "json summary.expired === 0", String(report.summary.expired));
      assert(report.summary.warning === 0, "json summary.warning === 0", String(report.summary.warning));
      assert(report.summary.ok === 2, "json summary.ok === 2", String(report.summary.ok));
      const okNames = report.notifications.ok.map((n) => n.name).join(",");
      assert(okNames === "webhook-token,signing-key", "ok bucket sorted soonest-due-first", okNames);
    },
  },
];

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Run a command, returning combined output and exit code. */
function run(cmd: string[], cwd: string): { exitCode: number; output: string } {
  const proc = Bun.spawnSync(cmd, { cwd, stdout: "pipe", stderr: "pipe" });
  return {
    exitCode: proc.exitCode,
    output: proc.stdout.toString() + proc.stderr.toString(),
  };
}

/** Strip act's `[Workflow/Job]   | ` line prefix from a log line. */
function stripActPrefix(line: string): string {
  return line.replace(/^\[[^\]]*\]\s*\|\s?/, "");
}

/** Extract the report text between START/END marker lines in act output. */
function extractSection(actOutput: string, marker: string): string {
  const lines = actOutput.split("\n");
  const start = lines.findIndex((l) => l.includes(`=== ${marker} START ===`));
  const end = lines.findIndex((l) => l.includes(`=== ${marker} END ===`));
  if (start === -1 || end === -1 || end <= start) {
    throw new Error(`Could not find ${marker} markers in act output`);
  }
  return lines
    .slice(start + 1, end)
    .filter((l) => l.includes("|")) // only container log lines carry the prefix
    .map(stripActPrefix)
    .join("\n");
}

/** Build the temp git repo for one case and return its path. */
function stageCase(testCase: TestCase, bunBin: string, actionlintBin: string): string {
  const repo = mkdtempSync(join(tmpdir(), `act-${testCase.name}-`));
  for (const entry of ["package.json", "tsconfig.json", ".actrc", "src", "tests", "fixtures", ".github"]) {
    cpSync(join(PROJECT_ROOT, entry), join(repo, entry), { recursive: true });
  }
  // Swap in this case's fixture at the path the workflow reads.
  writeFileSync(join(repo, "fixtures", "secrets.json"), JSON.stringify(testCase.fixture, null, 2));
  // Stage host binaries so the container runs without network access.
  mkdirSync(join(repo, "bin"), { recursive: true });
  copyFileSync(bunBin, join(repo, "bin", "bun"));
  copyFileSync(actionlintBin, join(repo, "bin", "actionlint"));
  chmodSync(join(repo, "bin", "bun"), 0o755);
  chmodSync(join(repo, "bin", "actionlint"), 0o755);

  for (const cmd of [
    ["git", "init", "-q"],
    ["git", "config", "user.email", "harness@example.com"],
    ["git", "config", "user.name", "Act Harness"],
    ["git", "add", "-A"],
    ["git", "commit", "-qm", `fixture: ${testCase.name}`],
  ]) {
    const { exitCode, output } = run(cmd, repo);
    if (exitCode !== 0) throw new Error(`${cmd.join(" ")} failed: ${output}`);
  }
  return repo;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

const bunBin = process.execPath;
const actionlintBin = Bun.which("actionlint");
if (!actionlintBin) throw new Error("actionlint not found on PATH");

let failures = 0;
let resultLog = "";

for (const testCase of CASES) {
  const caseFailures: string[] = [];
  const assert: Assert = (condition, label, detail) => {
    const status = condition ? "PASS" : "FAIL";
    resultLog += `[assert] ${status}: ${label}${condition || detail === undefined ? "" : ` (got: ${detail})`}\n`;
    if (!condition) caseFailures.push(label);
  };

  console.log(`\n=== Case: ${testCase.name} — running act push --rm ===`);
  const repo = stageCase(testCase, bunBin, actionlintBin);
  resultLog += `\n${"=".repeat(78)}\n=== TEST CASE: ${testCase.name} ===\n${"=".repeat(78)}\n`;
  try {
    // --pull=false: the runner image is local-only; forcing a registry pull
    // fails with an auth error.
    const { exitCode, output } = run(["act", "push", "--rm", "--pull=false"], repo);
    resultLog += output + "\n";

    assert(exitCode === 0, `act exited with code 0`, String(exitCode));
    const succeeded = output.match(/Job succeeded/g)?.length ?? 0;
    assert(succeeded === 2, `both jobs report "Job succeeded"`, `${succeeded} succeeded`);
    assert(!output.includes("Job failed"), `no job reports "Job failed"`);

    if (exitCode === 0) {
      const markdown = extractSection(output, "MARKDOWN REPORT");
      for (const expected of testCase.expectMarkdown) {
        assert(markdown.includes(expected), `markdown contains ${JSON.stringify(expected)}`);
      }
      const json = JSON.parse(extractSection(output, "JSON REPORT")) as JsonReport;
      testCase.expectJson(json, assert);
    }
  } finally {
    rmSync(repo, { recursive: true, force: true });
  }

  if (caseFailures.length === 0) {
    console.log(`✅ ${testCase.name}: all assertions passed`);
  } else {
    failures += caseFailures.length;
    console.error(`❌ ${testCase.name}: ${caseFailures.length} assertion(s) failed:`);
    for (const f of caseFailures) console.error(`   - ${f}`);
  }
}

writeFileSync(RESULT_FILE, resultLog);
console.log(`\nAct output + assertions written to ${RESULT_FILE}`);
if (failures > 0) {
  console.error(`\n${failures} assertion(s) failed`);
  process.exit(1);
}
console.log("All act pipeline test cases passed.");
