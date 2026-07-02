# Dependency License Checker

Parses a dependency manifest (`package.json` or `requirements.txt`), looks up
each dependency's license in a mock license database, classifies it against an
allow-list / deny-list config, and prints a compliance report
(`APPROVED` / `DENIED` / `UNKNOWN` per dependency, plus exact summary counts).

Built with plain Node.js (no external packages — tests use the built-in
`node:test` runner), developed red/green TDD: each function in
`license-checker.js` was written only after a failing test in
`license-checker.test.js` demanded it.

## Files

| File | Purpose |
| --- | --- |
| `license-checker.js` | Library + CLI (parse → mock lookup → classify → report) |
| `license-checker.test.js` | 19 unit tests, mock license DB injected as a plain object |
| `checker-config.json` | Allow/deny license config used by CI |
| `mock-licenses.json` | Mock license database (stands in for a registry lookup) |
| `test-manifest/` | Manifest directory the workflow scans (default: Node fixture) |
| `fixtures/` | Per-case manifests for the act pipeline tests |
| `.github/workflows/dependency-license-checker.yml` | CI pipeline: `test` job → `license-check` job |
| `workflow-structure.test.py` | Workflow YAML structure tests + actionlint gate |
| `run-act-tests.sh` | Runs every test case through the workflow via `act`, asserts exact output, writes `act-result.txt` |

## Usage

```sh
node license-checker.js --manifest-dir test-manifest \
  --config checker-config.json --licenses mock-licenses.json [--strict]
```

Exit codes: `0` report generated (`--strict` adds `1` = denied licenses found);
`2` = usage or input error (missing manifest, unreadable/invalid JSON, …).
Classification rules: deny-list wins over allow-list; unresolvable or unlisted
licenses are `UNKNOWN`; matching is case-insensitive.

## Running the tests

```sh
node --test                        # unit tests
python3 workflow-structure.test.py # workflow structure + actionlint
./run-act-tests.sh                 # full pipeline tests through act (Docker)
./run-act-tests.sh --assert-only   # re-assert against captured act-result.txt
```
