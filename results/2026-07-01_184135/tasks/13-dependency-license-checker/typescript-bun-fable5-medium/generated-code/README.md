# Dependency License Checker

TypeScript/Bun tool that parses a dependency manifest (`package.json` or
`requirements.txt`), resolves each dependency's license via a local JSON
license database, classifies it against an allow/deny config, and prints a
compliance report (`approved` / `denied` / `unknown`).

## Usage

```sh
bun run src/cli.ts \
  --manifest fixtures/manifests/package.json \
  --config fixtures/license-config.json \
  --licenses fixtures/license-db.json \
  [--strict]   # exit 1 if any denied license is found
```

Exit codes: `0` success, `1` denied licenses under `--strict`, `2` usage/input error.

## Layout

- `src/parse.ts` — manifest parsing (package.json, requirements.txt)
- `src/check.ts` — allow/deny classification (deny wins; unlisted → unknown)
- `src/report.ts` — report generation (license lookup injected, mockable) + formatting
- `src/lookup.ts` / `src/config.ts` — JSON-file-backed lookup and config loaders
- `src/cli.ts` — CLI wiring
- `tests/` — bun test suite (built with red/green TDD; lookup mocked in-memory)
- `.github/workflows/dependency-license-checker.yml` — CI workflow (unit tests job → compliance report job)
- `scripts/act-harness.ts` — runs each fixture case through the workflow via `act` and asserts exact output; writes `act-result.txt`

## Testing

```sh
bun test                        # unit + workflow-structure tests
bun run scripts/act-harness.ts  # end-to-end via act (requires Docker)
```
