/**
 * act-based end-to-end test harness.
 *
 * Every test case runs THROUGH the GitHub Actions workflow:
 *  1. Build a temp git repo containing the project files plus the case's
 *     ci-input/ fixture data (manifest, config, mock license database).
 *  2. Run `act push --rm` in that repo.
 *  3. Append the full act output to act-result.txt (delimited per case).
 *  4. Assert act exited 0, both jobs report "Job succeeded", and the log
 *     contains the EXACT expected report lines for that case's input.
 *
 * Run with: bun run scripts/act-harness.ts
 */
import { cpSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";

const ROOT = join(import.meta.dir, "..");
const RESULT_FILE = join(ROOT, "act-result.txt");

/** Project files copied into each temp repo. node_modules is rebuilt in CI. */
const PROJECT_FILES = ["package.json", "tsconfig.json", ".actrc", "src", "tests", ".github"];

interface TestCase {
  name: string;
  /** ci-input files written into the temp repo (repo-relative path -> content). */
  files: Record<string, string>;
  /** Exact strings that MUST appear in the act output. */
  expected: string[];
}

const CASES: TestCase[] = [
  {
    // npm manifest with ci-input overriding manifest, config, AND license db.
    name: "npm-package-json",
    files: {
      "ci-input/package.json": JSON.stringify(
        {
          name: "case1-app",
          dependencies: { lodash: "^4.17.21", "evil-lib": "2.0.0", "ghost-pkg": "1.0.0" },
        },
        null,
        2,
      ),
      "ci-input/license-config.json": JSON.stringify(
        { allow: ["MIT", "Apache-2.0"], deny: ["GPL-3.0"] },
        null,
        2,
      ),
      "ci-input/licenses.json": JSON.stringify(
        { lodash: "MIT", "evil-lib": "GPL-3.0" },
        null,
        2,
      ),
    },
    expected: [
      "Checking manifest: ci-input/package.json",
      "evil-lib@2.0.0: GPL-3.0 [denied]",
      "ghost-pkg@1.0.0: UNKNOWN [unknown]",
      "lodash@4.17.21: MIT [approved]",
      "Summary: 1 approved, 1 denied, 1 unknown",
    ],
  },
  {
    // pip manifest via ci-input; config + license db fall back to the
    // committed default fixtures, exercising the workflow's fallback path.
    name: "pip-requirements-txt",
    files: {
      "ci-input/requirements.txt": [
        "# pip case: mix of approved, denied, and unknown licenses",
        "requests==2.31.0",
        "flask>=3.0.1  # web framework",
        "copyleft-tool==1.0.0",
        "numpy",
        "",
      ].join("\n"),
    },
    expected: [
      "Checking manifest: ci-input/requirements.txt",
      "copyleft-tool@1.0.0: AGPL-3.0 [denied]",
      "flask@3.0.1: BSD-3-Clause [approved]",
      "numpy@*: UNKNOWN [unknown]",
      "requests@2.31.0: Apache-2.0 [approved]",
      "Summary: 2 approved, 1 denied, 1 unknown",
    ],
  },
];

/** Assertions that must hold for every case, independent of fixture data. */
const JOB_SUCCESS_PATTERNS: RegExp[] = [
  /License compliance check.*🏁 {2}Job succeeded/,
  /Pipeline summary.*🏁 {2}Job succeeded/,
];

async function run(cmd: string[], cwd: string): Promise<{ exitCode: number; output: string }> {
  const proc = Bun.spawn(cmd, { cwd, stdout: "pipe", stderr: "pipe" });
  const [stdout, stderr, exitCode] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
    proc.exited,
  ]);
  return { exitCode, output: stdout + stderr };
}

function setUpTempRepo(testCase: TestCase): string {
  const repo = mkdtempSync(join(tmpdir(), `act-case-${testCase.name}-`));
  for (const entry of PROJECT_FILES) {
    cpSync(join(ROOT, entry), join(repo, entry), { recursive: true });
  }
  for (const [relPath, content] of Object.entries(testCase.files)) {
    mkdirSync(join(repo, dirname(relPath)), { recursive: true });
    writeFileSync(join(repo, relPath), content);
  }
  return repo;
}

let resultLog = "";
let failures = 0;

function check(condition: boolean, label: string): void {
  const mark = condition ? "PASS" : "FAIL";
  if (!condition) failures++;
  const line = `  [${mark}] ${label}`;
  console.log(line);
  resultLog += `${line}\n`;
}

for (const testCase of CASES) {
  const banner = `\n${"=".repeat(72)}\n=== TEST CASE: ${testCase.name}\n${"=".repeat(72)}\n`;
  console.log(banner);
  resultLog += banner;

  const repo = setUpTempRepo(testCase);
  try {
    // act's push event wants a real git repo with at least one commit.
    for (const gitCmd of [
      ["git", "init", "-q", "-b", "main"],
      ["git", "add", "-A"],
      ["git", "-c", "user.email=ci@example.com", "-c", "user.name=CI", "commit", "-q", "-m", "fixture"],
    ]) {
      const { exitCode, output } = await run(gitCmd, repo);
      if (exitCode !== 0) throw new Error(`git setup failed (${gitCmd.join(" ")}): ${output}`);
    }

    console.log(`Running act push in ${repo} ...`);
    const act = await run(["act", "push", "--rm", "--pull=false"], repo);
    resultLog += `--- act output for case "${testCase.name}" (exit code ${act.exitCode}) ---\n`;
    resultLog += `${act.output}\n--- end act output for case "${testCase.name}" ---\n\n`;

    check(act.exitCode === 0, `act exited 0 (got ${act.exitCode})`);
    for (const pattern of JOB_SUCCESS_PATTERNS) {
      check(pattern.test(act.output), `job success marker: ${pattern}`);
    }
    for (const expected of testCase.expected) {
      check(act.output.includes(expected), `output contains exactly: "${expected}"`);
    }
  } finally {
    rmSync(repo, { recursive: true, force: true });
  }
}

const verdict = `\n${"=".repeat(72)}\nRESULT: ${failures === 0 ? "ALL ACT TEST CASES PASSED" : `${failures} ASSERTION(S) FAILED`}\n`;
console.log(verdict);
resultLog += verdict;
writeFileSync(RESULT_FILE, resultLog);
console.log(`Full act output saved to ${RESULT_FILE}`);
process.exit(failures === 0 ? 0 : 1);
