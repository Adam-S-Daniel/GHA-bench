# dependency-license-checker

TypeScript/Bun tool that parses a dependency manifest (`package.json` or
`requirements.txt`), resolves each dependency's license, checks it against an
allow/deny license config, and prints a compliance report classifying every
dependency as **approved**, **denied**, or **unknown**.

Built with red/green TDD — each module's test file was written first, run to
failure, then implemented (see git-style progression in `tests/`).

## Usage

```bash
bun run src/cli.ts \
  --manifest tests/fixtures/npm/package.json \
  --config tests/fixtures/license-config.json \
  --licenses tests/fixtures/licenses.json \
  [--strict]   # exit 2 if any denied license is found
```

License data comes from a local JSON "license database" (`--licenses`) mapping
package name → SPDX id. This is the injectable `LicenseLookup` seam: production
could back it with a registry client; tests inject in-memory mocks.

## Layout

- `src/manifest.ts` — parse package.json / requirements.txt into `Dependency[]`
- `src/lookup.ts` — file-backed `LicenseLookup` (the mockable seam)
- `src/config.ts` — load/validate the allow/deny config
- `src/checker.ts` — classify each dependency (deny wins over allow; case-insensitive)
- `src/report.ts` — deterministic plain-text report for CI log assertions
- `src/cli.ts` — argument parsing, wiring, exit codes (0 ok / 1 input error / 2 strict-denied)
- `tests/` — unit + CLI + workflow-structure tests (`bun test`), fixtures in `tests/fixtures/`

## CI

`.github/workflows/dependency-license-checker.yml` runs `bun test` and the
checker on push/PR/schedule/dispatch. Inputs can be overridden by dropping
files into `ci-input/` (manifest, `license-config.json`, `licenses.json`);
otherwise the committed fixtures are used.

End-to-end pipeline tests: `bun run scripts/act-harness.ts` builds a temp git
repo per test case, runs the workflow via `act push --rm`, and asserts exact
report lines and job success. Full output lands in `act-result.txt`.
