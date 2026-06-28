# Environment Matrix Generator

Generates a fully-expanded build matrix (JSON) from a configuration of OS
options, language versions and feature flags, suitable for a GitHub Actions
`strategy.matrix`. Supports `include`/`exclude` rules, `max-parallel`,
`fail-fast`, and validation against a maximum matrix size.

Implemented in **Python 3** (standard library only) using red/green TDD.

## Files

| Path | Purpose |
|------|---------|
| `matrix_generator.py` | The generator: expansion logic + CLI. |
| `matrix-config.json` | Default config the workflow reads. |
| `tests/test_matrix_generator.py` | Unit tests (TDD) for the core logic. |
| `tests/test_workflow.py` | Pipeline tests: every case runs **through `act`**, plus static workflow-structure checks. |
| `tests/fixtures/*.json` | Input fixtures for the act test cases. |
| `.github/workflows/environment-matrix-generator.yml` | CI pipeline that runs the generator and consumes the matrix. |
| `act-result.txt` | Captured output of every `act` run (artifact). |

## Config format

Mirrors a GitHub `strategy` block:

```json
{
  "matrix": {
    "os": ["ubuntu-latest", "windows-latest"],
    "version": ["3.11", "3.12"],
    "feature": ["minimal", "full"],
    "exclude": [{"os": "windows-latest", "version": "3.11"}],
    "include": [{"os": "ubuntu-latest", "version": "3.13", "experimental": true}]
  },
  "max-parallel": 4,
  "fail-fast": false,
  "max-size": 256
}
```

* **Dimensions** — every key under `matrix` except `include`/`exclude` is a
  product dimension. The cartesian product is expanded deterministically.
* **`exclude`** — subset match: any combination containing all the listed
  key/values is removed.
* **`include`** — GitHub's exact merge-or-append semantics (verified against
  the official fruit/animal documentation example in the unit tests): an
  include extends every base combination it can without overwriting a base
  dimension value; otherwise it becomes a new standalone job.
* **`max-parallel`** — positive integer (or omitted = GitHub default).
* **`fail-fast`** — boolean (default `true`, GitHub's default).
* **`max-size`** — ceiling on the expanded size (default `256`, GitHub's
  documented per-matrix job limit). Exceeding it is a hard error.

## Usage

```bash
python3 matrix_generator.py --config matrix-config.json
```

Output is the full result JSON plus machine-readable markers
(`MATRIX_SIZE=`, `MATRIX_JSON=`, ...). Pass `--set-output` to also write the
matrix/size/fail-fast/max-parallel to `$GITHUB_OUTPUT` so a downstream job can
consume it with `strategy: matrix: ${{ fromJSON(...) }}`.

## Testing

```bash
python3 -m pytest          # unit + workflow-structure + act pipeline tests
```

The pipeline tests build a throwaway git repo per fixture, run
`act push --rm`, append the output to `act-result.txt`, and assert the exact
expected matrix (size, combinations, max-parallel, fail-fast) for each input.
