// Parses the captured `act push` output (act-result.txt) and asserts on the
// exact expected values for each fixture, per the task's "all tests run
// through act" requirement. This does not re-run act; it verifies the
// artifact produced by the act run already captured in act-result.txt.

import { describe, expect, test } from "bun:test";

const ACT_RESULT_PATH = "act-result.txt";

describe("act-result.txt", () => {
  test("exists as a required artifact", async () => {
    expect(await Bun.file(ACT_RESULT_PATH).exists()).toBe(true);
  });

  test("shows both jobs succeeded", async () => {
    const text = await Bun.file(ACT_RESULT_PATH).text();

    const succeeded = text.match(/Job succeeded/g) ?? [];
    const failed = text.match(/Job failed/g) ?? [];

    expect(succeeded.length).toBeGreaterThanOrEqual(2);
    expect(failed.length).toBe(0);
  });

  test("mixed fixture: exact exit_code and expired_count outputs", async () => {
    const text = await Bun.file(ACT_RESULT_PATH).text();

    expect(text).toContain("::set-output:: exit_code=1");
    expect(text).toContain("::set-output:: expired_count=1");
  });

  test("mixed fixture: exact per-secret markdown rows", async () => {
    const text = await Bun.file(ACT_RESULT_PATH).text();

    expect(text).toContain("| db-password | -91 | 2026-01-01 | 90 | api-service, worker-service |");
    expect(text).toContain("| api-key | 10 | 2026-04-12 | 90 | billing-service |");
    expect(text).toContain("| tls-cert | 80 | 2026-06-21 | 90 | edge-proxy |");
  });

  test("all-ok fixture: exact bucket counts and rows", async () => {
    const text = await Bun.file(ACT_RESULT_PATH).text();

    expect(text).toContain("## Expired (0)");
    expect(text).toContain("## Warning (0)");
    expect(text).toContain("## OK (2)");
    expect(text).toContain("| cdn-origin-token | 49 | 2026-06-20 | 60 | cdn-edge |");
    expect(text).toContain("| webhook-signing-secret | 54 | 2026-06-25 | 60 | notifications-service |");
  });

  test("the classification assertion step passed inside the act run", async () => {
    const text = await Bun.file(ACT_RESULT_PATH).text();

    expect(text).toContain("Mixed fixture correctly classified: 1 expired secret, exit code 1.");
  });
});
