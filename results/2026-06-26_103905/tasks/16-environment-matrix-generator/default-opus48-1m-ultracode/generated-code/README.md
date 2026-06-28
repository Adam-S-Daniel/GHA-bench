# Environment Matrix Generator

Generate a GitHub Actions build matrix (as JSON) from a configuration that
describes OS options, language versions, and feature flags. Supports
`include`/`exclude` rules, `max-parallel` and `fail-fast` configuration, and
validates that the matrix does not exceed a maximum size.

## Files

| Path | Purpose |
|------|---------|
| `matrix_generator.py` | The generator. Pure Python 3 stdlib (no dependencies). |
| `matrix-config.json` | Default config the workflow reads. |
| `tests/test_matrix_generator.py` | Unit tests (red/green TDD). |
| `tests/test_workflow_structure.py` | Workflow structure + actionlint tests. |
| `tests/test_workflow_act.py` | End-to-end tests: every case runs through the workflow via `act`. |
| `tests/fixtures/*.json` | Input configs with known-good expected matrices. |
| `.github/workflows/environment-matrix-generator.yml` | The CI/CD pipeline. |
| `act-result.txt` | Captured `act` output for every test case (generated artifact). |

## Config schema

The config mirrors a real GitHub Actions `strategy:` block — `include`/`exclude`
live *inside* `matrix` next to the axes, while `max-parallel`, `fail-fast`, and
`max-size` are siblings of `matrix`:

```json
{
  "matrix": {
    "os": ["ubuntu-latest", "windows-latest"],
    "version": ["18", "20", "22"],
    "exclude": [ { "os": "windows-latest", "version": "18" } ],
    "include": [ { "os": "ubuntu-latest", "version": "22", "coverage": "true" } ]
  },
  "max-parallel": 4,
  "fail-fast": false,
  "max-size": 25
}
```

* **Axes** — every key in `matrix` other than `include`/`exclude` is an axis.
  The base matrix is their cartesian product.
* **exclude** — partial specs; any combination they are a subset of is removed.
* **include** — applied with GitHub's exact algorithm: an entry whose
  original-axis keys match existing combinations is merged into them (adding new
  keys, never overwriting axis values); an entry that matches none becomes a new
  standalone combination. (Verified against GitHub's documented example in the
  unit tests.)
* **max-size** — the matrix is flagged invalid if it produces more combinations
  than this (or zero combinations).

## Output

The expanded matrix is emitted in pure `include` form — directly consumable by
`strategy.matrix: ${{ fromJSON(...) }}` — alongside validation metadata:

```json
{
  "matrix": { "include": [ { "os": "ubuntu-latest", "version": "18" }, ... ] },
  "fail-fast": false,
  "max-parallel": 4,
  "size": 5,
  "max_size": 25,
  "valid": true,
  "errors": []
}
```

## Usage

```bash
python3 matrix_generator.py matrix-config.json          # pretty JSON to stdout
python3 matrix_generator.py matrix-config.json --compact
cat matrix-config.json | python3 matrix_generator.py    # read from stdin
python3 matrix_generator.py config.json --max-size 10   # override max-size
python3 matrix_generator.py config.json --strict        # exit 2 if invalid
python3 matrix_generator.py config.json --github-output  # write $GITHUB_OUTPUT
```

Exit codes: `0` success (check the `valid` field), `1` bad input
(missing file / malformed JSON / schema error), `2` invalid matrix under
`--strict`.

## How the workflow uses it

1. **`generate-matrix`** checks out the repo, runs the generator against the
   config, writes the matrix + metadata to `$GITHUB_OUTPUT`, and validates size.
2. **`build`** depends on `generate-matrix`, is gated on
   `needs.generate-matrix.outputs.valid == 'true'`, and fans out one job per
   generated combination via `matrix: ${{ fromJSON(...) }}`.

## Running the tests

```bash
python3 -m pytest tests/                       # everything (unit + structure + act)
python3 -m pytest tests/test_matrix_generator.py   # fast unit tests only
```

The act suite spins up an isolated git repo per fixture, runs `act push --rm`,
appends the output to `act-result.txt`, and asserts on exact expected values.

## Methodology

Built with red/green TDD: each piece of functionality (cartesian product →
exclude → include → validation → CLI) started as a failing test, then the
minimum code to pass, then refactor. The act-based suite is the authoritative
acceptance layer — every functional scenario is exercised through the real
GitHub Actions pipeline, not just the script in isolation.
