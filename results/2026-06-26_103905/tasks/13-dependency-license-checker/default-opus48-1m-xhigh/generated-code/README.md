# Dependency License Checker

Parse a dependency manifest, look up each dependency's license, classify it
against an allow-list / deny-list policy, and produce a compliance report
listing every dependency's status: **approved**, **denied**, or **unknown**.

## Files

| Path | Purpose |
|------|---------|
| `license_checker.py` | The checker library + CLI. |
| `tests/test_license_checker.py` | TDD unit tests (stdlib `unittest`) — run inside the act container. |
| `tests/test_workflow_structure.py` | Host-side workflow-structure + actionlint tests. |
| `run_act_tests.py` | End-to-end harness: runs every scenario through the workflow via `act`. |
| `fixtures/` | `policy.json` (allow/deny), `package.json` (manifest), `licenses.json` (mock license DB). |
| `.github/workflows/dependency-license-checker.yml` | The CI/CD workflow. |
| `act-result.txt` | Captured `act` output for every scenario (generated artifact). |

## How the license lookup is mocked

Real license discovery means querying a registry (npm, PyPI, …) over the
network — slow and non-deterministic. The lookup is therefore an **injectable
callable** `resolve(name, version) -> license | None`:

* In production it is built from a **license-database JSON file**
  (`make_license_resolver(db)`), keyed by `name@version` (exact) or bare `name`.
* In tests it is built from a plain `dict` — the mock the task asks for.

## Policy classification

`classify(license, policy)` is case-insensitive and **deny takes precedence over
allow** (fail safe). A missing/empty license is always `unknown`.

## CLI usage

```bash
python3 license_checker.py \
  --manifest fixtures/package.json \
  --policy   fixtures/policy.json \
  --license-db fixtures/licenses.json \
  --format text          # or: json
# Optional: --output report.txt   --fail-on-denied (exit 2 if any denied)
```

The text report ends with a machine-readable line CI can grep:

```
LICENSE-CHECK-SUMMARY total=4 approved=2 denied=1 unknown=1
```

Supported manifests: npm `package.json` (`*.json`) and pip `requirements.txt`
(`*.txt`); the format is auto-detected from the file name.

## TDD methodology

Built red → green: a failing `unittest` test was written first for each piece
(manifest parsing, error handling, classification, the mocked resolver, report
rendering, the CLI), then the minimum code to pass it. See the cycle-labelled
classes in `tests/test_license_checker.py`.

## Testing through the pipeline

Per the task, the functional scenarios run **through the GitHub Actions workflow
via `act`**, not against the script directly:

```bash
python3 run_act_tests.py   # builds a temp git repo per case, runs `act push --rm`
```

For each scenario the harness asserts `act` exited 0, that **both** jobs report
`Job succeeded`, and that the workflow emitted the **exact** expected summary and
per-dependency status line. Output is appended to `act-result.txt`. The
`unit-tests` job also runs the stdlib unit suite inside the container, so even
the TDD tests execute through the pipeline.

The workflow runs on `push`, `pull_request`, `workflow_dispatch`, and a weekly
`schedule`; uses `permissions: contents: read`; and has `license-check` depend
on `unit-tests` (`needs:`).
