// End-to-end workflow tests: EVERY case runs through the real GitHub Actions
// workflow via `act`. We also statically validate the workflow structure.
//
// For each case we build an isolated temp git repo containing the project files
// plus that case's fixture (written as changed-files.txt, which the workflow
// reads by default), run `act push --rm`, capture the output, append it to
// act-result.txt, and assert on the EXACT computed label set.
import { afterAll, describe, expect, test } from "bun:test";
import { execSync } from "node:child_process";
import {
  cpSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
  existsSync,
  appendFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

// Project root (this test lives in <root>/tests).
const ROOT = join(import.meta.dir, "..");
const ACT_RESULT = join(ROOT, "act-result.txt");

// Reset the aggregate artifact at the start of the run.
writeFileSync(ACT_RESULT, `# act-result.txt — generated ${new Date().toISOString()}\n`);

function strip(s: string): string {
  // Remove ANSI color codes so marker parsing is robust.
  return s.replace(/\[[0-9;]*m/g, "");
}

/** Build an isolated temp git repo containing the project + a fixture. */
function makeRepo(changedFiles: string): string {
  const dir = mkdtempSync(join(tmpdir(), "pr-label-act-"));
  for (const entry of ["src", "label-config.json", "package.json", ".github"]) {
    cpSync(join(ROOT, entry), join(dir, entry), { recursive: true });
  }
  // The fixture IS the changed-files list the workflow reads by default.
  writeFileSync(join(dir, "changed-files.txt"), changedFiles);
  // act + actions/checkout require a real git repo with a commit.
  execSync(
    'git init -q && git add -A && ' +
      'git -c user.email=t@t.t -c user.name=t commit -q -m fixture',
    { cwd: dir, stdio: "pipe" },
  );
  return dir;
}

interface ActRun {
  output: string;
  status: number;
}

function runAct(dir: string): ActRun {
  try {
    const output = execSync("act push --rm", {
      cwd: dir,
      encoding: "utf8",
      stdio: "pipe",
      timeout: 300_000,
      maxBuffer: 64 * 1024 * 1024,
    });
    return { output, status: 0 };
  } catch (err: unknown) {
    // execSync throws on non-zero exit; capture the combined output + status.
    const e = err as { stdout?: string; stderr?: string; status?: number };
    return {
      output: (e.stdout ?? "") + (e.stderr ?? ""),
      status: e.status ?? 1,
    };
  }
}

/**
 * Extract the value of a `MARKER=` line emitted by the CLI step.
 *
 * act prefixes a step's stdout with "<job>   | ", so the real marker lines look
 * like "... | LABELS=documentation". We anchor on that "| NAME=" prefix so we
 * never accidentally match the substring "LABELS=" that appears inside a unit
 * test's printed name during the earlier `bun test` step.
 */
function marker(output: string, name: string): string | null {
  const re = new RegExp(`\\| ${name}=([^\\s]*)`);
  const m = strip(output).match(re);
  return m ? m[1]!.trim() : null;
}

const CASES = [
  {
    name: "docs-only",
    fixture: "tests/fixtures/case-docs-only.txt",
    expectedLabels: "documentation",
    expectedCount: "1",
    expectedUnmatched: "",
  },
  {
    name: "multi-label-per-file",
    fixture: "tests/fixtures/case-multi-label.txt",
    expectedLabels: "api,tests,source",
    expectedCount: "3",
    expectedUnmatched: "",
  },
  {
    name: "mixed-with-unmatched",
    fixture: "tests/fixtures/case-mixed.txt",
    expectedLabels: "api,ci,documentation,source",
    expectedCount: "4",
    expectedUnmatched: "README.md",
  },
];

const tempDirs: string[] = [];
afterAll(() => {
  for (const d of tempDirs) rmSync(d, { recursive: true, force: true });
});

describe("workflow structure (static)", () => {
  const wfPath = join(ROOT, ".github/workflows/pr-label-assigner.yml");
  const wf = readFileSync(wfPath, "utf8");

  test("actionlint passes with exit code 0", () => {
    const status = (() => {
      try {
        execSync(`actionlint ${wfPath}`, { stdio: "pipe" });
        return 0;
      } catch (e) {
        return (e as { status?: number }).status ?? 1;
      }
    })();
    expect(status).toBe(0);
  });

  test("declares expected triggers", () => {
    expect(wf).toMatch(/on:/);
    expect(wf).toMatch(/push:/);
    expect(wf).toMatch(/pull_request:/);
    expect(wf).toMatch(/workflow_dispatch:/);
  });

  test("declares a job with checkout and the assign step", () => {
    expect(wf).toMatch(/assign-labels:/);
    expect(wf).toMatch(/actions\/checkout@v4/);
    expect(wf).toMatch(/runs-on:\s*ubuntu-latest/);
  });

  test("declares least-privilege permissions", () => {
    expect(wf).toMatch(/permissions:/);
    expect(wf).toMatch(/contents:\s*read/);
  });

  test("references script files that actually exist", () => {
    expect(wf).toContain("src/cli.ts");
    expect(existsSync(join(ROOT, "src/cli.ts"))).toBe(true);
    expect(wf).toContain("label-config.json");
    expect(existsSync(join(ROOT, "label-config.json"))).toBe(true);
  });
});

describe("workflow execution via act", () => {
  for (const c of CASES) {
    test(
      `case '${c.name}' runs through act and produces exact labels`,
      () => {
        const fixture = readFileSync(join(ROOT, c.fixture), "utf8");
        const dir = makeRepo(fixture);
        tempDirs.push(dir);

        const { output, status } = runAct(dir);

        // Persist every case's output to the required artifact.
        appendFileSync(
          ACT_RESULT,
          `\n${"=".repeat(70)}\n` +
            `CASE: ${c.name}\nFIXTURE: ${c.fixture}\n` +
            `EXPECTED LABELS=${c.expectedLabels}\nACT EXIT: ${status}\n` +
            `${"-".repeat(70)}\n${output}\n`,
        );

        // (1) act exited 0
        expect(status).toBe(0);
        // (2) every job succeeded
        expect(strip(output)).toContain("Job succeeded");
        // (3) EXACT expected values
        expect(marker(output, "LABELS")).toBe(c.expectedLabels);
        expect(marker(output, "LABEL_COUNT")).toBe(c.expectedCount);
        expect(marker(output, "UNMATCHED")).toBe(c.expectedUnmatched);
      },
      360_000,
    );
  }
});
