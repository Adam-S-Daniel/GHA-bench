# Dependency License Checker

A small, dependency-light Bash tool that parses a dependency manifest
(`package.json` or `requirements.txt`), resolves each dependency's license via a
**mockable** lookup, classifies it against an **allow-list / deny-list** policy,
and prints a compliance report. Built test-first with [bats-core], validated by
`shellcheck` + `bash -n`, and exercised end-to-end through a real GitHub Actions
pipeline using [`act`].

## Files

| Path | Purpose |
|------|---------|
| `license-checker.sh` | The checker. Source-able (functions) + executable (`main`). |
| `licenses.config` | Policy: `allow:` / `deny:` license lines. |
| `license-db.tsv` | **Mock** license database (`name <TAB> version <TAB> license`). |
| `package.json` | Example manifest checked by CI. |
| `tests/license-checker.bats` | 26 unit tests (TDD). |
| `tests/workflow.bats` | Workflow **structure** tests (no `act`). |
| `tests/act-integration.bats` | Pipeline tests: every case runs through `act`. |
| `tests/workflow_structure.py` | YAML query helper for the structure tests. |
| `tests/mocks/mock-lookup.sh` | Mock external license-lookup command. |
| `tests/fixtures/` | Fixtures (manifests, config, db) for unit tests. |
| `.github/workflows/dependency-license-checker.yml` | The CI pipeline. |
| `act-result.txt` | Captured `act` output for all pipeline cases (generated). |

## Usage

```bash
./license-checker.sh --manifest package.json --config licenses.config --db license-db.tsv
./license-checker.sh --manifest requirements.txt --config licenses.config --db license-db.tsv --format json
```

Exit codes: `0` compliant · `1` denied license present · `2` unknown license
present (no denied) · `3` IO error · `64` usage error. Pass `--no-fail` for
report-only mode (always exit 0) — used by CI so the job stays green while the
report is logged. Drop `--no-fail` to make the pipeline an enforcing gate.

## Mocking the license lookup

The lookup is pluggable so it is hermetic and testable:

- **Static DB (default):** `--db license-db.tsv`. A `*` version is a wildcard.
- **External command:** `--lookup-cmd CMD` (or `LICENSE_LOOKUP_CMD=...`), invoked
  as `CMD <name> <version>`; empty output ⇒ `UNKNOWN`. See
  `tests/mocks/mock-lookup.sh`.

In production either path would query a package registry / license API; the tests
substitute the static file or the mock command instead of hitting the network.

## TDD

Developed red→green: each function (`detect_manifest_type`, `parse_manifest`,
`load_config`, `classify_license`, `load_db`, `lookup_license`, the report) got a
failing bats test first, then the minimum implementation, then refactor.

```bash
bats tests/license-checker.bats   # unit tests
bats tests/workflow.bats          # workflow structure tests
```

## CI pipeline (`act`)

The workflow checks out the repo, installs `bats`/`shellcheck` (jq ships with the
runner), runs `bash -n` + `shellcheck`, runs the bats unit tests **inside the
pipeline**, then runs the checker and emits text + JSON reports. A second
`summary` job `needs` the first (job dependency).

`tests/act-integration.bats` is the integration harness: for each case it builds
an isolated temp git repo with the project files + that case's fixture manifest,
runs `act push --rm`, appends the output to `act-result.txt`, and asserts the
exact expected report values plus that every job reports **Job succeeded**.

[bats-core]: https://github.com/bats-core/bats-core
[`act`]: https://github.com/nektos/act
