# Dependency License Checker

A Bash tool that parses a dependency manifest, looks up each dependency's
license, classifies it against an allow-list / deny-list, and emits a
compliance report. Built test-first with [bats-core](https://github.com/bats-core/bats-core)
and wired into a GitHub Actions pipeline validated end-to-end with
[`act`](https://github.com/nektos/act).

## Usage

```bash
./license-checker.sh \
  --manifest    test/fixtures/package.json \
  --allow-list  test/fixtures/allow-list.txt \
  --deny-list   test/fixtures/deny-list.txt \
  --license-db  test/fixtures/license-db.csv
```

Run `./license-checker.sh --help` for all options.

### Inputs

- **Manifest** — `package.json` (npm) or `requirements.txt` (pip). The type is
  auto-detected from the file name, or forced with `--type npm|pip`.
- **Allow-list / Deny-list** — plain-text files, one license identifier per
  line (`#` comments allowed).
- **License database** — a `name,license` CSV. This is the **mockable** license
  lookup: in production it would query npm/PyPI; tests inject a fixture CSV so
  results are deterministic and offline.

### Output and exit codes

A per-dependency table plus a summary line and a `PASS`/`FAIL` result. Each
dependency is classified as:

- `APPROVED` — license is in the allow-list
- `DENIED` — license is in the deny-list (deny-list wins any conflict)
- `UNKNOWN` — license could not be found, or is in neither list

Exit codes: `0` all approved, `1` a denied license, `2` an unknown license
(none denied), `3` input error, `64` CLI usage error. `--no-fail` forces `0`
so CI can always produce the report and gate separately.

## Testing

The work was done red/green TDD: a failing bats test first, then the minimum
code to pass, then refactor.

```bash
bats test/license-checker.bats   # fast unit tests of every function + the CLI
bats test/workflow.bats          # workflow structure tests + act integration
```

`test/workflow.bats` runs the **whole pipeline through `act`** for each fixture
case: it builds a throwaway git repo, runs `act push --rm`, appends the output
to `act-result.txt`, and asserts on the *exact* expected report values and that
every job reports `Job succeeded`.

## CI

`.github/workflows/dependency-license-checker.yml` runs on push, pull request,
a weekly schedule, and manual dispatch. The `license-check` job runs the script
and exposes the result as a job output; the dependent `enforce-policy` job
surfaces that result. The workflow passes `actionlint` cleanly.
