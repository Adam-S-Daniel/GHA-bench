// Print a stable, machine-parseable summary of a generated matrix file.
//
// Used by the GitHub Actions workflow so the act-based test harness can assert
// on exact expected values (size, fail-fast, max-parallel, compact JSON).
//
// Usage: bun run summarize.ts <matrix.json>
import type { GeneratedMatrix } from "./matrix-generator";

const path = process.argv[2];
if (!path) {
  process.stderr.write("Usage: bun run summarize.ts <matrix.json>\n");
  process.exit(1);
}

const matrix = JSON.parse(await Bun.file(path).text()) as GeneratedMatrix;

// Emit clearly-delimited key=value lines that the harness greps for.
console.log(`MATRIX_SIZE=${matrix.size}`);
console.log(`FAIL_FAST=${matrix.failFast}`);
console.log(`MAX_PARALLEL=${matrix.maxParallel}`);
console.log(`MATRIX_JSON=${JSON.stringify(matrix.include)}`);
