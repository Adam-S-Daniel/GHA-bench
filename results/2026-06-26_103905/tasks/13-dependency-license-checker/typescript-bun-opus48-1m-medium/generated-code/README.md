# Dependency License Checker

Parses a dependency manifest (`package.json` or `requirements.txt`), looks up
each dependency's license, and classifies it against an allow-list / deny-list,
producing a compliance report.

Built with **TypeScript + Bun**, developed using **red/green TDD**.

## Layout

| Path | Purpose |
| --- | --- |
| `src/types.ts` | Shared domain types/interfaces |
| `src/parser.ts` | Manifest parsing (`package.json`, `requirements.txt`) |
| `src/checker.ts` | License classification + report generation |
| `src/report.ts` | Mockable DB-backed license lookup + report formatting |
| `src/cli.ts` | CLI entry point wiring it all together |
| `fixtures/` | Default manifest, license config, and mock license DB |
| `tests/` | Bun test suite (unit + workflow structure + `act` harness) |
| `.github/workflows/dependency-license-checker.yml` | CI pipeline |

## Usage

```bash
bun run src/cli.ts \
  --manifest fixtures/package.json \
  --config   fixtures/license-config.json \
  --db       fixtures/license-db.json \
  --format   text          # or json
```

Exit code is `0` when compliant (no denied/unknown licenses) and `1` otherwise.

The **license lookup is mocked** via a JSON database file (`--db`) — a
deterministic, offline stand-in for a real registry query, used in both tests
and CI.

## Tests

```bash
bun test
```

- `parser/checker/report/cli` tests cover the core logic (TDD).
- `workflow.test.ts` parses the workflow YAML and asserts its structure +
  that `actionlint` passes.
- `act.test.ts` runs **every case through the GitHub Actions workflow** with
  `nektos/act`, appends output to `act-result.txt`, and asserts exact
  report values. It self-skips inside the act container (`ACT=true`).

## CI

The workflow installs Bun, runs the unit tests, and generates a compliance
report from the fixtures. It is report-only by default; set the
`workflow_dispatch` input `enforce: true` (or env `LICENSE_ENFORCE=true`) to
fail the build on a license violation.
