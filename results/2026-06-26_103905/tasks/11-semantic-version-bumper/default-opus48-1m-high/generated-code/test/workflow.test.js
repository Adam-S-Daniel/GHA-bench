// Structure tests for the GitHub Actions workflow.
//
// These validate the workflow file itself (triggers, jobs, steps, script
// references) and that actionlint passes. They are intentionally kept OUT of
// the in-container test run (the workflow runs only test/bumper.test.js) because
// they shell out to actionlint, which lives on the host, not in the act image.

import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const workflowPath = path.join(root, ".github/workflows/semantic-version-bumper.yml");
const workflow = fs.readFileSync(workflowPath, "utf8");

describe("workflow structure", () => {
  test("declares all four expected trigger events", () => {
    const onBlock = workflow.slice(workflow.indexOf("\non:"));
    for (const trigger of ["push:", "pull_request:", "workflow_dispatch:", "schedule:"]) {
      assert.match(onBlock, new RegExp(`\\n\\s+${trigger.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}`),
        `missing trigger: ${trigger}`);
    }
  });

  test("defines a bump job on ubuntu-latest", () => {
    assert.match(workflow, /\njobs:/);
    assert.match(workflow, /\n {2}bump:/);
    assert.match(workflow, /runs-on:\s*ubuntu-latest/);
  });

  test("checks out the repo with actions/checkout@v4", () => {
    assert.match(workflow, /uses:\s*actions\/checkout@v4/);
  });

  test("declares permissions and env blocks", () => {
    assert.match(workflow, /\npermissions:/);
    assert.match(workflow, /\nenv:/);
  });

  test("references src/cli.js and that file exists on disk", () => {
    assert.match(workflow, /node\s+src\/cli\.js/);
    assert.ok(fs.existsSync(path.join(root, "src/cli.js")), "src/cli.js must exist");
  });

  test("invokes the unit test suite that exists on disk", () => {
    assert.match(workflow, /node --test test\/bumper\.test\.js/);
    assert.ok(fs.existsSync(path.join(root, "test/bumper.test.js")));
  });
});

describe("actionlint", () => {
  test("passes with exit code 0", () => {
    // execFileSync throws on non-zero exit; reaching the assert means exit 0.
    let exitCode = 1;
    try {
      execFileSync("actionlint", [workflowPath], { stdio: "pipe" });
      exitCode = 0;
    } catch (e) {
      exitCode = e.status ?? 1;
      assert.fail(`actionlint failed (exit ${exitCode}):\n${e.stdout}\n${e.stderr}`);
    }
    assert.equal(exitCode, 0);
  });
});
