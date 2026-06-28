#!/usr/bin/env bun
/**
 * One-shot smoke runner used during development to validate the workflow runs
 * end-to-end in `act` and to capture the exact output strings the test harness
 * asserts on. Not part of the test suite. Run: `bun run scripts/smoke-act.ts`.
 */
import { runActCase, countJobSucceeded } from "../tests/act-harness";

const mixed = await Bun.file("fixtures/secrets.json").text();
const run = runActCase("smoke-mixed", mixed);

console.log("=== SMOKE SUMMARY ===");
console.log("act exit code:", run.exitCode);
console.log("Job succeeded count:", countJobSucceeded(run.output));
console.log(
  'has "ROTATION_VERDICT total=4 expired=1 warning=1 ok=2":',
  run.output.includes("ROTATION_VERDICT total=4 expired=1 warning=1 ok=2"),
);
console.log('has \'"expired": 1\':', run.output.includes('"expired": 1'));
console.log("has AWS expiry 2026-04-01:", run.output.includes("2026-04-01"));
console.log("\n=== RELEVANT GREPS ===");
for (const line of run.output.split("\n")) {
  if (/succeeded|failed|ROTATION_VERDICT|"urgency"|"total"|"expired"|AWS_ACCESS_KEY|Job/.test(line)) {
    console.log(line);
  }
}
