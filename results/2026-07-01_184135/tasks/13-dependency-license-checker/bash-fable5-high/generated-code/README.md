# Dependency License Checker

A bash dependency license compliance checker, built test-first with bats-core
and wired into a GitHub Actions pipeline validated end-to-end with nektos/act.

## What it does

`license-checker.sh` parses a dependency manifest, looks up each dependency's
license, classifies it against an allow/deny policy, and prints a compliance
report:

```
./license-checker.sh --manifest package.json --config config.txt --license-db licenses.tsv
```

- **Manifests:** `package.json` (dependencies + devDependencies, parsed with
  jq) and `requirements.txt` (pinned `==` and range specifiers; comments and
  blank lines skipped).
- **Policy config:** lines of `allow=<LICENSE>` / `deny=<LICENSE>`. The
  deny-list wins if a license appears on both.
- **License lookup (mocked):** a TSV file of `name<TAB>license` stands in for
  a real registry query. Injecting the file keeps every test hermetic; a
  dependency missing from the DB reports license `UNKNOWN`.
- **Statuses:** `approved` (on allow-list), `denied` (on deny-list),
  `unknown` (unlisted license or missing from the DB).
- **Exit codes:** `0` clean report, `1` denied license found, `2` usage/input
  error (missing files, bad JSON, malformed lines, bad config).

## Layout

| Path | Purpose |
|---|---|
| `license-checker.sh` | the checker |
| `test/license_checker.bats` | unit suite (15 tests, written red/green TDD) |
| `test/workflow.bats` | workflow structure tests (actionlint + YAML shape) |
| `test/fixtures/` | manifests, policy config, mock license DB |
| `ci-input/` | default manifest/config/DB the CI pipeline checks |
| `.github/workflows/dependency-license-checker.yml` | CI pipeline |
| `scripts/run_act_tests.sh` | end-to-end harness driving the pipeline via act |
| `act-result.txt` | captured act output from the last harness run |

## CI pipeline

Two jobs: `test` runs the bats suite in the container; `license-check`
(needs `test`) runs the checker on whatever manifest `ci-input/` holds and
publishes the report to the job summary. `FAIL_ON_DENIED` (default `false`)
switches between report-only mode and a hard merge gate.

## Testing

```
bats test/                  # unit + workflow structure tests (host)
./scripts/run_act_tests.sh  # every case through the real pipeline via act
```

The act harness builds a temp git repo per case, swaps in that case's
`ci-input` fixtures, runs `act push --rm`, and asserts exact report rows,
exact summary counts, and that both jobs succeeded.
