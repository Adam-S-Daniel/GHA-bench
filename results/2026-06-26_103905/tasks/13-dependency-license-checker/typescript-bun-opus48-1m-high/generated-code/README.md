# Dependency License Checker

Parses a dependency manifest (`package.json` or `requirements.txt`), resolves
each dependency's license, classifies it against an allow-list / deny-list, and
emits a compliance report. Built with **TypeScript + Bun** using red/green TDD.

## Layout

```
src/
  types.ts     Shared domain types (Dependency, LicensePolicy, ComplianceReport, ...)
  parser.ts    Manifest parsing (package.json + requirements.txt), version normalization
  policy.ts    Policy loading + license classification (deny beats allow, case-insensitive)
  lookup.ts    License lookup seam — database-backed (the mock + offline CI source)
  report.ts    Report generation (pure core) + stable text formatting
  cli.ts       Arg parsing + IO orchestration; runCli() returns {output, exitCode}
tests/         Unit + workflow-structure tests (run with `bun test tests/`)
  fixtures/    Sample manifest / policy / license-database used by the CLI tests
fixtures/      Default fixtures the workflow runs against in plain CI
act-harness.test.ts   End-to-end harness: drives the workflow through `act`
.github/workflows/dependency-license-checker.yml   CI pipeline
```

## Design

- **The license lookup is a seam** (`LicenseLookup = (dep) => string | null`).
  In tests and CI it is backed by a static JSON database (`createDatabaseLookup`),
  which is the required mock and keeps runs deterministic and offline. Swapping in
  a registry/SPDX-scanner implementation later touches nothing else.
- **Classification precedence:** deny-list wins over allow-list; anything on
  neither list (or with no resolvable license) is `unknown`. `failOnUnknown`
  controls whether `unknown` fails the report.
- **Compliance is data, not a crash.** A denied dependency yields `RESULT: FAIL`
  and a non-zero *checker* exit, but the CI *job* still succeeds — the verdict is
  captured in the log (`CHECKER_EXIT`) so the pipeline reports rather than aborts.

## Usage

```bash
bun run src/cli.ts --manifest <package.json|requirements.txt> \
  --policy <policy.json> --database <licenses.json> [--format text|json]
```

Exit codes: `0` compliant, `1` non-compliant, `2` usage/IO/parse error.

## Testing

```bash
bun test tests/        # fast unit + workflow-structure tests (no Docker)
bun test               # the above PLUS the act-harness (drives the CI pipeline)
```

The act harness builds an isolated temp git repo per case, runs `act push --rm`,
appends each run's output to `act-result.txt`, and asserts exact expected values
(per-dependency status, summary line, verdict, checker exit) plus `Job succeeded`.
