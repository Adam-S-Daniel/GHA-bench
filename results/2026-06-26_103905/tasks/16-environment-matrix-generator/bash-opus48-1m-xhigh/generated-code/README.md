# Environment Matrix Generator

Generate a [GitHub Actions `strategy.matrix`](https://docs.github.com/actions/using-jobs/using-a-matrix-for-your-jobs)
build matrix (as JSON) from a configuration describing OS options, language
versions, and feature flags. Supports `include`/`exclude` rules, `max-parallel`
and `fail-fast` configuration, and validates that the expanded matrix does not
exceed a maximum job count.

## Files

| File | Purpose |
|------|---------|
| `matrix-generator.sh` | The generator. Reads a JSON config, applies the matrix algebra with `jq`, validates size, and prints the result. |
| `run-fixtures.sh` | Drives the generator across every fixture and verifies exact expected output. Run by the CI workflow. |
| `tests/environment-matrix-generator.bats` | bats-core test suite. Runs the whole pipeline through `act` and asserts on exact values, plus workflow-structure and lint checks. |
| `tests/fixtures/*` | Input configs and known-good expected outputs. |
| `tests/check_structure.py` | Parses the workflow YAML and asserts its structure. |
| `examples/demo-config.json` | Example config consumed by the workflow's build job. |
| `.github/workflows/environment-matrix-generator.yml` | CI/CD pipeline that validates the generator and consumes its output as a real matrix. |

## Config schema

```json
{
  "dimensions":   { "os": ["ubuntu-latest"], "node": ["18", "20"], "feature": ["minimal", "full"] },
  "include":      [ { "os": "windows-latest", "node": "20", "coverage": true } ],
  "exclude":      [ { "os": "ubuntu-latest", "node": "18" } ],
  "fail-fast":    false,
  "max-parallel": 4,
  "max-size":     256
}
```

* **dimensions** — named axes; the cartesian product forms the base combinations.
* **exclude** — removes any base combination that matches all of an entry's keys.
* **include** — follows GitHub's semantics: an entry merges into base combinations
  whose original-dimension keys all match (adding/overwriting extra keys), or, if
  it matches none, becomes a brand-new combination.
* **fail-fast** — emitted into the strategy block (default `true`).
* **max-parallel** — emitted into the strategy block when provided.
* **max-size** — the generator errors (exit 3) if the expanded job count exceeds
  this limit (default `256`, GitHub's real per-run limit).

## Usage

```bash
# Full strategy block (default)
./matrix-generator.sh --config config.json

# Just the matrix block (for $GITHUB_OUTPUT)
./matrix-generator.sh --config config.json --output matrix | jq -c .

# Number of expanded jobs, or every expanded combination
./matrix-generator.sh -c config.json --output size
./matrix-generator.sh -c config.json --output expand

# Read from stdin; override the size limit
cat config.json | ./matrix-generator.sh --max-size 64
```

Exit codes: `0` success · `1` usage/validation error · `2` missing `jq` or
unreadable config · `3` matrix exceeds `max-size`.

## Testing

```bash
bats tests/environment-matrix-generator.bats
```

The suite builds an isolated temp git repo, runs the workflow once via
`act push --rm`, captures everything to `act-result.txt`, and asserts on the
exact per-fixture results, that `act` exited `0`, and that every job succeeded.
