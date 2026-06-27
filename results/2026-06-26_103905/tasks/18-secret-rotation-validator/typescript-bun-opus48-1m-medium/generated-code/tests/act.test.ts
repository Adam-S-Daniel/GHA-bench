// End-to-end pipeline tests: every assertion below is verified by running the
// real GitHub Actions workflow through `act` (nektos/act) inside Docker — we
// never call the script directly here.
//
// For each test case we:
//   1. Build an isolated temp git repo containing the whole project plus that
//      case's fixture written to fixtures/secrets.json.
//   2. Run `act push --rm`, capturing combined output.
//   3. Append the output to act-result.txt (delimited per case).
//   4. Assert act exited 0, every job "succeeded", and the workflow emitted the
//      EXACT ROTATION_SUMMARY counts expected for that fixture.
//
// The workflow pins NOW=2026-06-27 and WARNING_DAYS=14, so every count below is
// deterministic. This suite is skipped when running *inside* act so the
// workflow's own test step can never recurse into Docker.
import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import {
  cpSync,
  mkdtempSync,
  rmSync,
  writeFileSync,
  appendFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const underAct = !!process.env.ACT;
const ROOT = join(import.meta.dir, "..");
const ACT_RESULT = join(ROOT, "act-result.txt");

/** A single end-to-end case: a fixture and its known-good summary counts. */
interface ActCase {
  name: string;
  secrets: unknown[];
  expected: { total: number; expired: number; warning: number; ok: number };
}

// Counts derived by hand for NOW=2026-06-27, warning window = 14 days.
const CASES: ActCase[] = [
  {
    // ok (64 left), warning (10 left), expired (overdue) -> 1/1/1.
    name: "mixed",
    secrets: [
      { name: "db-password", lastRotated: "2026-06-01", rotationPolicyDays: 90, requiredBy: ["api"] },
      { name: "stripe-key", lastRotated: "2026-04-08", rotationPolicyDays: 90, requiredBy: ["billing"] },
      { name: "legacy-token", lastRotated: "2026-01-01", rotationPolicyDays: 90, requiredBy: ["legacy"] },
    ],
    expected: { total: 3, expired: 1, warning: 1, ok: 0 + 1 },
  },
  {
    // Both long overdue -> 2 expired, nothing else.
    name: "all-expired",
    secrets: [
      { name: "ancient-key", lastRotated: "2020-01-01", rotationPolicyDays: 30, requiredBy: ["a"] },
      { name: "stale-cert", lastRotated: "2021-01-01", rotationPolicyDays: 90, requiredBy: ["b"] },
    ],
    expected: { total: 2, expired: 2, warning: 0, ok: 0 },
  },
];

/** Copy the project into a fresh temp dir, excluding volatile/output paths. */
function stageRepo(): string {
  const dir = mkdtempSync(join(tmpdir(), "srv-act-"));
  cpSync(ROOT, dir, {
    recursive: true,
    filter: (src) => {
      const skip = [".git", "node_modules", "act-result.txt"];
      return !skip.some((p) => src === join(ROOT, p) || src.startsWith(join(ROOT, p) + "/"));
    },
  });
  return dir;
}

/** Initialise a git repo and commit everything (act's checkout needs commits). */
function initGit(dir: string): void {
  const run = (args: string[]) => {
    const r = spawnSync("git", args, { cwd: dir, encoding: "utf8" });
    if (r.status !== 0) throw new Error(`git ${args.join(" ")} failed: ${r.stderr}`);
  };
  run(["init", "-q", "-b", "main"]);
  run(["config", "user.email", "ci@example.com"]);
  run(["config", "user.name", "CI"]);
  run(["add", "-A"]);
  run(["commit", "-q", "-m", "fixture"]);
}

beforeAll(() => {
  if (underAct) return;
  // Start every run with a fresh artifact file.
  writeFileSync(ACT_RESULT, `# act results — generated ${"run"}\n`);
});

describe.skipIf(underAct)("workflow via act", () => {
  for (const c of CASES) {
    test(
      `case "${c.name}" produces exact summary ${JSON.stringify(c.expected)}`,
      () => {
        const dir = stageRepo();
        try {
          // Overwrite the fixture with this case's data, then commit.
          writeFileSync(
            join(dir, "fixtures/secrets.json"),
            JSON.stringify({ secrets: c.secrets }, null, 2),
          );
          initGit(dir);

          const res = spawnSync(
            "act",
            [
              "push",
              "--rm",
              // The runner image is built locally; never try to pull it.
              "--pull=false",
              "-W",
              ".github/workflows/secret-rotation-validator.yml",
            ],
            { cwd: dir, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 },
          );

          const output = `${res.stdout ?? ""}\n${res.stderr ?? ""}`;

          // Persist the full output for this case as a required artifact.
          appendFileSync(
            ACT_RESULT,
            [
              `\n${"=".repeat(70)}`,
              `CASE: ${c.name}`,
              `EXPECTED: ${JSON.stringify(c.expected)}`,
              `ACT EXIT CODE: ${res.status}`,
              "=".repeat(70),
              output,
              "",
            ].join("\n"),
          );

          // 1. act must exit cleanly.
          expect(res.status).toBe(0);

          // 2. Both jobs (test, validate) must report success.
          const succeeded = output.match(/Job succeeded/g) ?? [];
          expect(succeeded.length).toBeGreaterThanOrEqual(2);

          // 3. The workflow must emit the EXACT expected summary line.
          const expectedLine = `ROTATION_SUMMARY total=${c.expected.total} expired=${c.expected.expired} warning=${c.expected.warning} ok=${c.expected.ok}`;
          expect(output).toContain(expectedLine);
        } finally {
          rmSync(dir, { recursive: true, force: true });
        }
      },
      300_000, // act can take 30-90s+ per run (image + bun download).
    );
  }
});

afterAll(() => {
  if (underAct) return;
  // Leave a trailing marker so a truncated/aborted run is obvious.
  appendFileSync(ACT_RESULT, `\n# end of act results (${CASES.length} cases)\n`);
});
