// Print a stable, machine-parseable one-line-per-field summary of a
// generated matrix file. The workflow runs this after matrix-generator.ts so
// the act-based test harness (workflow.test.ts) can grep exact values out of
// otherwise-noisy `act` log output, instead of trying to parse pretty-printed
// JSON that act interleaves with its own log prefixes on every line.
//
// Usage: bun run format-summary.ts <matrix.json>
import type { GeneratedMatrix } from "./matrix-generator";

const path = process.argv[2];
if (!path) {
  process.stderr.write("Usage: bun run format-summary.ts <matrix.json>\n");
  process.exit(1);
}

const matrix = JSON.parse(await Bun.file(path).text()) as GeneratedMatrix;

console.log(`MATRIX_SIZE=${matrix.matrixSize}`);
console.log(`FAIL_FAST=${matrix["fail-fast"]}`);
console.log(`MAX_PARALLEL=${matrix["max-parallel"]}`);
console.log(`MATRIX_JSON=${JSON.stringify(matrix.matrix.include)}`);
