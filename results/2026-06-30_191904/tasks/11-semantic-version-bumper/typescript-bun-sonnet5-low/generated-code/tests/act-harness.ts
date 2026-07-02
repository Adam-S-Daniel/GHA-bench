// Runs the GitHub Actions workflow through `act` once per fixture test case,
// in an isolated temp git repo, and asserts on the exact expected version
// bump for each case. All act output is appended to act-result.txt.
//
// This is intentionally a standalone script (not a bun:test file) since it
// shells out to Docker via act and each case takes real wall-clock time.
import { mkdtemp, rm, cp, writeFile, appendFile, readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { $ } from "bun";

interface TestCase {
  name: string;
  commitsFixture: string;
  startVersion: string;
  expectedVersion: string;
}

const CASES: TestCase[] = [
  {
    name: "minor-bump-from-feat",
    commitsFixture: "fixtures/commits-minor.txt",
    startVersion: "1.1.0",
    expectedVersion: "1.2.0",
  },
  {
    name: "patch-bump-from-fix",
    commitsFixture: "fixtures/commits-patch.txt",
    startVersion: "1.1.0",
    expectedVersion: "1.1.1",
  },
  {
    name: "major-bump-from-breaking-change",
    commitsFixture: "fixtures/commits-major.txt",
    startVersion: "1.1.0",
    expectedVersion: "2.0.0",
  },
];

const REPO_ROOT = process.cwd();
const RESULT_FILE = join(REPO_ROOT, "act-result.txt");

async function setUpTempRepo(testCase: TestCase): Promise<string> {
  const dir = await mkdtemp(join(tmpdir(), `act-${testCase.name}-`));

  // Copy project files needed to run the workflow (skip .git, node_modules, act artifacts).
  const entries = [
    "src",
    "tests",
    "fixtures",
    ".github",
    "package.json",
    "bun.lock",
    "bun.lockb",
    "CHANGELOG.md",
  ];
  for (const entry of entries) {
    const src = join(REPO_ROOT, entry);
    const file = Bun.file(src);
    const exists = (await file.exists()) || (await $`test -d ${src}`.nothrow()).exitCode === 0;
    if (!exists) continue;
    await cp(src, join(dir, entry), { recursive: true, force: true });
  }

  // Seed this test case's version file and commit-log fixture.
  await writeFile(
    join(dir, "version.json"),
    JSON.stringify({ version: testCase.startVersion }, null, 2) + "\n",
  );
  const commitLog = await readFile(join(REPO_ROOT, testCase.commitsFixture), "utf8");
  await writeFile(join(dir, "commits.txt"), commitLog);

  // act push requires a git repo with at least one commit.
  await $`git init -q`.cwd(dir);
  await $`git -c user.email=act@test.local -c user.name=act-harness add -A`.cwd(dir);
  await $`git -c user.email=act@test.local -c user.name=act-harness commit -q -m "test: seed fixture for ${testCase.name}"`.cwd(
    dir,
  );

  return dir;
}

async function runCase(testCase: TestCase): Promise<void> {
  const dir = await setUpTempRepo(testCase);
  try {
    const result = await $`act push --rm`.cwd(dir).nothrow();
    const output = result.stdout.toString() + result.stderr.toString();

    await appendFile(
      RESULT_FILE,
      `\n===== TEST CASE: ${testCase.name} =====\n` +
        `start_version=${testCase.startVersion} expected_version=${testCase.expectedVersion}\n` +
        `exit_code=${result.exitCode}\n\n${output}\n`,
    );

    if (result.exitCode !== 0) {
      throw new Error(`act push exited with code ${result.exitCode} for case "${testCase.name}"`);
    }

    const jobSuccessCount = (output.match(/Job succeeded/g) ?? []).length;
    if (jobSuccessCount < 2) {
      throw new Error(
        `Expected both jobs ("test" and "bump-version") to succeed for case "${testCase.name}", found ${jobSuccessCount} success markers`,
      );
    }

    const expectedLine = `New version: ${testCase.expectedVersion}`;
    if (!output.includes(expectedLine)) {
      throw new Error(
        `Expected act output to contain "${expectedLine}" for case "${testCase.name}", but it did not.`,
      );
    }

    console.log(`PASS: ${testCase.name} -> ${testCase.expectedVersion}`);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}

async function main(): Promise<void> {
  await writeFile(RESULT_FILE, `act test harness run\n`);
  for (const testCase of CASES) {
    await runCase(testCase);
  }
  console.log(`\nAll ${CASES.length} act test cases passed. See act-result.txt for full output.`);
}

await main();
