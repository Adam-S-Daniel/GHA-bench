# Secret Rotation Validator

A small Bash tool that reads a configuration of secrets and their rotation
metadata, decides which ones are **expired**, **expiring soon** (warning), or
**ok**, and emits a rotation report grouped by urgency in either **markdown**
or **JSON**.

It is wired into a GitHub Actions pipeline that lints the script, runs the
test suite, and produces a rotation report on every push / PR / weekly
schedule.

```
.
├── secret-rotation-validator.sh          # the tool
├── fixtures/                             # mock secret configurations
│   ├── mixed.json  all-ok.json  boundary.json  empty.json
│   ├── bad-date.json  missing-field.json   # error-path fixtures
│   └── ci-secrets.json                   # config the workflow audits
├── test/
│   ├── unit/validator.bats               # TDD unit tests (run inside CI)
│   ├── structure/workflow.bats           # workflow structure tests
│   └── act/act_harness.bats              # end-to-end tests *through* act
├── .github/workflows/secret-rotation-validator.yml
├── run-tests.sh
└── act-result.txt                        # captured act output (artifact)
```

## The tool

```text
Usage: secret-rotation-validator.sh [OPTIONS]

  -c, --config FILE       Secrets config JSON file (default: stdin, or "-")
  -w, --warning-days N    Warning window in days (default: 14)
  -f, --format FORMAT     Output format: markdown | json (default: markdown)
  -n, --now DATE          Pin "today" to DATE (YYYY-MM-DD); also $SRV_NOW
      --fail-on LEVEL     Exit 1 when worst status >= LEVEL:
                          none | warning | expired (default: none)
  -h, --help              Show help
```

### Config format

```json
{
  "secrets": [
    {
      "name": "db-password",
      "last_rotated": "2026-01-01",
      "rotation_policy_days": 90,
      "required_by": ["api", "worker"]
    }
  ]
}
```

`name`, `last_rotated` (YYYY-MM-DD) and `rotation_policy_days` are required;
`required_by` is optional metadata.

### Classification

For each secret, relative to *today*:

```
expiry_date = last_rotated + rotation_policy_days
days_until  = expiry_date - today        (whole days)

expired   when days_until <  0
warning   when 0 <= days_until <= warning_window
ok        when days_until >  warning_window
```

"Today" defaults to the live UTC date but can be pinned with `--now`/`$SRV_NOW`
so reports and tests are deterministic.

### Output

* **markdown** — a report with a summary count table plus one section per
  urgency group (Expired / Warning / OK), each a table of the matching secrets.
* **json** — a machine-readable document: `generated_at`, `warning_days`, a
  `summary` object and a `secrets` array with the computed `status`,
  `expiry_date` and `days_until_expiry` for every secret.

### Exit codes

| code | meaning |
|------|---------|
| 0 | success |
| 1 | `--fail-on` policy gate tripped (report still printed) |
| 2 | usage error (bad arguments, missing/unreadable config) |
| 3 | invalid config content (bad JSON / structure / field / date) |

### Examples

```bash
# Markdown report, default 14-day warning window
./secret-rotation-validator.sh --config fixtures/mixed.json

# JSON, 30-day window, pinned date
./secret-rotation-validator.sh -c fixtures/mixed.json -w 30 -f json -n 2026-06-28

# Use as a CI gate: fail the build if anything is expired
./secret-rotation-validator.sh -c fixtures/mixed.json --fail-on expired
```

## Tests (red/green TDD)

The tool was built test-first with [bats-core](https://github.com/bats-core/bats-core).
There are three suites:

* `test/unit/validator.bats` — drives the script directly with a pinned date so
  every assertion is deterministic. These are the red/green TDD tests and are
  exactly what the CI pipeline runs, so running the workflow under `act`
  executes all of them.
* `test/structure/workflow.bats` — parses the workflow YAML and asserts its
  shape (triggers, jobs, dependency chain, permissions, that it references the
  script/fixtures that exist, and that `actionlint` passes).
* `test/act/act_harness.bats` — the end-to-end harness: for each case it builds
  an isolated temp git repo seeded with that case's fixture, runs
  `act push --rm`, appends the output to `act-result.txt`, and asserts act
  exited 0, every job reports *Job succeeded*, the in-pipeline unit suite
  passed, and the rotation report contains the **exact** expected metrics.

```bash
./run-tests.sh          # fast: static checks + unit + structure
./run-tests.sh --all    # also the slow act harness
```

## GitHub Actions workflow

`.github/workflows/secret-rotation-validator.yml` runs on push, pull_request, a
weekly `schedule` (Monday 06:00 UTC), and `workflow_dispatch` (with an optional
`warning_days` input). It uses least-privilege `permissions: contents: read`
and three dependent jobs:

1. **lint** — `bash -n` + `shellcheck` on the script.
2. **test** — installs bats and runs `bats --tap test/unit/`.
3. **report** — runs the validator against `fixtures/ci-secrets.json`, writes
   the markdown report to the job summary, and surfaces the JSON metrics.

### Running it locally with `act`

The container image is built locally (no registry), so disable image pulling:

```bash
act push --pull=false -P ubuntu-latest=act-ubuntu-pwsh:latest
```

`act-result.txt` is a captured artifact of two such runs (a mixed fixture and
an all-ok fixture) demonstrating the pipeline succeeding end-to-end.
