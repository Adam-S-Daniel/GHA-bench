// Red/green TDD step 8 (GitHub Actions requirement): actually run the
// workflow through `act` and assert on the real output, instead of testing
// the script directly.
//
// Design note on "one act push per test case": the task's own guidance caps
// agents at 3 `act push` invocations total ("30-90 seconds per run...
// diagnose errors from output rather than re-running blindly"), while this
// validator has 5 distinct scenarios (ok / warning / expired / mixed-json /
// invalid-config). Running one `act push` per scenario would need 5 runs,
// which the budget doesn't allow. Instead, the workflow itself expresses
// every scenario as its own GitHub Actions job (a `strategy.matrix` job per
// fixture, plus a dedicated error-handling job) — see
// .github/workflows/secret-rotation-validator.yml. A single `act push`
// therefore *does* run every test case through the real pipeline; act
// reports each job's outcome independently ("Job succeeded" per job), and
// we assert exact expected values for each case out of that one capture.
import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

const PROJECT_ROOT: string = join(import.meta.dir, "..");
const ACT_RESULT_PATH: string = join(PROJECT_ROOT, "act-result.txt");
const ACT_TIMEOUT_MS: number = 480_000; // matrix of 7 job runs, each pulling bun fresh

// Files/directories copied into the isolated temp git repo that `act` runs
// against. Deliberately excludes node_modules/.git (regenerated or
// irrelevant) and this file itself (running `act` from inside a workflow
// that `act` executes would recursively spin up Docker-in-Docker).
const PROJECT_ENTRIES: string[] = [
  "app.ts",
  "src",
  "fixtures",
  "package.json",
  "bun.lock",
  "tsconfig.json",
  ".actrc",
  ".github",
  "tests/dateUtils.test.ts",
  "tests/evaluate.test.ts",
  "tests/config.test.ts",
  "tests/report.test.ts",
  "tests/format.test.ts",
  "tests/cli.test.ts",
  "tests/workflow-structure.test.ts",
];

interface CaseExpectation {
  id: string;
  /** Substring identifying this case's job/lines in the act output (for the act-result.txt excerpt). */
  logFilter: string;
  /** Exact substrings that must appear in the act output for this case. */
  mustContain: string[];
}

const CASE_EXPECTATIONS: CaseExpectation[] = [
  {
    id: "ok",
    logFilter: "(ok)",
    mustContain: [
      "## Expired (0)",
      "## Warning (0)",
      "## OK (2)",
      "| tls-cert-primary | 2026-06-21 | 90 | 80 | web-frontend |",
      "| ci-deploy-token | 2026-06-26 | 30 | 25 | ci-pipeline |",
    ],
  },
  {
    id: "warning",
    logFilter: "(warning)",
    mustContain: [
      "## Expired (0)",
      "## Warning (2)",
      "## OK (0)",
      "| payment-api-key | 2026-04-12 | 90 | 10 | payments-service |",
      "| internal-db-token | 2026-05-02 | 60 | 0 | internal-db |",
    ],
  },
  {
    id: "expired",
    logFilter: "(expired)",
    mustContain: [
      "## Expired (2)",
      "## Warning (0)",
      "## OK (0)",
      "| legacy-ftp-password | 2026-03-28 | 90 | -5 | legacy-ftp |",
      "| old-smtp-secret | 2026-05-02 | 30 | -30 | mail-relay |",
    ],
  },
  {
    id: "mixed",
    logFilter: "(mixed)",
    mustContain: [
      '"totalSecrets": 3',
      '"name": "db-password"',
      '"daysUntilExpiry": -10',
      '"name": "api-key"',
      '"daysUntilExpiry": 10',
      '"name": "tls-cert"',
      '"daysUntilExpiry": 60',
    ],
  },
  {
    id: "invalid",
    logFilter: "error handling",
    mustContain: [
      "captured exit code: 1",
      "rotationPolicyDays must be a positive integer, got -5",
      "CASE_MARKER_END case=invalid",
    ],
  },
];

let actOutput: string = "";
let actExitCode: number = -1;
let tempDir: string = "";

