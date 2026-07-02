# Dependency License Checker

Parses a dependency manifest (`package.json` or `requirements.txt`, auto-detected
by content), looks up each dependency's license through a mockable
`LicenseSource`, classifies it against allow/deny lists from a JSON config, and
prints a compliance report (`approved` / `denied` / `unknown` per dependency).

```bash
python3 license_checker.py \
  --manifest test-data/manifest \
  --config fixtures/config.json \
  --licenses fixtures/mock_licenses.json \
  [--fail-on-denied]   # exit 2 if anything is denied
```

## Layout

- `license_checker.py` — parser, config loader, `MockLicenseSource`, classifier, report renderer, CLI
- `tests/test_license_checker.py` — unit tests, built red/green TDD cycle by cycle (see module docstring)
- `tests/test_workflow_structure.py` — workflow YAML structure tests (triggers, jobs, referenced paths, actionlint)
- `fixtures/` — manifest fixtures, allow/deny config, mocked license database
- `.github/workflows/dependency-license-checker.yml` — CI: `test` job (pytest) → `license-report` job (runs the checker on `test-data/manifest`)
- `run_harness.py` — runs each test case through the workflow with `act push --rm` in a temp git repo, appends output to `act-result.txt`, and asserts exit codes, job success, and exact report lines

## Running

```bash
python3 -m pytest tests/ -v   # local suite (also runs inside the act container)
python3 run_harness.py        # full pipeline validation via act (writes act-result.txt)
```

The license lookup is mocked (`fixtures/mock_licenses.json`) so tests and CI are
deterministic and offline; swap `MockLicenseSource` for a real registry client in
production.
