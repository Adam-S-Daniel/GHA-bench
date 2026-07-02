# Environment Matrix Generator (TypeScript + Bun)

Generates a GitHub Actions `strategy.matrix` (as JSON) from a configuration of
OS options, language versions and feature flags — with include/exclude rules,
`max-parallel`, `fail-fast`, and a maximum-size validation (default: GitHub's
256-job limit).

## Usage

```bash
bun run src/cli.ts <config.json> [--pretty] [--matrix-only]
```

- default output: one line of compact JSON `{"strategy": {...}, "jobCount": N}`
- `--matrix-only`: prints just `{"include": [...]}` — spliceable into a
  workflow via `matrix: ${{ fromJSON(...) }}`
- exit code 1 with a meaningful message on stderr for any config error or
  when the matrix exceeds `maxSize`

### Config schema

```jsonc
{
  "os": ["ubuntu-latest", "macos-latest"],   // required, non-empty
  "languageVersions": ["18", "20"],          // required; numbers coerced to strings
  "featureFlags": ["telemetry"],             // optional -> `feature` dimension
  "exclude": [{ "os": "macos-latest", "language-version": "18" }], // partial match
  "include": [{ "os": "ubuntu-latest", "experimental": "true" }],  // GH semantics
  "maxParallel": 2,                          // optional -> strategy.max-parallel
  "failFast": false,                         // optional, default true (GH default)
  "maxSize": 10                              // optional, default 256 (GH limit)
}
```

Include/exclude follow GitHub Actions semantics: an exclude entry removes any
combination matching all of its keys; an include entry extends matching
combinations with extra keys, or is appended as a new combination when nothing
matches. Rule keys use the generated dimension names (`os`,
`language-version`, `feature`).

## Design

- `src/matrix.ts` — pure functions: `expandCombinations` (cartesian product),
  `applyExcludes`, `applyIncludes`, `validateConfig`, `generateMatrix`.
- `src/cli.ts` — thin CLI wrapper (file loading, JSON parsing, exit codes).
- Built red/green TDD, one cycle per feature: cartesian product → excludes →
  includes → strategy assembly → validation/size limit → CLI → workflow
  structure. Each cycle's tests were written first and observed failing.

## Tests

```bash
bun test                 # 32 tests: unit + CLI (spawned) + workflow structure
```

`tests/workflow.test.ts` parses `.github/workflows/environment-matrix-generator.yml`,
checks triggers/permissions/job wiring/referenced paths, and asserts
`actionlint` exits 0.

## CI pipeline (`.github/workflows/environment-matrix-generator.yml`)

1. `unit-tests` — full `bun test` suite (installs actionlint for the
   structure tests).
2. `generate-matrix` — runs every fixture in `fixtures/cases/` through the
   CLI via `scripts/run-cases.sh` (`ok-*` must succeed, `fail-*` must fail),
   then emits the `fixtures/pipeline.json` matrix as a job output.
3. `consume-matrix` — a real matrix job driven by
   `${{ fromJSON(needs.generate-matrix.outputs.matrix) }}`, proving the
   generated JSON is directly consumable by GitHub Actions.

## End-to-end verification through act

```bash
bun run scripts/act-harness.ts --reset
bun run scripts/act-harness.ts ok-basic
bun run scripts/act-harness.ts ok-include-exclude
bun run scripts/act-harness.ts fail-oversized
```

Each case builds a temp git repo containing the project plus only that case's
fixture, runs `act push --rm`, appends the full output to `act-result.txt`,
and asserts: act exit 0, the exact expected generator output for that input,
the exact pipeline matrix + matrix-job echoes, and exactly four
"Job succeeded" lines (no "Job failed").
