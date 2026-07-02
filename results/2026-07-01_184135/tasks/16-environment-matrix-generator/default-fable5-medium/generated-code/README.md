# Environment Matrix Generator

Generates a GitHub Actions `strategy` block (fail-fast, max-parallel, and a
flat `matrix.include` list) from a declarative JSON config describing OS
options, language versions, and feature flags. Built red/green TDD style in
Python (stdlib only).

## Usage

```bash
python3 matrix_generator.py fixtures/config.json
```

Config schema:

```jsonc
{
  "os": ["ubuntu-latest", "windows-latest"],        // any list key = a dimension
  "version": ["3.11", "3.12"],
  "features": {"tls": [true, false]},               // each flag -> its own dimension
  "exclude": [{"os": "windows-latest", "version": "3.11"}],  // partial match, GitHub semantics
  "include": [{"os": "ubuntu-latest", "version": "3.12", "coverage": true}],
  "fail_fast": false,                               // default true (GitHub default)
  "max_parallel": 2,                                // default: unlimited
  "max_size": 10                                    // default 256 (GitHub's job cap)
}
```

Errors (oversized matrix, malformed config, bad rules) exit 1 with a
message on stderr.

## Layout

- `matrix_generator.py` — library + CLI
- `tests/` — unit tests (stdlib `unittest`; run inside the CI container)
- `host_tests/` — workflow structure tests (YAML shape, referenced paths, actionlint)
- `fixtures/` — config fixtures used by the workflow
- `.github/workflows/environment-matrix-generator.yml` — pipeline:
  unit-tests → generate-matrix (+ oversized-config rejection check) →
  build (consumes the generated matrix via `fromJSON`) → summary
- `run_act_tests.py` — end-to-end harness: runs every test case through
  the workflow with `act push`, asserts exact outputs, writes `act-result.txt`

## Running the tests

```bash
python3 -m unittest discover -s tests -t .       # unit tests
python3 -m unittest discover -s host_tests -t .  # workflow structure tests
python3 run_act_tests.py                         # full pipeline via act (3 cases)
```
