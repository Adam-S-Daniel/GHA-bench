/**
 * Validates the act harness's assertion logic against the REAL act output that
 * was captured in act-result.txt during the integration run. This lets us
 * confirm a fix to the assertion scoping (aggregate-job-only) without spending
 * another expensive `act` run: we replay the genuine, already-recorded output
 * through `checkCase` and assert every case now passes.
 */
import { describe, expect, it } from "bun:test";
import { existsSync, readFileSync } from "node:fs";
import { CASES, checkCase } from "../harness/run-act.ts";

const ACT_RESULT = new URL("../act-result.txt", import.meta.url).pathname;

/** One parsed case block from act-result.txt. */
interface Block {
  id: string;
  code: number;
  output: string;
}

/** Split the concatenated act-result.txt into per-case blocks. */
function parseBlocks(text: string): Block[] {
  const blocks: Block[] = [];
  // Each block: "CASE: <id>\nDESC: ...\nACT EXIT CODE: <n>\n---\n<output>".
  const re =
    /CASE: (\S+)\nDESC: [^\n]*\nACT EXIT CODE: (\d+)\n-+\n([\s\S]*?)\n=+\n/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(text)) !== null) {
    blocks.push({ id: m[1]!, code: Number(m[2]), output: m[3]! });
  }
  return blocks;
}

const hasArtifact = existsSync(ACT_RESULT);

describe("act harness assertions (replayed against real captured output)", () => {
  it.skipIf(!hasArtifact)("act-result.txt artifact exists", () => {
    expect(hasArtifact).toBe(true);
  });

  it.skipIf(!hasArtifact)(
    "every recorded case passes the (scoped) assertions",
    () => {
      const text = readFileSync(ACT_RESULT, "utf8");
      const blocks = parseBlocks(text);
      // There should be one recorded block per defined case.
      expect(blocks.length).toBe(CASES.length);

      for (const testCase of CASES) {
        const block = blocks.find((b) => b.id === testCase.id);
        expect(block, `no recorded output for case ${testCase.id}`).toBeDefined();

        const outcome = checkCase(testCase, block!.code, block!.output);
        if (!outcome.passed) {
          throw new Error(
            `case ${testCase.id} failed assertions:\n  ${outcome.failures.join("\n  ")}`,
          );
        }
        expect(outcome.passed).toBe(true);
      }
    },
  );
});
