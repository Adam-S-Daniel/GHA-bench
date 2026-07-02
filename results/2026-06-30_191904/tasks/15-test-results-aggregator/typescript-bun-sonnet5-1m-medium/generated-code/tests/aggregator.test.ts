import { describe, expect, test } from "bun:test";
import { runAggregator } from "../src/aggregator";

describe("runAggregator", () => {
  test("returns markdown and exit code 0 when there are failures present but reporting only (non-strict)", async () => {
    const outcome = await runAggregator({ resultsDir: "fixtures", strict: false });
    expect(outcome.markdown).toContain("# Test Results Summary");
    expect(outcome.exitCode).toBe(0);
  });

  test("returns exit code 1 in strict mode when the aggregate has failures", async () => {
    const outcome = await runAggregator({ resultsDir: "fixtures", strict: true });
    expect(outcome.exitCode).toBe(1);
  });

  test("surfaces a readable error message and exit code 1 for a missing directory", async () => {
    const outcome = await runAggregator({ resultsDir: "fixtures/nope", strict: false });
    expect(outcome.exitCode).toBe(1);
    expect(outcome.markdown).toContain("does not exist");
  });
});
