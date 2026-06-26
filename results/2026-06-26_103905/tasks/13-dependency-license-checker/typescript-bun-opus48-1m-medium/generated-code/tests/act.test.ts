import { beforeAll, describe, expect, test } from "bun:test";
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

// This harness drives every test case THROUGH the GitHub Actions workflow
// using `act`. It is skipped inside the act container itself (ACT=true) so
// the workflow's own `bun test` step does not recurse into act.
const INSIDE_ACT = process.env.ACT === "true";

const ROOT = join(import.meta.dir, "..");
const ACT_RESULT = join(ROOT, "act-result.txt");

// Project files copied into each isolated temp repo. We deliberately omit
// .git, node_modules, and the result artifact.
const COPY_ITEMS = [
  "src",
  "tests",
  "fixtures",
  "package.json",
  "tsconfig.json",
  ".actrc",
  ".github",
];

interface Fixtures {
  manifest: string; // package.json contents
  config: string; // license-config.json contents
  db: string; // license-db.json contents
}

interface ActOutcome {
  status: number;
  output: string;
}

/**
 * Build an isolated git repo containing the project + the case's fixtures,
 * then run `act push --rm` inside it and capture the combined output.
 */
function runActCase(name: string, fx: Fixtures): ActOutcome {
  const dir = mkdtempSync(join(tmpdir(), "dlc-act-"));
  try {
    for (const item of COPY_ITEMS) {
      cpSync(join(ROOT, item), join(dir, item), { recursive: true });
    }
    // Write this case's fixture data, overwriting the defaults.
    writeFileSync(join(dir, "fixtures/package.json"), fx.manifest);
    writeFileSync(join(dir, "fixtures/license-config.json"), fx.config);
    writeFileSync(join(dir, "fixtures/license-db.json"), fx.db);

    // act needs a git repo with a commit to evaluate a push event.
    const git = (args: string[]) =>
      spawnSync("git", args, { cwd: dir, encoding: "utf8" });
    git(["init", "-q", "-b", "main"]);
    git(["config", "user.email", "ci@example.com"]);
    git(["config", "user.name", "CI"]);
    git(["add", "-A"]);
    git(["commit", "-q", "-m", "fixture"]);

    const res = spawnSync(
      "act",
      [
        "push",
        "--rm",
        "--pull=false",
        "-W",
        ".github/workflows/dependency-license-checker.yml",
      ],
      { cwd: dir, encoding: "utf8", timeout: 300_000 },
    );
    const output = `${res.stdout ?? ""}${res.stderr ?? ""}`;

    // Persist the output for this case to the required artifact.
    appendFileSync(
      ACT_RESULT,
      `\n===== ACT CASE: ${name} =====\n${output}\n===== END CASE: ${name} (exit=${res.status}) =====\n`,
    );

    return { status: res.status ?? -1, output };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

describe.skipIf(INSIDE_ACT)("workflow via act", () => {
  beforeAll(() => {
    // Start the artifact fresh for this harness run.
    writeFileSync(
      ACT_RESULT,
      `Dependency License Checker — act run results\n`,
    );
  });

  test(
    "case 1: all licenses approved -> COMPLIANT",
    () => {
      const out = runActCase("all-approved", {
        manifest: JSON.stringify({
          name: "app",
          dependencies: { lodash: "4.17.21", express: "4.18.2" },
        }),
        config: JSON.stringify({ allow: ["MIT", "ISC"], deny: ["GPL-3.0"] }),
        db: JSON.stringify({ lodash: "MIT", express: "MIT" }),
      });

      expect(out.status).toBe(0);
      expect(out.output).toContain("Job succeeded");
      // Exact expected report values for this input:
      expect(out.output).toContain("lodash@4.17.21  license=MIT  status=APPROVED");
      expect(out.output).toContain("express@4.18.2  license=MIT  status=APPROVED");
      expect(out.output).toContain(
        "Total: 2  Approved: 2  Denied: 0  Unknown: 0",
      );
      expect(out.output).toContain("Verdict: COMPLIANT");
    },
    300_000,
  );

  test(
    "case 2: a denied license -> NOT COMPLIANT",
    () => {
      const out = runActCase("denied", {
        manifest: JSON.stringify({
          name: "app",
          dependencies: { "evil-lib": "1.0.0", lodash: "4.17.21" },
        }),
        config: JSON.stringify({ allow: ["MIT"], deny: ["GPL-3.0"] }),
        db: JSON.stringify({ "evil-lib": "GPL-3.0", lodash: "MIT" }),
      });

      expect(out.status).toBe(0);
      expect(out.output).toContain("Job succeeded");
      expect(out.output).toContain(
        "evil-lib@1.0.0  license=GPL-3.0  status=DENIED",
      );
      expect(out.output).toContain("lodash@4.17.21  license=MIT  status=APPROVED");
      expect(out.output).toContain(
        "Total: 2  Approved: 1  Denied: 1  Unknown: 0",
      );
      expect(out.output).toContain("Verdict: NOT COMPLIANT");
    },
    300_000,
  );

  test(
    "case 3: an unknown license -> NOT COMPLIANT",
    () => {
      const out = runActCase("unknown", {
        manifest: JSON.stringify({
          name: "app",
          dependencies: { "mystery-pkg": "2.0.0" },
        }),
        config: JSON.stringify({ allow: ["MIT"], deny: ["GPL-3.0"] }),
        db: JSON.stringify({}),
      });

      expect(out.status).toBe(0);
      expect(out.output).toContain("Job succeeded");
      expect(out.output).toContain(
        "mystery-pkg@2.0.0  license=<none>  status=UNKNOWN",
      );
      expect(out.output).toContain(
        "Total: 1  Approved: 0  Denied: 0  Unknown: 1",
      );
      expect(out.output).toContain("Verdict: NOT COMPLIANT");
    },
    300_000,
  );
});
