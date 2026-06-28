# Dependency License Checker

Parses a dependency manifest (`package.json` or a pip `requirements.txt`), looks
up each dependency's license, classifies it against an allow / deny policy, and
prints a compliance report. Written in **TypeScript** and run with **Bun**.

## Layout

| File | Purpose |
|------|---------|
| `src/lib.ts` | Pure, fully-tested core logic (parse → look up → classify → format). |
| `src/app.ts` | Thin CLI: reads files, wires the library together, sets exit codes. |
| `tests/lib.test.ts` | Unit tests (TDD) for every library function, with a **mocked** license lookup. |
| `tests/workflow.test.ts` | Workflow structure tests **+** end-to-end tests that run the real workflow through `act`. |
| `fixtures/ci/` | Default manifest / policy / license-database used by the workflow. |
| `.github/workflows/dependency-license-checker.yml` | The CI pipeline. |

## How the license lookup is mocked

The lookup is an injected function (`LicenseLookup`). Tests pass a `mock()` or a
small in-memory map; CI backs it with a static JSON "license database"
(`fixtures/ci/licenses.json`) via `createLookupFromMap`. Nothing ever hits the
network — deterministic and offline-friendly.

## CLI usage

```bash
bun run src/app.ts \
  --manifest fixtures/ci/manifest.json \
  --config   fixtures/ci/policy.json \
  --licenses fixtures/ci/licenses.json \
  --format   text          # text | json | kv
# Optional gates: --strict (fail on denied), --fail-on-unknown
```

Classification rules: a license on the **deny** list → `denied` (deny wins over
allow); on the **allow** list → `approved`; missing or unlisted → `unknown`.
Matching is case-insensitive.

Exit codes: `0` success · `1` gate violation (only with `--strict` /
`--fail-on-unknown`) · `2` usage/runtime error.

## Tests

```bash
bun test                                   # everything (unit + structure + act)
bun test tests/lib.test.ts                 # fast unit tests only
bun test tests/workflow.test.ts -t "workflow structure"   # fast structure checks only
```

The `act` layer builds an isolated temp git repo per case, runs `act push --rm`
in Docker, appends the full output to `act-result.txt`, and asserts on the exact
expected report values.

## CI workflow

Triggers on push / PR / weekly schedule / manual dispatch. The `license-check`
job installs Bun, runs the checker (writing a job summary and exposing the
summary counts as job outputs); the `compliance-gate` job `needs` it and reports
the decision. The pipeline is **report-only** (always exits 0) so it surfaces
violations without blocking — flip to blocking by adding `--strict`.
