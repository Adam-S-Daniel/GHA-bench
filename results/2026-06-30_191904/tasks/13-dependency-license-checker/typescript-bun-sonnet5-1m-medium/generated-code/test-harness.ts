#!/usr/bin/env bun
// Integration test harness: exercises the GitHub Actions workflow itself
// (not the script in isolation) via `act push --rm`. For each fixture
// scenario, it builds a temp git repo containing the project files plus
// that scenario's manifest, runs the workflow through act, and asserts on
// the exact compliance numbers act printed. All output is appended to
// act-result.txt in the current working directory.
//
// Usage: bun run test-harness.ts

import { mkdtemp, rm, cp, writeFile, appendFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

interface Scenario {
  name: string;
  manifestFixture: string;
  expectedSummary: { total: number; approved: number; denied: number; unknown: number };
}

const SCENARIOS: Scenario[] = [
  {
    name: "all-approved",
    manifestFixture: "fixtures/package-approved.json",
    expectedSummary: { total: 2, approved: 2, denied: 0, unknown: 0 },
  },
  {
    name: "denied-license-present",
    manifestFixture: "fixtures/package-denied.json",
    expectedSummary: { total: 2, approved: 1, denied: 1, unknown: 0 },
  },
  {
    name: "unknown-license-present",
    manifestFixture: "fixtures/package-unknown.json",
    expectedSummary: { total: 2, approved: 1, denied: 0, unknown: 1 },
  },
];

const PROJECT_ROOT = process.cwd();
const RESULT_FILE = join(PROJECT_ROOT, "act-result.txt");

async function run(cmd: string[], cwd: string): Promise<{ exitCode: number; output: string }> {
  const proc = Bun.spawn(cmd, { cwd, stdout: "pipe", stderr: "pipe" });
  const [stdout, stderr] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
  ]);
  const exitCode = await proc.exited;
  return { exitCode, output: `${stdout}\n${stderr}` };
}

async function setupTempRepo(scenario: Scenario): Promise<string> {
  const dir = await mkdtemp(join(tmpdir(), `license-checker-${scenario.name}-`));

  const entries = [
    "app.ts",
    "src",
    "tests",
    "fixtures",
    "tsconfig.json",
    "package.json",
    "bun.lock",
    ".actrc",
    ".github",
  ];
  for (const entry of entries) {
    await cp(join(PROJECT_ROOT, entry), join(dir, entry), { recursive: true });
  }

  // Overwrite the manifest the workflow reads with this scenario's fixture data.
  const manifestContent = await Bun.file(join(PROJECT_ROOT, scenario.manifestFixture)).text();
  await writeFile(join(dir, "fixtures", "current-manifest.json"), manifestContent);

  await run(["git", "init", "-q"], dir);
  await run(["git", "-c", "user.email=harness@example.com", "-c", "user.name=harness", "add", "-A"], dir);
  await run(
    ["git", "-c", "user.email=harness@example.com", "-c", "user.name=harness", "commit", "-q", "-m", "test fixture"],
    dir
  );

  return dir;
}

function assertContains(output: string, needle: string, context: string): void {
  if (!output.includes(needle)) {
    throw new Error(`Expected act output to contain "${needle}" (${context}) but it did not.`);
  }
}

async function main(): Promise<void> {
  await writeFile(RESULT_FILE, "");

  let failures = 0;

  for (const scenario of SCENARIOS) {
    console.log(`\n=== Scenario: ${scenario.name} ===`);
    const dir = await setupTempRepo(scenario);

    try {
      const { exitCode, output } = await run(["act", "push", "--rm", "--pull=false"], dir);

      await appendFile(
        RESULT_FILE,
        `\n===== SCENARIO: ${scenario.name} =====\nexit code: ${exitCode}\n${output}\n===== END ${scenario.name} =====\n`
      );

      if (exitCode !== 0) {
        console.error(`FAIL [${scenario.name}]: act exited with code ${exitCode}`);
        failures += 1;
        continue;
      }

      const jobSucceededCount = (output.match(/Job succeeded/g) ?? []).length;
      if (jobSucceededCount < 2) {
        console.error(
          `FAIL [${scenario.name}]: expected both jobs to report "Job succeeded" (found ${jobSucceededCount})`
        );
        failures += 1;
        continue;
      }

      const { total, approved, denied, unknown } = scenario.expectedSummary;
      assertContains(output, `Total: ${total}`, scenario.name);
      assertContains(output, `Approved: ${approved}`, scenario.name);
      assertContains(output, `Denied: ${denied}`, scenario.name);
      assertContains(output, `Unknown: ${unknown}`, scenario.name);

      console.log(`PASS [${scenario.name}]: exit=0, jobs succeeded, summary matched expected values`);
    } catch (err) {
      console.error(`FAIL [${scenario.name}]: ${(err as Error).message}`);
      failures += 1;
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  }

  if (failures > 0) {
    console.error(`\n${failures} scenario(s) failed.`);
    process.exitCode = 1;
  } else {
    console.log(`\nAll ${SCENARIOS.length} scenarios passed. See ${RESULT_FILE} for full act output.`);
  }
}

main();
