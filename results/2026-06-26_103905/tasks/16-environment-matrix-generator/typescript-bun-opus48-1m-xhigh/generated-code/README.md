# Environment Matrix Generator

Generate a [GitHub Actions `strategy.matrix`](https://docs.github.com/en/actions/using-jobs/using-a-matrix-for-your-jobs)
(as JSON) from a configuration describing **OS options, language versions, and
feature flags**. Supports GitHub's `include` / `exclude` rules, `max-parallel`
and `fail-fast` settings, and validates that the generated matrix does not
exceed a configurable maximum size.

Implemented in **TypeScript** and run with **[Bun](https://bun.sh)**.

## Quick start

```bash
# Generate a matrix from a config file (pretty-printed)
bun run src/generate.ts --config fixtures/basic.json --pretty

# Or pipe config via stdin
cat fixtures/include-exclude.json | bun run src/generate.ts

# Or point at a file via the environment variable the workflow uses
MATRIX_CONFIG_FILE=fixtures/feature-flags.json bun run src/generate.ts
```

## Configuration format

```jsonc
{
  // Matrix axes. Any axis name works; "os", "node" and "feature" are typical.
  "matrix": {
    "os": ["ubuntu-latest", "windows-latest"],
    "node": ["18", "20"],
    "feature": ["default", "experimental"]
  },

  // Optional: GitHub `exclude` rules (partial match removes combinations).
  "exclude": [{ "os": "windows-latest", "node": "18" }],

  // Optional: GitHub `include` rules (extend matching rows, or add new ones).
  "include": [{ "os": "macos-latest", "node": "20", "experimental": true }],

  "maxParallel": 2,   // optional -> emitted as strategy.max-parallel
  "failFast": true,   // optional -> emitted as strategy.fail-fast
  "maxSize": 50       // optional -> generation fails if the matrix is bigger
}
```

### Output

The fully-expanded matrix is emitted under `matrix.include` — GitHub's idiom for
a dynamically-generated matrix — together with the count and metadata:

```json
{
  "matrix": {
    "include": [
      { "os": "ubuntu-latest", "node": "18" },
      { "os": "ubuntu-latest", "node": "20" }
    ]
  },
  "count": 2,
  "max-parallel": 2,
  "fail-fast": true
}
```

A consuming workflow uses it as:

```yaml
strategy:
  matrix: ${{ fromJson(needs.generate-matrix.outputs.matrix) }}
```

## `include` / `exclude` semantics

These follow GitHub's documented algorithm exactly (and are pinned to GitHub's
own published example in `tests/matrix.test.ts`):

1. Expand the axes into the cartesian product.
2. Apply `exclude` (a partial filter; an entry removes every combination whose
   listed keys all match).
3. Apply `include`: each entry tries to **extend** the original combinations it
   matches on the shared axis keys; non-axis keys are merged in (and may be
   overwritten by a later `include`). An entry that matches nothing becomes a
   new standalone combination. Because `include` runs after `exclude`, it can
   re-add an excluded combination.

## Project layout

| Path | Purpose |
|------|---------|
| `src/types.ts` | Shared interfaces (`MatrixConfig`, `GeneratedStrategy`, …) |
| `src/matrix.ts` | Pure matrix logic: cartesian product, exclude, include, validation, generation |
| `src/cli.ts` | Text⇄strategy helpers (`buildStrategy`, `formatStrategy`) |
| `src/generate.ts` | Executable CLI (argv / file / stdin / stdout / exit codes) |
| `fixtures/` | Example configurations, also used as test fixtures |
| `tests/` | Bun tests (see below) |
| `.github/workflows/environment-matrix-generator.yml` | CI pipeline that runs the generator |

## Tests

Everything is built test-first (red/green TDD).

```bash
# Fast unit + workflow-structure tests
bun test

# The full act integration harness (slow — runs the real workflow via Docker)
RUN_ACT=1 bun test tests/act.test.ts
```

* `tests/matrix.test.ts` — cartesian product, exclude, include (GitHub's
  canonical example), generation, max-size validation, config validation.
* `tests/cli.test.ts` / `tests/generate.test.ts` — the CLI core and the
  executable (via subprocess).
* `tests/workflow-structure.test.ts` — parses the workflow YAML, checks
  triggers / permissions / jobs / dependencies, verifies referenced files
  exist, and asserts `actionlint` passes.
* `tests/act.test.ts` — runs the workflow end-to-end through
  [`act`](https://github.com/nektos/act) for each fixture, saving all output to
  `act-result.txt` and asserting on the exact generated values and that every
  job succeeded. Opt-in via `RUN_ACT=1` so the normal `bun test` stays fast.

## CI pipeline

`.github/workflows/environment-matrix-generator.yml` runs on push / PR / a
weekly schedule / manual dispatch. It:

1. **generate-matrix** — checks out the repo, installs Bun, runs the unit tests,
   runs the generator over `matrix-config.json`, and exposes the matrix as a job
   output.
2. **build** — `needs: generate-matrix`; consumes the generated matrix via
   `fromJson(...)` and fans out one run per combination.
3. **summary** — `needs: [generate-matrix, build]`; fan-in confirmation.
