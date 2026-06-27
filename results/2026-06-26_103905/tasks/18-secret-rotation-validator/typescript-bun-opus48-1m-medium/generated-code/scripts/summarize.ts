// Small helper used by the CI workflow to emit a single, machine-readable
// summary line from a JSON rotation report. Keeping it separate from the CLI
// avoids YAML escaping headaches in the workflow and gives the act test
// harness a stable line to assert exact values against.
//
// Usage: bun run scripts/summarize.ts <report.json>
// Prints: ROTATION_SUMMARY total=<n> expired=<n> warning=<n> ok=<n>
import { readFileSync } from "node:fs";

const path = Bun.argv[2];
if (!path) {
  console.error("Usage: bun run scripts/summarize.ts <report.json>");
  process.exit(2);
}

try {
  const report = JSON.parse(readFileSync(path, "utf8"));
  const s = report.summary;
  if (!s || typeof s.total !== "number") {
    throw new Error("report is missing a valid summary");
  }
  console.log(
    `ROTATION_SUMMARY total=${s.total} expired=${s.expired} warning=${s.warning} ok=${s.ok}`,
  );
} catch (err) {
  console.error(
    `Failed to summarize "${path}": ${err instanceof Error ? err.message : String(err)}`,
  );
  process.exit(2);
}
