# Dependency License Checker

A small TypeScript/Bun tool that parses a dependency manifest, looks up each
dependency's license (via a **mockable** lookup), checks every license against
an **allow-list / deny-list**, and produces a compliance report classifying each
dependency as **approved**, **denied**, or **unknown**.

Built with red/green TDD using Bun's built-in test runner.

## Files

| File | Purpose |
| --- | --- |
| `license-checker.ts` | Library (pure parse/check/report core) **and** the CLI entrypoint. |
| `license-checker.test.ts` | Unit tests for the library + CLI (no network, no Docker). |
| `workflow.test.ts` | Workflow structure tests + end-to-end `act` integration tests. |
| `fixtures/` | Sample manifest, allow/deny config, and mock license database. |
| `.github/workflows/dependency-license-checker.yml` | CI pipeline that runs the checker. |

## How it works

1. **Parse** a manifest into `{ name, version }[]`. Supports `package.json`
   (merges `dependencies`, `devDependencies`, `peerDependencies`,
   `optionalDependencies`) and `requirements.txt` (pip specifiers, extras,
   comments, and `-r`/option lines).
2. **Look up** each dependency's license. The lookup is an injectable function
   (`LicenseLookup`), so tests pass a mock and CI passes a JSON-backed
   "database" — keeping the whole pipeline deterministic and offline. Keys may
   be `name` or `name@version` (the version-specific entry wins).
3. **Classify** each license against the config: deny-list wins over allow-list;
   missing/unlisted licenses are `unknown`. Matching is case-insensitive.
4. **Report** as greppable text or JSON, with a summary and a compliance verdict.

## Usage

```bash
bun run license-checker.ts \
  --manifest fixtures/package.json \
  --config   fixtures/config.json \
  --licenses fixtures/licenses.json \
  --format   text        # or: json
```

Options: `--type`, `--output <path>`, `--strict` (exit 1 on a denied
dependency), `--fail-on-unknown` (with `--strict`, also fail on unknown),
`--help`. Exit codes: `0` ok, `1` compliance failure (`--strict`), `2`
usage/IO error.

### Config format (`config.json`)

```json
{ "allow": ["MIT", "Apache-2.0"], "deny": ["GPL-3.0", "AGPL-3.0"] }
```

### Mock license database (`licenses.json`)

```json
{ "left-pad": "MIT", "left-pad@1.3.0": "MIT", "copyleft-lib": "GPL-3.0" }
```

A dependency absent from the database resolves to `unknown`.

## Testing

```bash
bun test                         # everything (unit + structure + act integration)
bun test license-checker.test.ts # fast unit/CLI tests only
```

The `act` integration tests (`workflow.test.ts`) build a throwaway git repo per
test case, run the workflow via `act push` in Docker, append the full output to
`act-result.txt`, and assert on exact report values and `Job succeeded`.

## CI pipeline

`.github/workflows/dependency-license-checker.yml` runs on push, pull_request, a
weekly schedule, and on demand. Two jobs with a dependency edge: `unit-tests`
runs `bun test`, then `license-compliance` runs the checker against the fixtures,
writes a job summary, and annotates (without failing) when non-compliant — a
report-only gate that always surfaces results for triage.
