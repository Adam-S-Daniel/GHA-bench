# Dependency License Checker

A small, dependency-light Bash tool that parses a dependency manifest
(`package.json` or `requirements.txt`), looks up each dependency's license via a
**mockable** lookup, classifies it against an allow-list / deny-list policy, and
prints a compliance report (text or JSON).

Built test-first with [bats-core](https://github.com/bats-core/bats-core) and
wired into a GitHub Actions pipeline that is exercised end-to-end with
[`act`](https://github.com/nektos/act).

## Layout

```
license-checker.sh                       # the tool (POSIX-ish bash, shellcheck-clean)
config/license-policy.conf               # allow/deny policy (the "config")
fixtures/package.json                     # default manifest (out-of-the-box demo)
fixtures/license-db.txt                   # mock license database (the lookup seam)
tests/license-checker.bats               # TDD unit tests (27 cases)
tests/workflow.bats                       # workflow structure + act integration tests
tests/check_workflow.py                   # YAML structure validator
tests/cases/{approved,denied,requirements}/   # per-case fixtures for the act harness
.github/workflows/dependency-license-checker.yml
```

## Usage

```bash
./license-checker.sh \
    --manifest fixtures/package.json \
    --config   config/license-policy.conf \
    --license-db fixtures/license-db.txt
```

Options:

| Flag | Meaning |
| --- | --- |
| `--manifest <file>` | Manifest to scan; format auto-detected from content. |
| `--config <file>` | License policy (allow/deny lists). |
| `--license-db <file>` | Mock license database (`name=License`). Absent ⇒ UNKNOWN. |
| `--format text\|json` | Output format (default `text`). |
| `--fail-on-denied` | Exit `1` if any dependency is DENIED. |
| `-h, --help` | Usage. |

Exit codes: `0` ok · `1` denied found (with `--fail-on-denied`) · `2` usage
error · `3` input error.

### How a license is classified

1. Look the dependency up in the license database (the mocked seam). Not
   found ⇒ `unknown`.
2. License on the **deny** list ⇒ `denied` (deny wins over allow).
3. License on the **allow** list ⇒ `approved`.
4. Otherwise (known but unlisted, or undetermined) ⇒ `unknown`.

Comparison is case-insensitive; the deny list takes precedence so a license that
appears on both lists is rejected.

## Mocking the license lookup

The only impure part of the checker — "what license does package X use?" — is
isolated behind `lookup_license`, which reads a plain-text database file passed
via `--license-db`. Tests point this at a fixture, making every run deterministic
and offline. Swapping in a real resolver (an SPDX API, `license-checker`, etc.)
means replacing that one function.

## Testing

```bash
# Fast unit tests (TDD)
bats tests/license-checker.bats

# Workflow structure checks + full act pipeline (one `act push` per case)
bats tests/workflow.bats
```

`tests/workflow.bats` builds a throwaway git repo per case, runs the workflow
with `act push --rm`, appends the full output to `act-result.txt`, and asserts on
the **exact** report values and that every job reports `Job succeeded`.

## CI pipeline

`.github/workflows/dependency-license-checker.yml` runs on push, pull_request, a
weekly schedule, and manual dispatch:

- **lint-and-test** — installs bats + shellcheck, runs `bash -n`, `shellcheck`,
  and the bats unit suite.
- **license-check** (`needs: lint-and-test`) — resolves the manifest, generates
  the compliance report, publishes it to the job summary, and runs a policy
  gate. The gate is report-only by default and can be made strict via the
  `fail_on_denied` dispatch input.
