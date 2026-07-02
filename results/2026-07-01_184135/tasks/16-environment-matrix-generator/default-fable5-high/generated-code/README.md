# Environment Matrix Generator

Generates a GitHub Actions `strategy.matrix` JSON document from a declarative
config describing OS options, language versions, and feature flags — with
`include`/`exclude` rules, `fail-fast`, `max-parallel`, and a maximum-size
guard. Built test-first (red/green TDD) in Python (stdlib only).

## Usage

```bash
python3 matrix_generator.py fixtures/config.json
```

Prints one line of compact JSON on success (exit 0); on any error prints a
meaningful message to stderr and exits non-zero.

## Config format

```json
{
  "matrix": {
    "os": ["ubuntu-latest", "macos-latest"],
    "node": ["18", "20"],
    "feature-flag": ["stable", "beta"],
    "exclude": [ { "os": "macos-latest", "node": "18" } ],
    "include": [ { "os": "ubuntu-latest", "node": "20", "coverage": true } ]
  },
  "fail-fast": false,
  "max-parallel": 4,
  "max-size": 256
}
```

- Axes (any key other than `include`/`exclude`) are non-empty lists of
  scalars; the matrix is their cartesian product.
- `exclude` entries remove any combination they **partially** match
  (GitHub Actions semantics), applied before `include`.
- `include` entries expand every combination they match without overwriting
  original axis values; an entry matching nothing becomes a new standalone
  combination. Later includes may overwrite keys added by earlier includes.
- `fail-fast` defaults to `true`; `max-parallel` is omitted from the output
  when unset (unlimited); `max-size` defaults to 256 (GitHub's own limit) and
  the generator fails if the final matrix exceeds it.

## Output shape

```json
{
  "fail-fast": false,
  "max-parallel": 4,
  "count": 4,
  "matrix": { "include": [ {"os": "...", "node": "..."}, ... ] }
}
```

A downstream job consumes it with the standard dynamic-matrix pattern:

```yaml
strategy:
  matrix: ${{ fromJSON(needs.generate-matrix.outputs.strategy1).matrix }}
```

## Layout

- `matrix_generator.py` — library + CLI.
- `tests/test_matrix_generator.py` — unit tests, one class per TDD cycle.
- `tests/test_workflow_structure.py` — parses the workflow YAML, checks
  triggers/jobs/needs/outputs, referenced paths, and runs actionlint where
  available.
- `fixtures/` — test-case configs (`config.json` is case 1's copy; the
  workflow reads case 2 and the invalid oversized config directly).
- `.github/workflows/environment-matrix-generator.yml` — CI pipeline:
  `unit-tests` → `generate-matrix` (both cases + error path) →
  `consume-case1`/`consume-case2` fan out over the generated matrices.
- `run_act_tests.sh` — end-to-end harness; runs everything through the
  workflow with `act push --rm --pull=false` and writes `act-result.txt`,
  asserting exact expected JSON, per-job combinations, and job successes.
