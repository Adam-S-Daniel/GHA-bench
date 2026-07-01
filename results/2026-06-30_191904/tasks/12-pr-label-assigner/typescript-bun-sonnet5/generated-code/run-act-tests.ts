#!/usr/bin/env bun
// act integration harness for .github/workflows/pr-label-assigner.yml.
//
// Per the task's "test through the pipeline" requirement, this is where the
// solution is actually verified end-to-end: for each fixture case it builds
// an isolated temp git repo containing the project + that case's changed
// file list, runs `act push --rm` against it, and asserts on the exact
// LABELS= output the workflow computed -- not just that *something* ran.
//
// Usage: bun run run-act-tests.ts
// Exits 0 only if every case passes; non-zero otherwise.
import { spawnSync } from "node:child_process";
import {
  appendFileSync,
  cpSync,
  mkdtempSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const PROJECT_ROOT = import.meta.dir;
const RESULT_FILE = join(PROJECT_ROOT, "act-result.txt");

/** One end-to-end pipeline test case. */
interface ActCase {
  /** Short identifier, also used to name the temp dir. */
  name: string;
  /** Fixture file (relative to the project root) to use as the PR's changed files. */
  fixturePath: string;
  /** Exact expected value of the "LABELS=" line the workflow must print. */
  expectedLabels: string;
}

// Expected values were derived by hand from .github/labeler-config.json and
// confirmed against `bun run src/cli.ts --files <fixture>` during
// development (see task notes) -- these fixtures now serve as the pipeline's
// acceptance cases.
const CASES: ActCase[] = [
  {
    name: "api-and-tests",
    fixturePath: "fixtures/cases/api-and-tests.txt",
    // api(10) > tests(5) > code(0): one file matches two rules, priority
    // breaks the multi-rule ordering.
    expectedLabels: "api,tests,code",
  },
  {
    name: "ci-and-dependencies",
    fixturePath: "fixtures/cases/ci-and-dependencies.txt",
    // dependencies(8) > ci(7): two different files, two different rules,
    // priority decides the conflict.
    expectedLabels: "dependencies,ci",
  },
  {
    name: "docs-only",
    fixturePath: "fixtures/cases/docs-only.txt",
    expectedLabels: "documentation",
  },
  {
    name: "no-match",
    fixturePath: "fixtures/cases/no-match.txt",
    expectedLabels: "",
  },
];

// Everything the workflow needs at runtime. No node_modules/bun.lock --
// the script has zero runtime dependencies, so the workflow never runs
// `bun install`.
const COPY_ITEMS = ["src", "fixtures", ".github", "package.json", "tsconfig.json", ".actrc"];

function setupRepo(c: ActCase): string {
  const dir = mkdtempSync(join(tmpdir(), `act-${c.name}-`));
  for (const item of COPY_ITEMS) {
    cpSync(join(PROJECT_ROOT, item), join(dir, item), { recursive: true });
  }
  // Overwrite the default fixture with this case's changed-file list so the
  // workflow's default push-trigger path picks it up.
  cpSync(join(PROJECT_ROOT, c.fixturePath), join(dir, "fixtures/changed-files.txt"));

  const git = (...args: string[]) =>
    spawnSync("git", args, { cwd: dir, encoding: "utf8" });
  git("init", "-q", "-b", "main");
  git("config", "user.email", "act-harness@example.com");
  git("config", "user.name", "act harness");
  git("add", "-A");
  git("commit", "-q", "-m", `fixture: ${c.name}`);
  return dir;
}

/** Strips ANSI color codes act may emit, so string matching is reliable. */
function stripAnsi(s: string): string {
  return s.replace(/\x1b\[[0-9;]*m/g, "");
}

/** Extracts the value of the last "LABELS=..." occurrence in act's output. */
function extractLabels(output: string): string | null {
  const matches = [...stripAnsi(output).matchAll(/LABELS=([^\r\n]*)/g)];
  if (matches.length === 0) return null;
  return matches[matches.length - 1]![1]!.trimEnd();
}

function section(title: string): string {
  const bar = "=".repeat(78);
  return `\n${bar}\n${title}\n${bar}\n`;
}

function runCase(c: ActCase): boolean {
  console.log(`\n>>> act push for case "${c.name}"`);
  const dir = setupRepo(c);
  try {
    const result = spawnSync(
      "act",
      ["push", "--rm", "--pull=false"],
      { cwd: dir, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 },
    );
    const output = `${result.stdout ?? ""}\n${result.stderr ?? ""}`;
    const exitCode = result.status ?? -1;

    appendFileSync(
      RESULT_FILE,
      section(
        `CASE: ${c.name} | fixture=${c.fixturePath} | expected LABELS=${c.expectedLabels}`,
      ) +
        output +
        `\n[harness] act exit code: ${exitCode}\n`,
    );

    const problems: string[] = [];
    if (exitCode !== 0) problems.push(`act exited ${exitCode}, expected 0`);
    if (!/Job succeeded/.test(output)) {
      problems.push('output did not contain "Job succeeded"');
    }
    const labels = extractLabels(output);
    if (labels === null) {
      problems.push("no LABELS= line found in act output");
    } else if (labels !== c.expectedLabels) {
      problems.push(
        `LABELS mismatch: got "${labels}", expected "${c.expectedLabels}"`,
      );
    }

    if (problems.length > 0) {
      console.error(`  FAIL [${c.name}]: ${problems.join("; ")}`);
      appendFileSync(RESULT_FILE, `[harness] RESULT: FAIL — ${problems.join("; ")}\n`);
      return false;
    }
    console.log(`  PASS [${c.name}]: LABELS="${labels}"`);
    appendFileSync(RESULT_FILE, `[harness] RESULT: PASS\n`);
    return true;
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

writeFileSync(
  RESULT_FILE,
  "act integration results for .github/workflows/pr-label-assigner.yml\nGenerated by run-act-tests.ts\n",
);

let passed = 0;
for (const c of CASES) {
  if (runCase(c)) passed++;
}

const summary = `\n${"#".repeat(78)}\nSUMMARY: ${passed}/${CASES.length} cases passed\n${"#".repeat(78)}\n`;
appendFileSync(RESULT_FILE, summary);
console.log(summary.trim());
console.log(`Full output written to: ${RESULT_FILE}`);

process.exit(passed === CASES.length ? 0 : 1);