async function copyProjectInto(destDir: string): Promise<void> {
  for (const entry of PROJECT_ENTRIES) {
    const src = join(PROJECT_ROOT, entry);
    const dest = join(destDir, entry);
    await Bun.spawn(["mkdir", "-p", join(dest, "..")]).exited;
    const cp = Bun.spawn(["cp", "-r", src, dest], { stderr: "pipe" });
    const code = await cp.exited;
    if (code !== 0) {
      const stderr = await new Response(cp.stderr).text();
      throw new Error(`Failed to copy ${entry}: ${stderr}`);
    }
  }
}

async function runGit(cwd: string, args: string[]): Promise<void> {
  const proc = Bun.spawn(["git", ...args], { cwd, stdout: "pipe", stderr: "pipe" });
  const code = await proc.exited;
  if (code !== 0) {
    const stderr = await new Response(proc.stderr).text();
    throw new Error(`git ${args.join(" ")} failed: ${stderr}`);
  }
}

beforeAll(async () => {
  tempDir = await mkdtemp(join(tmpdir(), "secret-rotation-act-"));
  await copyProjectInto(tempDir);

  await runGit(tempDir, ["init", "-q"]);
  await runGit(tempDir, ["-c", "user.email=test@example.com", "-c", "user.name=Test Runner", "add", "-A"]);
  await runGit(tempDir, [
    "-c",
    "user.email=test@example.com",
    "-c",
    "user.name=Test Runner",
    "commit",
    "-q",
    "-m",
    "test: secret rotation validator fixture commit",
  ]);

  const proc = Bun.spawn(
    // --pull=false: `act-ubuntu-pwsh:latest` is a locally-built image (see
    // Dockerfile.act); with pulling enabled act tries to fetch it from a
    // registry and fails with a Docker Hub auth error.
    ["act", "push", "--rm", "--pull=false", "-P", "ubuntu-latest=act-ubuntu-pwsh:latest"],
    { cwd: tempDir, stdout: "pipe", stderr: "pipe" },
  );
  const [stdout, stderr] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
  ]);
  actExitCode = await proc.exited;
  actOutput = `${stdout}\n${stderr}`;

  const banner = (id: string): string => `\n${"=".repeat(80)}\nTEST CASE: ${id}\n${"=".repeat(80)}\n`;
  const sections: string[] = [
    "Secret Rotation Validator — act push integration test results",
    "Command: act push --rm --pull=false -P ubuntu-latest=act-ubuntu-pwsh:latest",
    `Exit code: ${actExitCode}`,
    "",
    "All 5 scenarios (ok, warning, expired, mixed, invalid) are validated by",
    "this single `act push` run, via distinct jobs/matrix entries in",
    ".github/workflows/secret-rotation-validator.yml. Per-case excerpts below,",
    "followed by the full raw act output.",
  ];
  for (const { id, logFilter } of CASE_EXPECTATIONS) {
    const relevantLines = actOutput
      .split("\n")
      .filter((line) => line.includes(logFilter))
      .join("\n");
    sections.push(banner(id));
    sections.push(relevantLines || "(no case-specific lines found; see full output below)");
  }
  sections.push(`\n${"=".repeat(80)}\nFULL RAW ACT OUTPUT\n${"=".repeat(80)}\n`);
  sections.push(actOutput);

  await writeFile(ACT_RESULT_PATH, sections.join("\n"));
}, ACT_TIMEOUT_MS);

afterAll(async () => {
  if (tempDir) {
    await rm(tempDir, { recursive: true, force: true });
  }
});

describe("act push integration", () => {
  test("act-result.txt is written to the current working directory", async () => {
    const file = Bun.file(ACT_RESULT_PATH);
    expect(await file.exists()).toBe(true);
  });

  test("act exits with code 0", () => {
    expect(actExitCode).toBe(0);
  });

  test("every job in the workflow shows 'Job succeeded'", () => {
    // unit-tests, validate-secrets x4 (matrix), validate-error-handling, summary
    const expectedJobRunCount = 7;
    const successCount = actOutput.split("Job succeeded").length - 1;
    expect(successCount).toBe(expectedJobRunCount);
  });

  test("no job reports failure", () => {
    expect(actOutput).not.toContain("Job failed");
  });

  for (const { id, mustContain } of CASE_EXPECTATIONS) {
    test(`case "${id}": act output contains the exact expected values`, () => {
      for (const expected of mustContain) {
        expect(actOutput).toContain(expected);
      }
    });
  }
});
