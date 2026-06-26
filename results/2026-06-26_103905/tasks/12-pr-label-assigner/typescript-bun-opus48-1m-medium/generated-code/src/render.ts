// Deterministic rendering of an assignment result.
//
// The output is designed to be both human-readable and machine-parseable: the
// CI workflow and the act test harness assert on the stable `LABELS=`,
// `LABEL_COUNT=` and `UNMATCHED=` marker lines.
import type { AssignmentResult } from "./label-assigner.ts";

export function renderResult(
  result: AssignmentResult,
  fileCount: number,
): string {
  const lines: string[] = [];
  lines.push("PR Label Assigner");
  lines.push("=================");
  lines.push(`Changed files: ${fileCount}`);

  if (result.labels.length > 0) {
    lines.push(`Matched labels (${result.labels.length}):`);
    for (const label of result.labels) lines.push(`  - ${label}`);
  } else {
    lines.push("Matched labels (0): <none>");
  }

  if (result.unmatched.length > 0) {
    lines.push(`Files matching no rule: ${result.unmatched.join(", ")}`);
  }

  // Stable machine-parseable markers (one value per line).
  lines.push(`LABELS=${result.labels.join(",")}`);
  lines.push(`LABEL_COUNT=${result.labels.length}`);
  lines.push(`UNMATCHED=${result.unmatched.join(",")}`);

  return lines.join("\n");
}
